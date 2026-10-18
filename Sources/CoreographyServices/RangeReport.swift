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
    public let hottest: (key: String, celsius: Double)?

    static func make(
        range: ClosedRange<Date>, ledger: AppLedger, frames: [CapturedSnapshot],
        gpuFrames: [CapturedGPU], sensorFrames: [CapturedSensors]
    ) -> RangeReport {
        let (apps, covered) = ledger.totals(in: range)
        let inRange = frames.filter { range.contains($0.stamp.wallTime) }
        let cpu = inRange.compactMap(\.cpuPercentOfMachine.numericValue)
        let hottest = sensorFrames.filter { range.contains($0.stamp.wallTime) }
            .compactMap { frame in frame.hottest.flatMap { hottest in
                hottest.celsius.numericValue.map { (key: hottest.key, celsius: $0) }
            } }
            .max { $0.celsius < $1.celsius }
        return RangeReport(
            requested: range, covered: covered,
            topCPUApps: Array(apps.filter { $0.cpuSeconds > 0 }.sorted { $0.cpuSeconds > $1.cpuSeconds }.prefix(appLimit)),
            topDiskApps: Array(apps.filter { $0.diskBytes > 0 }.sorted { $0.diskBytes > $1.diskBytes }.prefix(appLimit)),
            activeAppCount: apps.count,
            cpuMeanPercent: cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count),
            cpuPeakPercent: cpu.max(),
            memoryPeakBytes: inRange.compactMap(\.memoryUsedBytes.numericValue).max(),
            gpuPeakPercent: gpuFrames.filter { range.contains($0.stamp.wallTime) }
                .flatMap(\.devices).compactMap(\.utilizationPercent.numericValue).max(),
            hottest: hottest
        )
    }
}
