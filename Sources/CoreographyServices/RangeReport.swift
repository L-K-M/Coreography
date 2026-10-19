import Foundation
import CoreographyKit

/// What happened inside a selected time range (plan P7).
public struct RangeReport: Sendable {
    public static let appLimit = 5

    public let requested: ClosedRange<Date>
    /// The span the process ledger actually covers; nil when no interval fits.
    public let covered: ClosedRange<Date>?
    public let topCPUApps: [AppRangeTotal]
    public let topDiskApps: [AppRangeTotal]
    /// Apps by bytes moved over the network; nil when no interval read network.
    public let topNetworkApps: [AppRangeTotal]?
    public let activeAppCount: Int
    /// Every app the ledger saw in the range, for comparisons and re-ranking.
    public let apps: [AppRangeTotal]
    public let cpuMeanPercent: Double?
    public let cpuPeakPercent: Double?
    /// Nearest-rank, from raw readings only; nil when the range reaches
    /// rolled-up history, whose buckets keep no spread.
    public let cpuMedianPercent: Double?
    public let cpuP95Percent: Double?
    public let memoryPeakBytes: Double?
    public let gpuPeakPercent: Double?
    /// The key is nil when the peak came from stored history, which keeps no sensor key.
    public let hottest: (key: String?, celsius: Double)?

    /// Live data answers for its own span; stored history (on the 6 h and
    /// 24 h ranges) answers only for what lies before each live series
    /// starts. Day-tier buckets weigh their means by count, so the mean stays
    /// exact; their maxima are the true peaks.
    static func make(
        range: ClosedRange<Date>, ledger: AppLedger, frames: [CapturedSnapshot],
        gpuFrames: [CapturedGPU], sensorFrames: [CapturedSensors], stored: StoredHistory? = nil
    ) -> RangeReport {
        let liveTotals = ledger.totals(in: range)
        let (apps, covered) = stored.map {
            AppLedger.combine($0.ledger.totals(in: range, endingBy: ledger.intervals.first?.start ?? .distantFuture), liveTotals)
        } ?? liveTotals

        func older(_ metric: HistoryMetric, before first: Date?) -> [StoredValue] {
            stored?.values(metric, in: range, before: first ?? .distantFuture) ?? []
        }
        let inRange = frames.filter { range.contains($0.stamp.wallTime) }
        let storedCPU = older(.cpu, before: frames.first?.stamp.wallTime)
        let liveCPU = inRange.compactMap(\.cpuPercentOfMachine.numericValue)
        let cpuCount = storedCPU.reduce(0) { $0 + $1.count } + liveCPU.count
        let cpuTotal = storedCPU.reduce(0) { $0 + $1.mean * Double($1.count) } + liveCPU.reduce(0, +)
        let memory = older(.memoryUsed, before: frames.first?.stamp.wallTime).map(\.maximum)
            + inRange.compactMap(\.memoryUsedBytes.numericValue)
        let gpu = older(.gpuBusy, before: gpuFrames.first?.stamp.wallTime).map(\.maximum)
            + gpuFrames.filter { range.contains($0.stamp.wallTime) }
                .flatMap(\.devices).compactMap(\.utilizationPercent.numericValue)
        let liveHottest = sensorFrames.filter { range.contains($0.stamp.wallTime) }
            .compactMap { frame in frame.hottest.flatMap { hottest in
                hottest.celsius.numericValue.map { (key: Optional(hottest.key), celsius: $0) }
            } }
        let storedHottest = older(.hottestCelsius, before: sensorFrames.first?.stamp.wallTime)
            .map { (key: String?.none, celsius: $0.maximum) }
        let hottest = (storedHottest + liveHottest).max { $0.celsius < $1.celsius }
        let percentiles = cpuPercentiles(stored: storedCPU, live: liveCPU)
        return RangeReport(
            requested: range, covered: covered,
            topCPUApps: Array(apps.filter { $0.cpuSeconds > 0 }.sorted { $0.cpuSeconds > $1.cpuSeconds }.prefix(appLimit)),
            topDiskApps: Array(apps.filter { $0.diskBytes > 0 }.sorted { $0.diskBytes > $1.diskBytes }.prefix(appLimit)),
            topNetworkApps: apps.contains { $0.networkBytes != nil }
                ? Array(apps.filter { ($0.networkBytes ?? 0) > 0 }.sorted { ($0.networkBytes ?? 0) > ($1.networkBytes ?? 0) }.prefix(appLimit))
                : nil,
            activeAppCount: apps.count,
            apps: apps,
            cpuMeanPercent: cpuCount == 0 ? nil : cpuTotal / Double(cpuCount),
            cpuPeakPercent: (storedCPU.map(\.maximum) + liveCPU).max(),
            cpuMedianPercent: percentiles?.median, cpuP95Percent: percentiles?.p95,
            memoryPeakBytes: memory.max(),
            gpuPeakPercent: gpu.max(),
            hottest: hottest
        )
    }

    /// A stored value counting more than one reading is a rolled-up bucket
    /// (plan: percentiles require raw samples).
    static func cpuPercentiles(stored: [StoredValue], live: [Double]) -> (median: Double, p95: Double)? {
        guard stored.allSatisfy({ $0.count == 1 }) else { return nil }
        let sorted = (stored.map(\.mean) + live).sorted()
        guard let median = NearestRank.value(sorted, NearestRank.median),
              let p95 = NearestRank.value(sorted, NearestRank.p95) else { return nil }
        return (median, p95)
    }
}
