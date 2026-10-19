import Foundation
import CoreographyDrivers

/// Per-process GPU time in ms/s from per-client GPU time counters (plan:
/// per-app GPU time, a different scale than device busy %). Overlapping
/// command queues can add up past the wall clock, so it is not a share
/// and is not capped.
///
/// Each client's time is a counter of its own, so a client that closes
/// drops out without pulling its process backwards, and one opened since
/// the last walk counts all of its time:
///
/// ```text
/// walk 1           client 7 (pid 40) 100 ms
/// walk 2, 1 s on   client 7 (pid 40) 160 ms, client 9 (pid 40) 30 ms
/// pid 40           (160 − 100) + 30 = 90 ms in 1 s → 90 ms/s
/// ```
struct GPUTimeLedger {
    enum Usage: Equatable {
        case collecting
        case gap(String)
        case unavailable(String)
        case unsupported(String)
        /// GPU milliseconds per second by PID; a PID without clients used none.
        case millisecondsPerSecond([Int32: Double])
    }

    private struct Walk {
        let clockID: UUID
        let monotonicNanoseconds: UInt64
        let times: [UInt64: UInt64]
        let isComplete: Bool
    }

    private static let millisecondsPerSecond = 1_000.0
    private static let nanosecondsPerSecond = 1_000_000_000.0
    private let maximumGapNanoseconds: Double
    private var previous: Walk?

    init(maximumGap: Duration) {
        let (seconds, attoseconds) = maximumGap.components
        maximumGapNanoseconds = Double(seconds) * Self.nanosecondsPerSecond + Double(attoseconds) / Self.nanosecondsPerSecond
    }

    mutating func reset() { previous = nil }

    mutating func record(_ snapshot: RawGPUClientSnapshot) -> Usage {
        let walk: GPUClientWalk
        switch snapshot.walk {
        case .failure(let error):
            previous = nil
            return switch error {
            case .unsupportedPlatform: .unsupported("Per-process GPU time needs macOS")
            case .unavailable(let reason): .unavailable(reason)
            case .systemCall(let operation, let code): .unavailable("\(operation) failed (\(code))")
            }
        case .success(let read):
            walk = read
        }

        let times = Dictionary(walk.clients.map { ($0.registryEntryID, $0.gpuNanoseconds) }) { first, _ in first }
        let before = previous
        previous = Walk(
            clockID: snapshot.clockID, monotonicNanoseconds: snapshot.monotonicNanoseconds,
            times: times, isComplete: walk.isComplete
        )
        guard let before, before.clockID == snapshot.clockID,
              snapshot.monotonicNanoseconds > before.monotonicNanoseconds else { return .collecting }
        let elapsed = Double(snapshot.monotonicNanoseconds - before.monotonicNanoseconds)
        guard elapsed <= maximumGapNanoseconds else { return .gap("GPU clients were not read within the maximum gap") }

        var used: [Int32: UInt64] = [:]
        for client in walk.clients {
            let delta: UInt64
            if let earlier = before.times[client.registryEntryID] {
                // A smaller count is a driver reset, not negative time.
                delta = client.gpuNanoseconds >= earlier ? client.gpuNanoseconds - earlier : 0
            } else {
                // New since a complete walk, so all its time is recent; after an
                // incomplete one it may be old, and only counts from now on.
                delta = before.isComplete ? client.gpuNanoseconds : 0
            }
            let sum = used[client.pid, default: 0].addingReportingOverflow(delta)
            used[client.pid] = sum.overflow ? .max : sum.partialValue
        }
        return .millisecondsPerSecond(used.mapValues { Double($0) * Self.millisecondsPerSecond / elapsed })
    }
}
