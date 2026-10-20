import Foundation
import CoreographyKit

/// What the readable processes leave unexplained (plan: an unattributed
/// share only where system and process accounting are compatible and
/// additive). CPU qualifies: both count busy time against the whole machine.
///
/// ```text
/// host CPU:     |--30 %--|--40 %--|   over the process interval, mean 35 %
/// processes:    20 % + 5 % readable   (other users' need the helper)
/// unattributed: 10 %                  restricted, kernel, short-lived
/// ```
enum ProcessAttribution {
    /// Host CPU averaged over the process interval ending at the process
    /// sample, less the readable processes' CPU, never below zero. Nil when
    /// the interval holds no host reading or any unreadable one, or the
    /// process sample follows an interruption.
    static func unattributedCPU(
        host: [(time: Date, cpu: MetricReading)], processes: CapturedProcesses, interval: TimeInterval
    ) -> Double? {
        guard processes.continuity == .continuous else { return nil }

        let end = processes.stamp.wallTime
        let window = host.filter { $0.time > end.addingTimeInterval(-interval) && $0.time <= end }
        let values = window.compactMap { $0.cpu.availability == .measured ? $0.cpu.numericValue : nil }
        guard !values.isEmpty, values.count == window.count else { return nil }

        let hostMean = values.reduce(0, +) / Double(values.count)
        let readable = processes.processes.compactMap(\.cpuPercentOfMachine.numericValue).reduce(0, +)
        return max(hostMean - readable, 0)
    }
}
