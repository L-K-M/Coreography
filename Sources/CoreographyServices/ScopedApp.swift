import Foundation
import CoreographyKit

/// A lane quantity the ledger does not keep per app, read from the process sample.
public enum ScopedMetric: Hashable, Sendable {
    /// Summed member footprints; shared pages can count more than once.
    case memory
    /// GPU milliseconds per second, a different scale than device busy %.
    case gpu
}

/// The scoped app's reading in one lane, with its rank so the lane keeps
/// the app's place visible (plan: selection and scope).
///
/// ```text
/// Safari: 1.2 GB footprint est. · rank 2 of 41 apps
/// ```
public struct ScopedAppReading: Equatable, Sendable {
    public let value: MetricReading
    /// 1 for the largest; nil when the app used none or could not be read.
    public let rank: Int?
    /// Apps with a positive readable value, the app included when it has one.
    public let rankedApps: Int
}

enum ScopedApp {
    /// Every metric from one grouping pass; empty when the sample has no
    /// row for the app, as it was not observed then.
    static func readings(of app: String, in processes: CapturedProcesses) -> [ScopedMetric: ScopedAppReading] {
        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .name, grouping: .app)
        guard let row = rows.first(where: { $0.name == app }) else { return [:] }
        return Dictionary(uniqueKeysWithValues: [ScopedMetric.memory, .gpu].map { ($0, reading(row, $0, among: rows)) })
    }

    private static func reading(_ row: ProcessRow, _ metric: ScopedMetric, among rows: [ProcessRow]) -> ScopedAppReading {
        let values = rows.compactMap { other -> Double? in
            guard let value = reading(other, metric).numericValue, value > 0 else { return nil }
            return value
        }
        let own = reading(row, metric)
        let rank = own.numericValue.flatMap { value in
            value > 0 ? values.filter { $0 > value }.count + 1 : nil
        }
        return ScopedAppReading(value: own, rank: rank, rankedApps: values.count)
    }

    private static func reading(_ row: ProcessRow, _ metric: ScopedMetric) -> MetricReading {
        switch metric {
        case .memory: row.memoryFootprintBytes
        case .gpu: row.gpuMillisecondsPerSecond
        }
    }
}
