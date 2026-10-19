import Foundation
import CoreographyKit

/// Recorded statistics per metric over a window, for `coreo stats`
/// (plan: the command-line tool's stats over a time range).
public struct HistoryStatsReport: Codable, Sendable {
    public let windowStart: Date
    public let windowEnd: Date
    public let metrics: [MetricStats]
}

/// One metric's readings over the window. Gaps and unavailable samples
/// are counted, never read as zero, so `valued` can be below `storedSamples`.
///
/// ```text
/// cpu  stored 3600  valued 3590  min 2  median 9  p95 41  max 88  mean 12.4
/// ```
public struct MetricStats: Codable, Equatable, Sendable {
    public let metric: String
    public let storedSamples: Int
    public let valued: Int
    public let minimum: Double?
    public let median: Double?
    public let p95: Double?
    public let maximum: Double?
    /// Nil for pressure levels, which are severity ordinals and are never averaged.
    public let mean: Double?
}

enum HistoryStats {
    /// Severity ordinals: a median and peak mean something, a mean does not.
    private static let ordinalMetrics: Set<HistoryMetric> = [.memoryPressure, .thermalPressure]
    private static let medianRank = 0.5
    private static let p95Rank = 0.95

    static func stats(_ metric: HistoryMetric, _ samples: [HistorySample]) -> MetricStats {
        let values = samples.compactMap(\.value).filter(\.isFinite).sorted()
        return MetricStats(
            metric: "\(metric)", storedSamples: samples.count, valued: values.count,
            minimum: values.first, median: nearestRank(values, medianRank), p95: nearestRank(values, p95Rank),
            maximum: values.last,
            mean: values.isEmpty || ordinalMetrics.contains(metric) ? nil : values.reduce(0, +) / Double(values.count)
        )
    }

    /// Nearest-rank percentile: always a recorded value, never an interpolation.
    /// Example: p95 of 1...20 is the 19th value, 19.
    private static func nearestRank(_ sorted: [Double], _ rank: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let index = Int((rank * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(index, 0), sorted.count - 1)]
    }
}
