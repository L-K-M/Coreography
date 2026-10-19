import Foundation
import CoreographyDrivers

/// One process's TCP and UDP byte rates over the last interval.
public struct ProcessTrafficReading: Codable, Equatable, Sendable {
    /// The kernel's unique process ID, which a reused PID never shares.
    public let uniqueID: UInt64
    public let pid: Int32
    public let name: String
    public let receivedBytesPerSecond: MetricReading
    public let sentBytesPerSecond: MetricReading
}

/// Per-process network rates at one moment (plan S3: per-app network).
/// Processes seen for the first time are collecting; a process that
/// stopped using the network is absent, not zero, until it reappears.
public struct ProcessTrafficSnapshot: Codable, Sendable {
    public let stamp: SampleStamp
    public let processes: [ProcessTrafficReading]
    /// Connections that closed before naming their process, and the kernel's own.
    public let unattributedReceivedBytesPerSecond: MetricReading
    public let unattributedSentBytesPerSecond: MetricReading
    /// Why nothing could be read, when nothing could.
    public let unavailableReason: String?

    /// Rates by PID, for joining to a process sample of the same moment.
    public func byPID() -> [Int32: ProcessTrafficReading] {
        Dictionary(processes.map { ($0.pid, $0) }) { first, second in
            first.uniqueID > second.uniqueID ? first : second
        }
    }
}

/// Byte rates come from counter deltas over the real elapsed interval,
/// per unique process, so a reused PID never inherits another process's
/// bytes and a closed connection's bytes are not lost.
public actor ProcessTrafficMonitor {
    private static let source = MetricSource(provider: "network", driver: "NetworkStatistics", channel: "TCP and UDP sources")
    private let driver: any ProcessTrafficSampleReading
    private let maximumGap: Duration
    private var trackers: [UInt64: (received: CounterRateTracker, sent: CounterRateTracker)] = [:]
    private var unattributed: (received: CounterRateTracker, sent: CounterRateTracker)

    public init() throws { try self.init(driver: ProcessTrafficDriver()) }

    init(driver: any ProcessTrafficSampleReading, maximumGap: Duration = .seconds(5)) throws {
        self.driver = driver
        self.maximumGap = maximumGap
        unattributed = (
            try CounterRateTracker(maxGap: maximumGap, source: Self.source),
            try CounterRateTracker(maxGap: maximumGap, source: Self.source)
        )
    }

    public func reset() {
        trackers.removeAll()
        unattributed.received.reset()
        unattributed.sent.reset()
    }

    public func sample() async throws -> ProcessTrafficSnapshot {
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds, wallTime: raw.wallTime)

        let traffic: [RawProcessTraffic]
        switch raw.traffic {
        case .failure(let error):
            reset()
            let reason = switch error {
            case .unsupportedPlatform: "Per-process network needs macOS"
            case .unavailable(let detail): detail
            }
            let missing = MetricReading.unsupported(reason: reason, source: Self.source)
            return ProcessTrafficSnapshot(
                stamp: stamp, processes: [], unattributedReceivedBytesPerSecond: missing,
                unattributedSentBytesPerSecond: missing, unavailableReason: reason
            )
        case .success(let read):
            traffic = read
        }

        var seen: Set<UInt64> = []
        var readings: [ProcessTrafficReading] = []
        for process in traffic {
            seen.insert(process.uniqueID)
            var pair = try trackers[process.uniqueID] ?? (
                CounterRateTracker(maxGap: maximumGap, source: Self.source),
                CounterRateTracker(maxGap: maximumGap, source: Self.source)
            )
            let received = pair.received.record(process.receivedBytes, at: stamp)
            let sent = pair.sent.record(process.sentBytes, at: stamp)
            trackers[process.uniqueID] = pair
            readings.append(ProcessTrafficReading(
                uniqueID: process.uniqueID, pid: process.pid, name: process.name,
                receivedBytesPerSecond: received, sentBytesPerSecond: sent
            ))
        }
        // A process with no traffic left has no baseline to keep.
        trackers = trackers.filter { seen.contains($0.key) }

        return ProcessTrafficSnapshot(
            stamp: stamp, processes: readings,
            unattributedReceivedBytesPerSecond: unattributed.received.record(raw.unattributedReceivedBytes, at: stamp),
            unattributedSentBytesPerSecond: unattributed.sent.record(raw.unattributedSentBytes, at: stamp),
            unavailableReason: nil
        )
    }
}
