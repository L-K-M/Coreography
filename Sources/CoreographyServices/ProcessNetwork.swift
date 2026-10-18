import Foundation
import CoreographyKit

public typealias CapturedTraffic = ProcessTrafficSnapshot

/// Joins per-process network rates to a process sample (plan S3).
///
/// NetworkStatistics names processes by PID and short name. A row takes a
/// rate only when both agree, so a PID reused since the traffic sample
/// never borrows another process's bytes. A process with no open TCP or
/// UDP socket is absent from the traffic sample: it moved nothing, which
/// is a measured zero, not missing data.
enum ProcessNetwork {
    static func rates(
        for process: ObservedProcess, in traffic: CapturedTraffic?
    ) -> (received: MetricReading, sent: MetricReading) {
        guard let traffic else {
            let collecting = MetricReading.collecting()
            return (collecting, collecting)
        }
        if let reason = traffic.unavailableReason {
            let missing = MetricReading.unsupported(reason: reason)
            return (missing, missing)
        }
        guard let reading = traffic.byPID()[process.id.pid] else {
            let idle = (try? MetricReading.measured(0)) ?? .collecting()
            return (idle, idle)
        }
        guard sameProcess(process.name, reading.name) else {
            let collecting = MetricReading.collecting()
            return (collecting, collecting)
        }
        return (reading.receivedBytesPerSecond, reading.sentBytesPerSecond)
    }

    /// The kernel's short command name is a prefix of the full process name, or the reverse.
    private static func sameProcess(_ observed: String, _ reported: String) -> Bool {
        observed.hasPrefix(reported) || reported.hasPrefix(observed)
    }

    /// Received plus sent, for sorting; nil while either is unknown.
    static func total(_ received: MetricReading, _ sent: MetricReading) -> Double? {
        guard let received = received.numericValue, let sent = sent.numericValue else { return nil }
        return received + sent
    }
}
