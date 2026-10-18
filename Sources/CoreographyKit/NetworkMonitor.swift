import Foundation
import CoreographyDrivers

public actor NetworkMonitor {
    private static let nanosecondsPerSecond = 1_000_000_000.0
    private static let source = MetricSource(
        provider: "network", driver: "sysctl", channel: "IFMIB_IFDATA / IFDATA_GENERAL; 64-bit bytes"
    )
    private static let primarySource = MetricSource(
        provider: "network", driver: "SystemConfiguration", channel: "PrimaryInterface; IPv4 then IPv6"
    )
    private let driver: any NetworkSampleReading
    private let maximumGap: Duration
    private var previousStamp: SampleStamp?
    private var rates: [NetworkInterfaceID: InterfaceRates] = [:]
    private var buffer: SampleBuffer<NetworkSnapshot>

    public init() throws { try self.init(driver: NetworkInterfacesDriver()) }

    init(
        driver: any NetworkSampleReading, maximumGap: Duration = .seconds(3), historyCapacity: Int = 60
    ) throws {
        _ = try CounterRateTracker(maxGap: maximumGap)
        self.driver = driver
        self.maximumGap = maximumGap
        self.buffer = try SampleBuffer(capacity: historyCapacity)
    }

    public func reset() {
        previousStamp = nil
        rates.removeAll()
        buffer.removeAll()
    }

    public func history() -> [NetworkSnapshot] { buffer.elements }

    public func sample() async throws -> NetworkSnapshot {
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(
            clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds, wallTime: raw.wallTime
        )
        let interrupted = updateContinuity(stamp)
        if interrupted { rates.removeAll() }
        var interfaces: [NetworkInterfaceReading] = []
        var issues: [NetworkCollectionIssue] = []
        let enumerationReading: MetricReading
        let truncated: Bool
        switch raw.enumeration {
        case .failure(let error):
            rates.removeAll()
            enumerationReading = try missing(error, source: Self.source)
            truncated = false
        case .success(let enumeration):
            truncated = enumeration.isTruncated
            enumerationReading = try .measured(
                Double(enumeration.interfaces.count + enumeration.failures.count), source: Self.source
            )
            issues = try enumeration.failures.map {
                NetworkCollectionIssue(index: $0.index, reading: try missing($0.error, source: Self.source))
            }
            var nextRates: [NetworkInterfaceID: InterfaceRates] = [:]
            var seen: Set<NetworkInterfaceID> = []
            for interface in enumeration.interfaces {
                guard let identity = try? NetworkInterfaceID(index: interface.index, name: interface.name),
                      interface.monotonicNanoseconds <= stamp.monotonicNanoseconds,
                      seen.insert(identity).inserted else {
                    issues.append(NetworkCollectionIssue(
                        index: interface.index,
                        reading: try .unavailable(reason: "Invalid or duplicate interface observation", source: Self.source)
                    ))
                    continue
                }
                let age = Double(stamp.monotonicNanoseconds - interface.monotonicNanoseconds)
                    / Self.nanosecondsPerSecond
                let interfaceStamp = SampleStamp(
                    clockID: stamp.clockID, monotonicNanoseconds: interface.monotonicNanoseconds,
                    wallTime: stamp.wallTime.addingTimeInterval(-age)
                )
                let received: MetricReading
                let sent: MetricReading
                if interface.linkState == .down {
                    received = try .unavailable(reason: "Interface link is down", source: Self.source)
                    sent = received
                } else {
                    var state = try rates[identity] ?? InterfaceRates(maximumGap: maximumGap)
                    let receiveRate = state.received.record(interface.receivedBytes, at: interfaceStamp)
                    let sendRate = state.sent.record(interface.sentBytes, at: interfaceStamp)
                    let gap = MetricReading.gap(reason: "Sampling interrupted", source: Self.source)
                    received = interrupted ? gap : receiveRate
                    sent = interrupted ? gap : sendRate
                    nextRates[identity] = state
                }
                interfaces.append(NetworkInterfaceReading(
                    id: identity, stamp: interfaceStamp, linkState: interface.linkState,
                    receivedBytesPerSecond: received, sentBytesPerSecond: sent
                ))
            }
            rates = nextRates
        }

        let primary: NetworkInterfaceID?
        let family: PrimaryInterfaceFamily?
        let primaryIssue: MetricReading?
        switch raw.primaryInterface {
        case .success(let reported):
            let matches = interfaces.filter { $0.id.name == reported.name }
            primary = matches.count == 1 ? matches.first?.id : nil
            family = reported.family
            primaryIssue = primary == nil
                ? try .unavailable(reason: "Primary interface is absent or ambiguous in this enumeration", source: Self.primarySource)
                : nil
        case .failure(let error):
            primary = nil
            family = nil
            primaryIssue = try missing(error, source: Self.primarySource)
        }
        let snapshot = NetworkSnapshot(
            id: UUID(), stamp: stamp, enumeration: enumerationReading,
            enumerationTruncated: truncated, interfaces: interfaces, issues: issues,
            primaryInterface: primary, primaryFamily: family,
            primaryIssue: primaryIssue,
            continuity: interrupted ? .interrupted : .continuous
        )
        buffer.append(snapshot)
        return snapshot
    }

    private func updateContinuity(_ stamp: SampleStamp) -> Bool {
        defer { previousStamp = stamp }
        guard let previous = previousStamp else { return false }
        let wallElapsed = stamp.wallTime.timeIntervalSince(previous.wallTime)
        if wallElapsed < 0 || stamp.clockID != previous.clockID { buffer.removeAll() }
        guard stamp.clockID == previous.clockID,
              stamp.monotonicNanoseconds > previous.monotonicNanoseconds else { return true }
        let components = maximumGap.components
        let gapSeconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return wallElapsed < 0 || wallElapsed > gapSeconds
            || Duration.nanoseconds(stamp.monotonicNanoseconds - previous.monotonicNanoseconds) > maximumGap
    }

    private func missing(_ error: NetworkDriverError, source: MetricSource) throws -> MetricReading {
        switch error {
        case .unsupportedPlatform:
            .unsupported(reason: "Native interface sampling requires macOS", source: source)
        case .unavailable(let reason):
            try .unavailable(reason: reason, source: source)
        case .restricted(let code):
            try .restricted(reason: "Interface access denied (\(code))", source: source)
        case .systemCall(let operation, let code):
            try .unavailable(reason: "\(operation) failed (\(code))", source: source)
        }
    }

    private struct InterfaceRates {
        var received: CounterRateTracker
        var sent: CounterRateTracker

        init(maximumGap: Duration) throws {
            received = try CounterRateTracker(maxGap: maximumGap, source: source)
            sent = try CounterRateTracker(maxGap: maximumGap, source: source)
        }
    }
}
