import Foundation
import CoreographyKit

extension ProcessSort: Codable {}

/// The busiest apps and lone processes now, for `coreo top`, grouped as
/// the process pane groups them by app.
public struct TopReport: Codable, Sendable {
    public struct Row: Codable, Sendable {
        public let name: String
        /// Processes in the app; 1 for a lone process.
        public let processes: Int
        /// A lone process's ID; an app has none.
        public let pid: Int32?
        public let cpuPercentOfMachine: MetricReading
        public let memoryFootprintBytes: MetricReading
        public let diskReadBytesPerSecond: MetricReading
        public let diskWriteBytesPerSecond: MetricReading
        public let networkReceivedBytesPerSecond: MetricReading
        public let networkSentBytesPerSecond: MetricReading
        public let gpuMillisecondsPerSecond: MetricReading
        public let cpuPowerWatts: MetricReading
        /// Lifetime user plus system CPU, summed for an app; the cpuTime sort's value.
        public let cpuTimeSeconds: MetricReading
        /// Threads now, summed for an app; the threads sort's value.
        public let threadCount: MetricReading
        /// When it started; an app's first process. The started sort's value.
        public let started: Date?
    }

    public let takenAt: Date
    public let sort: ProcessSort
    public let rows: [Row]
    /// Apps and lone processes observed, so a short list says how much it left out.
    public let total: Int
    /// Processes whose counters need the helper; their apps' totals are lower bounds.
    public let restrictedProcesses: Int

    static func make(processes: CapturedProcesses, traffic: CapturedTraffic?, sortedBy sort: ProcessSort, count: Int) -> TopReport {
        let rows = ProcessGroups.rows(
            in: processes, matching: "", sortedBy: sort, grouping: .app, facts: ProcessFacts(traffic: traffic)
        )
        return TopReport(
            takenAt: processes.stamp.wallTime, sort: sort,
            rows: rows.prefix(count).map { row in
                Row(
                    name: row.name, processes: row.memberCount, pid: row.process?.id.pid,
                    cpuPercentOfMachine: row.cpuPercentOfMachine, memoryFootprintBytes: row.memoryFootprintBytes,
                    diskReadBytesPerSecond: row.diskReadBytesPerSecond, diskWriteBytesPerSecond: row.diskWriteBytesPerSecond,
                    networkReceivedBytesPerSecond: row.networkReceivedBytesPerSecond,
                    networkSentBytesPerSecond: row.networkSentBytesPerSecond,
                    gpuMillisecondsPerSecond: row.gpuMillisecondsPerSecond, cpuPowerWatts: row.cpuPowerWatts,
                    cpuTimeSeconds: row.cpuTimeSeconds, threadCount: row.threadCount, started: row.started
                )
            },
            total: rows.count, restrictedProcesses: processes.restrictedUsageCount
        )
    }
}
