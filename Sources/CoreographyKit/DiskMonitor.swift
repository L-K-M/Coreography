import Foundation
import CoreographyDrivers

public actor DiskMonitor {
    private static let nanosecondsPerSecond = 1_000_000_000.0
    private static let source = MetricSource(
        provider: "disk", driver: "IOKit", channel: "IOBlockStorageDriver / Statistics; bytes"
    )
    private let driver: any DiskSampleReading
    private let maximumGap: Duration
    private var previousStamp: SampleStamp?
    private var rates: [StorageDeviceID: DeviceRates] = [:]
    private var buffer: SampleBuffer<DiskSnapshot>

    public init() throws { try self.init(driver: DiskIODriver()) }

    init(
        driver: any DiskSampleReading, maximumGap: Duration = .seconds(3), historyCapacity: Int = 60
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

    public func history() -> [DiskSnapshot] { buffer.elements }

    public func sample() async throws -> DiskSnapshot {
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(
            clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds, wallTime: raw.wallTime
        )
        let interrupted = updateContinuity(stamp)
        if interrupted { rates.removeAll() }
        var devices: [DiskDeviceReading] = []
        var issues: [DiskCollectionIssue] = []
        let enumerationReading: MetricReading
        let truncated: Bool
        switch raw.enumeration {
        case .failure(let error):
            rates.removeAll()
            enumerationReading = try missing(error)
            truncated = false
        case .success(let enumeration):
            truncated = enumeration.isTruncated
            enumerationReading = try .measured(
                Double(enumeration.devices.count + enumeration.failures.count), source: Self.source
            )
            issues = try enumeration.failures.map {
                DiskCollectionIssue(registryEntryID: $0.registryEntryID, reading: try missing($0.error))
            }
            var nextRates: [StorageDeviceID: DeviceRates] = [:]
            var seen: Set<StorageDeviceID> = []
            for device in enumeration.devices {
                guard let identity = try? StorageDeviceID(registryEntryID: device.registryEntryID),
                      device.monotonicNanoseconds <= stamp.monotonicNanoseconds,
                      seen.insert(identity).inserted else {
                    issues.append(DiskCollectionIssue(
                        registryEntryID: device.registryEntryID,
                        reading: try .unavailable(reason: "Invalid or duplicate storage observation", source: Self.source)
                    ))
                    continue
                }
                let age = Double(stamp.monotonicNanoseconds - device.monotonicNanoseconds)
                    / Self.nanosecondsPerSecond
                let deviceStamp = SampleStamp(
                    clockID: stamp.clockID, monotonicNanoseconds: device.monotonicNanoseconds,
                    wallTime: stamp.wallTime.addingTimeInterval(-age)
                )
                let read: MetricReading
                let written: MetricReading
                switch device.counters {
                case .failure(let error):
                    read = try missing(error)
                    written = read
                case .success(let counters):
                    var state = try rates[identity] ?? DeviceRates(maximumGap: maximumGap)
                    let readRate = state.read.record(counters.readBytes, at: deviceStamp)
                    let writeRate = state.written.record(counters.writtenBytes, at: deviceStamp)
                    let gap = MetricReading.gap(reason: "Sampling interrupted", source: Self.source)
                    read = interrupted ? gap : readRate
                    written = interrupted ? gap : writeRate
                    nextRates[identity] = state
                }
                devices.append(DiskDeviceReading(
                    id: identity, name: device.name, stamp: deviceStamp,
                    readBytesPerSecond: read, writtenBytesPerSecond: written
                ))
            }
            rates = nextRates
        }
        let snapshot = DiskSnapshot(
            id: UUID(), stamp: stamp, enumeration: enumerationReading, enumerationTruncated: truncated,
            devices: devices, issues: issues, continuity: interrupted ? .interrupted : .continuous
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

    private func missing(_ error: DiskDriverError) throws -> MetricReading {
        switch error {
        case .unsupportedPlatform: .unsupported(reason: "Native storage sampling requires macOS", source: Self.source)
        case .unavailable(let reason): try .unavailable(reason: reason, source: Self.source)
        case .restricted(let code): try .restricted(reason: "Storage access denied (\(code))", source: Self.source)
        case .systemCall(let operation, let code):
            try .unavailable(reason: "\(operation) failed (\(code))", source: Self.source)
        }
    }

    private struct DeviceRates {
        var read: CounterRateTracker
        var written: CounterRateTracker

        init(maximumGap: Duration) throws {
            read = try CounterRateTracker(maxGap: maximumGap, source: source)
            written = try CounterRateTracker(maxGap: maximumGap, source: source)
        }
    }
}
