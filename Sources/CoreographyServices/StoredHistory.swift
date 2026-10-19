import Foundation
import CoreographyKit

/// Stored readings shaped for the lanes, for the part of a range older than
/// live history (plan: the 6 h pill reads the on-disk Recent tier, 24 h the
/// Day tier).
///
/// ```text
/// |<------------------- 6 h ------------------->|
/// | stored prefix (disk, reduced once per load) | live hour |
///                                               ^ first live sample
/// ```
/// Each series is decimated when loaded, so redraws never touch the disk.
/// Stored series follow the recorder's choices: the primary interface, an
/// automatic storage device and the first GPU.
/// One stored reading, or one Day-tier bucket, for range reports: means
/// combine by count, peaks by maximum.
struct StoredValue: Sendable {
    let time: Date
    let mean: Double
    let maximum: Double
    let count: Int
}

/// Which stored tier a range reads.
enum StoredTier: Sendable {
    /// 1 s readings for six hours.
    case recent
    /// 10 s buckets with minimum, maximum and mean for a week.
    case day

    static func reading(_ span: TimeInterval) -> StoredTier { span > HistoryStore.retention ? .day : .recent }

    /// A silence longer than three sampling steps (sleep, the app not running) is a gap.
    var maximumGap: TimeInterval { self == .recent ? 3 : 3 * HistoryStore.dayBucket }
}

struct StoredHistory: Sendable {
    private static let lineMetrics: [HistoryMetric] = [
        .cpu, .memoryUsed, .networkReceived, .networkSent, .diskRead, .diskWritten,
        .gpuBusy, .batteryCharge, .hottestCelsius
    ]
    /// Range reports need true means and peaks, not the drawn extremes.
    private static let reportMetrics: Set<HistoryMetric> = [.cpu, .memoryUsed, .gpuBusy, .hottestCelsius]
    private static let stackMetrics: [(MemoryCategory, HistoryMetric)] = [
        (.app, .memoryApp), (.wired, .memoryWired), (.compressed, .memoryCompressed), (.cached, .memoryCached)
    ]

    let start: Date
    let end: Date
    let tier: StoredTier
    private(set) var lines: [HistoryMetric: [DashboardPoint]] = [:]
    private(set) var memoryStack: [MemoryStackPoint] = []
    private(set) var memoryPressure: [MemoryPressureSpan] = []
    private(set) var thermalPressure: [ThermalPressureSpan] = []
    /// Readings or buckets for range reports; about 1.4 MB for six hours of readings.
    private(set) var reportValues: [HistoryMetric: [StoredValue]] = [:]
    /// The stored app ledger, for range totals and scoped apps before the live hour.
    private(set) var ledger = AppLedger(capacity: 1)

    /// Read and reduce every lane's series; runs off the main actor. Ranges
    /// beyond the Recent tier's six hours read the Day tier.
    static func load(from recorder: HistoryRecorder, start: Date, end: Date) async throws -> StoredHistory {
        let tier = StoredTier.reading(end.timeIntervalSince(start))
        let gap = tier.maximumGap
        var history = StoredHistory(start: start, end: end, tier: tier)
        for metric in lineMetrics {
            let series = try await series(metric, tier: tier, recorder: recorder, start: start, end: end)
            history.lines[metric] = Decimation.points(points(series.drawn, maximumGap: gap), start: start, end: end)
            if reportMetrics.contains(metric) { history.reportValues[metric] = series.report }
        }
        // The ledger is kept in the Recent tier only, so longer ranges total its six hours.
        history.ledger = AppLedger(stored: try await recorder.ledger(from: start, to: end))

        var layers: [MemoryCategory: [HistorySample]] = [:]
        for (category, metric) in stackMetrics {
            layers[category] = try await series(metric, tier: tier, recorder: recorder, start: start, end: end).means
        }
        history.memoryStack = Decimation.stack(stack(layers, maximumGap: gap), start: start, end: end)

        let memory = try await series(.memoryPressure, tier: tier, recorder: recorder, start: start, end: end)
        history.memoryPressure = levelSpans(memory.peaks, maximumGap: gap).compactMap { span in
            MemoryPressureLevel(rawValue: span.level)
                .map { MemoryPressureSpan(id: UUID(), start: span.start, end: span.end, level: $0) }
        }
        let thermal = try await series(.thermalPressure, tier: tier, recorder: recorder, start: start, end: end)
        history.thermalPressure = levelSpans(thermal.peaks, maximumGap: gap).compactMap { span in
            ThermalPressureLevel(rawValue: span.level)
                .map { ThermalPressureSpan(id: UUID(), start: span.start, end: span.end, level: $0) }
        }
        return history
    }

    /// One metric's stored readings in each form the lanes and reports need.
    private struct Series {
        /// Every extreme in time order, for lines.
        let drawn: [HistorySample]
        /// One mean per instant, for stacks.
        let means: [HistorySample]
        /// One maximum per instant, for pressure bands: the worst level wins.
        let peaks: [HistorySample]
        let report: [StoredValue]
    }

    private static func series(
        _ metric: HistoryMetric, tier: StoredTier, recorder: HistoryRecorder, start: Date, end: Date
    ) async throws -> Series {
        switch tier {
        case .recent:
            let samples = try await recorder.samples(metric, from: start, to: end)
            let report = samples.compactMap { sample in
                sample.value.map { StoredValue(time: sample.time, mean: $0, maximum: $0, count: 1) }
            }
            return Series(drawn: samples, means: samples, peaks: samples, report: report)
        case .day:
            // A bucket draws its minimum at its start and its maximum mid-bucket, so both extremes survive.
            let rollups = try await recorder.rollups(metric, from: start, to: end)
            let middle = HistoryStore.dayBucket / 2
            func sample(_ time: Date, _ value: Double) -> HistorySample {
                HistorySample(metric: metric, time: time, value: value, availability: .measured)
            }
            return Series(
                drawn: rollups.flatMap { [sample($0.time, $0.minimum), sample($0.time.addingTimeInterval(middle), $0.maximum)] },
                means: rollups.map { sample($0.time, $0.mean) },
                peaks: rollups.map { sample($0.time, $0.maximum) },
                report: rollups.map { StoredValue(time: $0.time, mean: $0.mean, maximum: $0.maximum, count: $0.count) }
            )
        }
    }

    /// Readings or buckets in the range that predate `cutoff`, where live data takes over.
    func values(_ metric: HistoryMetric, in range: ClosedRange<Date>, before cutoff: Date) -> [StoredValue] {
        (reportValues[metric] ?? []).filter { range.contains($0.time) && $0.time < cutoff }
    }

    /// Missing readings and silences longer than `maximumGap` start new segments.
    static func points(_ samples: [HistorySample], maximumGap: TimeInterval = StoredTier.recent.maximumGap) -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        var previous: Date?
        for sample in samples {
            if let previous, sample.time.timeIntervalSince(previous) > maximumGap { segment += 1 }
            previous = sample.time
            guard let value = sample.value else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(id: UUID(), time: sample.time, value: value, segment: segment))
        }
        return result
    }

    /// Stack only instants with every layer stored; host layers share one timestamp.
    static func stack(
        _ layers: [MemoryCategory: [HistorySample]], maximumGap: TimeInterval = StoredTier.recent.maximumGap
    ) -> [MemoryStackPoint] {
        var values: [MemoryCategory: [Date: Double]] = [:]
        for (category, samples) in layers {
            for sample in samples { values[category, default: [:]][sample.time] = sample.value }
        }
        let times = (layers[.app] ?? []).map(\.time)

        var result: [MemoryStackPoint] = []
        var segment = 0
        var previous: Date?
        for time in times {
            if let previous, time.timeIntervalSince(previous) > maximumGap { segment += 1 }
            previous = time
            let stacked = MemoryCategory.allCases.compactMap { values[$0]?[time] }
            guard stacked.count == MemoryCategory.allCases.count else {
                segment += 1
                continue
            }

            var lower = 0.0
            for (category, value) in zip(MemoryCategory.allCases, stacked) {
                result.append(MemoryStackPoint(
                    id: "stored-\(time.timeIntervalSince1970)-\(category.rawValue)", time: time,
                    category: category, lower: lower, upper: lower + value, segment: segment
                ))
                lower += value
            }
        }
        return result
    }

    /// Consecutive known levels within `maximumGap` merge into spans labelled
    /// with the later reading, as the live bands are.
    static func levelSpans(
        _ samples: [HistorySample], maximumGap: TimeInterval = StoredTier.recent.maximumGap
    ) -> [(start: Date, end: Date, level: Int)] {
        var result: [(start: Date, end: Date, level: Int)] = []
        var previous: Date?
        for sample in samples {
            guard let value = sample.value, let level = Int(exactly: value) else {
                previous = nil
                continue
            }
            let before = previous
            previous = sample.time
            guard let before, sample.time.timeIntervalSince(before) <= maximumGap else { continue }
            if let last = result.last, last.end == before, last.level == level {
                result[result.count - 1].end = sample.time
            } else {
                result.append((start: before, end: sample.time, level: level))
            }
        }
        return result
    }
}
