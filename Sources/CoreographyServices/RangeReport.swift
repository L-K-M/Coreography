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
    public let activeAppCount: Int
    public let cpuMeanPercent: Double?
    public let cpuPeakPercent: Double?
    public let memoryPeakBytes: Double?
    public let gpuPeakPercent: Double?
    /// The key is nil when the peak came from stored history, which keeps no sensor key.
    public let hottest: (key: String?, celsius: Double)?

    /// Live data answers for its own span; stored history (on the 6 h
    /// range) answers only for what lies before each live series starts.
    static func make(
        range: ClosedRange<Date>, ledger: AppLedger, frames: [CapturedSnapshot],
        gpuFrames: [CapturedGPU], sensorFrames: [CapturedSensors], stored: StoredHistory? = nil
    ) -> RangeReport {
        let liveTotals = ledger.totals(in: range)
        let (apps, covered) = stored.map {
            AppLedger.combine($0.ledger.totals(in: range, endingBy: ledger.intervals.first?.start ?? .distantFuture), liveTotals)
        } ?? liveTotals

        func older(_ metric: HistoryMetric, before first: Date?) -> [Double] {
            stored?.values(metric, in: range, before: first ?? .distantFuture) ?? []
        }
        let inRange = frames.filter { range.contains($0.stamp.wallTime) }
        let cpu = older(.cpu, before: frames.first?.stamp.wallTime) + inRange.compactMap(\.cpuPercentOfMachine.numericValue)
        let memory = older(.memoryUsed, before: frames.first?.stamp.wallTime)
            + inRange.compactMap(\.memoryUsedBytes.numericValue)
        let gpu = older(.gpuBusy, before: gpuFrames.first?.stamp.wallTime)
            + gpuFrames.filter { range.contains($0.stamp.wallTime) }
                .flatMap(\.devices).compactMap(\.utilizationPercent.numericValue)
        let liveHottest = sensorFrames.filter { range.contains($0.stamp.wallTime) }
            .compactMap { frame in frame.hottest.flatMap { hottest in
                hottest.celsius.numericValue.map { (key: Optional(hottest.key), celsius: $0) }
            } }
        let storedHottest = older(.hottestCelsius, before: sensorFrames.first?.stamp.wallTime)
            .map { (key: String?.none, celsius: $0) }
        let hottest = (storedHottest + liveHottest).max { $0.celsius < $1.celsius }
        return RangeReport(
            requested: range, covered: covered,
            topCPUApps: Array(apps.filter { $0.cpuSeconds > 0 }.sorted { $0.cpuSeconds > $1.cpuSeconds }.prefix(appLimit)),
            topDiskApps: Array(apps.filter { $0.diskBytes > 0 }.sorted { $0.diskBytes > $1.diskBytes }.prefix(appLimit)),
            activeAppCount: apps.count,
            cpuMeanPercent: cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count),
            cpuPeakPercent: cpu.max(),
            memoryPeakBytes: memory.max(),
            gpuPeakPercent: gpu.max(),
            hottest: hottest
        )
    }
}
