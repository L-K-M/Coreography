import Foundation
import CoreographyKit

/// Stored readings shaped for the lanes, for the part of a range older than
/// live history (plan: the 6 h pill reads the on-disk Recent tier, 24 h
/// and 7 d the Day tier, 30 d the Month tier).
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
struct StoredValue: Codable, Equatable, Sendable {
    let time: Date
    let mean: Double
    let maximum: Double
    let count: Int
}

/// One stored reading or rollup bucket, the raw form a `StoredHistory`
/// reduces and a recording's stored section serializes. The tier says
/// which shape an entry takes: under `recent` it is a reading — `time`
/// and `value`, the value absent where the reading was a gap; under
/// `day` or `month` it is a bucket — `time`, `minimum`, `maximum`,
/// `mean` and `count`.
struct StoredPoint: Codable, Equatable, Sendable {
    let time: Date
    let value: Double?
    /// The reading's state under `recent`; nil for a bucket or a file saved
    /// before availability was kept.
    let availability: MetricAvailability?
    let minimum: Double?
    let maximum: Double?
    let mean: Double?
    let count: Int?

    init(
        time: Date, value: Double? = nil, availability: MetricAvailability? = nil, minimum: Double? = nil,
        maximum: Double? = nil, mean: Double? = nil, count: Int? = nil
    ) {
        self.time = time
        self.value = value
        self.availability = availability
        self.minimum = minimum
        self.maximum = maximum
        self.mean = mean
        self.count = count
    }
}

/// Which stored tier a range reads.
enum StoredTier: String, Codable, Sendable {
    /// 1 s readings for six hours.
    case recent
    /// 10 s buckets with minimum, maximum and mean for a week.
    case day
    /// 1 min buckets with minimum, maximum and mean for a month.
    case month

    /// A range longer than the 1 s retention reads the Day tier, and one
    /// longer than the Day tier's retention the Month tier.
    static func reading(
        _ span: TimeInterval, recentRetention: TimeInterval, dayRetention: TimeInterval = HistoryStore.dayRetention
    ) -> StoredTier {
        if span > dayRetention { return .month }
        return span > recentRetention ? .day : .recent
    }

    /// How long one stored value spans: a reading is an instant, a bucket its width.
    var span: TimeInterval {
        switch self {
        case .recent: 0
        case .day: HistoryStore.dayBucket
        case .month: HistoryStore.monthBucket
        }
    }

    /// A silence longer than three sampling steps (sleep, the app not running) is a gap.
    var maximumGap: TimeInterval {
        switch self {
        case .recent: 3
        case .day: 3 * HistoryStore.dayBucket
        case .month: 3 * HistoryStore.monthBucket
        }
    }

    var rollupTier: RollupTier? {
        switch self {
        case .recent: nil
        case .day: .day
        case .month: .month
        }
    }
}

struct StoredHistory: Sendable {
    private static let lineMetrics: [HistoryMetric] = [
        .cpu, .memoryUsed, .networkReceived, .networkSent, .diskRead, .diskWritten,
        .gpuBusy, .batteryCharge, .hottestCelsius,
        .efficiencyClusterActivePercent, .performanceClusterActivePercent,
        .efficiencyClusterFrequencyMHz, .performanceClusterFrequencyMHz
    ]
    /// Range reports need true means and peaks, not the drawn extremes.
    private static let reportMetrics: Set<HistoryMetric> = [.cpu, .memoryUsed, .gpuBusy, .hottestCelsius]
    private static let stackMetrics: [(MemoryCategory, HistoryMetric)] = [
        (.app, .memoryApp), (.wired, .memoryWired), (.compressed, .memoryCompressed), (.cached, .memoryCached)
    ]
    /// Every metric the reduction reads: the lane lines, the memory stack
    /// layers and the two pressure bands.
    private static let storedMetrics: [HistoryMetric] =
        lineMetrics + stackMetrics.map(\.1) + [.memoryPressure, .thermalPressure]

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

    /// The raw stored data behind one range under one tier: every metric's
    /// series (Recent-tier readings, Day- or Month-tier buckets) and the
    /// app ledger. `load` reads it from the store, a save reads it there
    /// again to serialize it, and a recording's stored section carries it;
    /// `init(reducing:)` is the one reduction all three share, so
    /// identical data draws and reports identically.
    struct RawData: Equatable, Sendable {
        let start: Date
        let end: Date
        let tier: StoredTier
        let series: [HistoryMetric: [StoredPoint]]
        let ledger: [LedgerInterval]

        init(
            start: Date, end: Date, tier: StoredTier,
            series: [HistoryMetric: [StoredPoint]], ledger: [LedgerInterval]
        ) {
            self.start = start
            self.end = end
            self.tier = tier
            self.series = series
            self.ledger = ledger
        }

        /// Raw data as a recording's stored section carries it, over the
        /// recording's range. The save side already cut the stored ledger at
        /// the first live interval (`Recording.make`), so it replays exactly
        /// what the recording kept.
        init(replaying stored: Recording.Stored, range: ClosedRange<Date>) {
            self.init(
                start: range.lowerBound, end: range.upperBound, tier: stored.tier,
                series: stored.series.reduce(into: [:]) { series, pair in
                    guard let metric = HistoryMetric(recordingKey: pair.key) else { return }
                    series[metric] = pair.value
                },
                ledger: stored.ledger.map { interval in
                    LedgerInterval(
                        start: interval.start, end: interval.end, cores: interval.cores,
                        coversNetwork: interval.coversNetwork, coversEnergy: interval.coversEnergy,
                        entries: interval.entries.map {
                            LedgerEntry(
                                app: $0.app, cpuSeconds: $0.cpuSeconds, diskBytes: $0.diskBytes,
                                networkBytes: $0.networkBytes, energyJoules: $0.energyJoules,
                                isLowerBound: $0.isLowerBound
                            )
                        }
                    )
                }
            )
        }

        /// The metric's readings or buckets in the range that predate
        /// `cutoff`, where live data takes over — the rule `values` cuts
        /// report values by.
        func points(_ metric: HistoryMetric, in range: ClosedRange<Date>, before cutoff: Date) -> [StoredPoint] {
            (series[metric] ?? []).filter { StoredHistory.includes($0.time, in: range, before: cutoff, span: tier.span) }
        }
    }

    init(start: Date, end: Date, tier: StoredTier) {
        self.start = start
        self.end = end
        self.tier = tier
    }

    /// Read and reduce every lane's series; runs off the main actor. Ranges
    /// beyond the Recent tier's six hours read the Day tier, and beyond the
    /// Day tier's week the Month tier.
    static func load(
        from recorder: HistoryRecorder, start: Date, end: Date, recentRetention: TimeInterval = HistoryStore.retention,
        dayRetention: TimeInterval = HistoryStore.dayRetention
    ) async throws -> StoredHistory {
        let tier = StoredTier.reading(end.timeIntervalSince(start), recentRetention: recentRetention, dayRetention: dayRetention)
        return StoredHistory(reducing: try await rawData(from: recorder, tier: tier, start: start, end: end))
    }

    /// The raw data a range's stored part reduces or a recording
    /// serializes: every stored metric's series and the stored ledger,
    /// read through the recorder under the given tier.
    static func rawData(
        from recorder: HistoryRecorder, tier: StoredTier, start: Date, end: Date
    ) async throws -> RawData {
        var series: [HistoryMetric: [StoredPoint]] = [:]
        for metric in storedMetrics {
            series[metric] = try await rawSeries(metric, tier: tier, recorder: recorder, start: start, end: end)
        }
        // The ledger is kept in the Recent tier only, so longer ranges total its six hours.
        return RawData(
            start: start, end: end, tier: tier, series: series,
            ledger: try await recorder.ledger(from: start, to: end)
        )
    }

    /// One metric's raw series under the tier: Recent readings or rollup buckets.
    private static func rawSeries(
        _ metric: HistoryMetric, tier: StoredTier, recorder: HistoryRecorder, start: Date, end: Date
    ) async throws -> [StoredPoint] {
        switch tier {
        case .recent:
            return try await recorder.samples(metric, from: start, to: end).map {
                StoredPoint(time: $0.time, value: $0.value, availability: $0.availability)
            }
        case .day, .month:
            return try await recorder.rollups(metric, tier: tier.rollupTier ?? .day, from: start, to: end).map {
                StoredPoint(time: $0.time, minimum: $0.minimum, maximum: $0.maximum, mean: $0.mean, count: $0.count)
            }
        }
    }

    /// The stored part of an open recording, rebuilt from its saved series
    /// and ledger intervals through the same reduction a live load runs,
    /// so lanes, reports and contributors read the earlier part in replay
    /// as they do live.
    init(replaying stored: Recording.Stored, range: ClosedRange<Date>) {
        self.init(reducing: RawData(replaying: stored, range: range))
    }

    /// Reduce the raw data to the lines, report values, memory stack,
    /// pressure spans and ledger the lanes and reports read.
    init(reducing raw: RawData) {
        self.init(start: raw.start, end: raw.end, tier: raw.tier)
        let gap = raw.tier.maximumGap
        for metric in Self.lineMetrics {
            guard let points = raw.series[metric] else { continue }
            let series = Self.series(points, for: metric, tier: raw.tier)
            lines[metric] = Decimation.points(Self.points(series.drawn, maximumGap: gap), start: raw.start, end: raw.end)
            if Self.reportMetrics.contains(metric) { reportValues[metric] = series.report }
        }
        ledger = AppLedger(stored: raw.ledger)

        var layers: [MemoryCategory: [HistorySample]] = [:]
        for (category, metric) in Self.stackMetrics {
            guard let points = raw.series[metric] else { continue }
            layers[category] = Self.series(points, for: metric, tier: raw.tier).means
        }
        memoryStack = Decimation.stack(Self.stack(layers, maximumGap: gap), start: raw.start, end: raw.end)

        if let points = raw.series[.memoryPressure] {
            memoryPressure = Self.levelSpans(
                Self.series(points, for: .memoryPressure, tier: raw.tier).peaks, maximumGap: gap
            ).compactMap { span in
                MemoryPressureLevel(rawValue: span.level)
                    .map { MemoryPressureSpan(id: UUID(), start: span.start, end: span.end, level: $0) }
            }
        }
        if let points = raw.series[.thermalPressure] {
            thermalPressure = Self.levelSpans(
                Self.series(points, for: .thermalPressure, tier: raw.tier).peaks, maximumGap: gap
            ).compactMap { span in
                ThermalPressureLevel(rawValue: span.level)
                    .map { ThermalPressureSpan(id: UUID(), start: span.start, end: span.end, level: $0) }
            }
        }
    }

    /// One metric's raw series in each form the lanes and reports need.
    private struct Series {
        /// Every extreme in time order, for lines.
        let drawn: [HistorySample]
        /// One mean per instant, for stacks.
        let means: [HistorySample]
        /// One maximum per instant, for pressure bands: the worst level wins.
        let peaks: [HistorySample]
        let report: [StoredValue]
    }

    /// Reduce one metric's raw series under its tier. A reading is one
    /// point, a gap kept by its absent value; a bucket draws its minimum
    /// at its start and its maximum mid-bucket, so both extremes survive.
    private static func series(_ points: [StoredPoint], for metric: HistoryMetric, tier: StoredTier) -> Series {
        switch tier {
        case .recent:
            let samples = points.map {
                // The state the store wrote travels with the point; a file
                // saved before availability was kept rebuilds it from value
                // nil-ness, which the store's writes — a measured or finer
                // value, or a value-less state the lanes draw as a break —
                // make exhaustive.
                HistorySample(
                    metric: metric, time: $0.time, value: $0.value,
                    availability: $0.availability ?? ($0.value == nil ? .gap : .measured)
                )
            }
            return Series(
                drawn: samples, means: samples, peaks: samples,
                report: points.compactMap { point in
                    point.value.map { StoredValue(time: point.time, mean: $0, maximum: $0, count: 1) }
                }
            )
        case .day, .month:
            // Half the fetched rollup tier's bucket places the maximum mid-bucket.
            let middle = (tier.rollupTier ?? .day).bucket / 2
            func sample(_ time: Date, _ value: Double) -> HistorySample {
                HistorySample(metric: metric, time: time, value: value, availability: .measured)
            }
            // A saved bucket missing a field cannot be drawn; skip it.
            let buckets = points.compactMap { point -> (time: Date, minimum: Double, maximum: Double, mean: Double, count: Int)? in
                guard let minimum = point.minimum, let maximum = point.maximum,
                      let mean = point.mean, let count = point.count else {
                    assertionFailure("a stored bucket at \(point.time) is missing minimum, maximum, mean or count")
                    return nil
                }
                return (point.time, minimum, maximum, mean, count)
            }
            return Series(
                drawn: buckets.flatMap {
                    [sample($0.time, $0.minimum), sample($0.time.addingTimeInterval(middle), $0.maximum)]
                },
                means: buckets.map { sample($0.time, $0.mean) },
                peaks: buckets.map { sample($0.time, $0.maximum) },
                report: buckets.map { StoredValue(time: $0.time, mean: $0.mean, maximum: $0.maximum, count: $0.count) }
            )
        }
    }

    /// Readings or buckets in the range that predate `cutoff`, where live data takes over.
    /// A bucket counts only if it ends before live data starts, or its readings would count twice.
    func values(_ metric: HistoryMetric, in range: ClosedRange<Date>, before cutoff: Date) -> [StoredValue] {
        (reportValues[metric] ?? []).filter { Self.includes($0.time, in: range, before: cutoff, span: tier.span) }
    }

    /// A reading counts where it starts; a bucket counts only when it ends
    /// before live data takes over — the bound both report values and
    /// series saved into a recording are cut at.
    static func includes(_ time: Date, in range: ClosedRange<Date>, before cutoff: Date, span: TimeInterval) -> Bool {
        range.contains(time) && (span == 0 ? time < cutoff : time.addingTimeInterval(span) <= cutoff)
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
