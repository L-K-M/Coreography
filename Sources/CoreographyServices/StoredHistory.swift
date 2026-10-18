import Foundation
import CoreographyKit

/// Stored readings shaped for the lanes, for the part of a range older than
/// live history (plan: the 6 h pill reads the on-disk Recent tier).
///
/// ```text
/// |<------------------- 6 h ------------------->|
/// | stored prefix (disk, reduced once per load) | live hour |
///                                               ^ first live sample
/// ```
/// Each series is decimated when loaded, so redraws never touch the disk.
/// Stored series follow the recorder's choices: the primary interface, an
/// automatic storage device and the first GPU.
struct StoredHistory: Sendable {
    /// Recording runs at 1 s; a longer silence (sleep, the app not running) is a gap.
    static let maximumGap: TimeInterval = 3
    private static let lineMetrics: [HistoryMetric] = [
        .cpu, .memoryUsed, .networkReceived, .networkSent, .diskRead, .diskWritten,
        .gpuBusy, .batteryCharge, .hottestCelsius
    ]
    private static let stackMetrics: [(MemoryCategory, HistoryMetric)] = [
        (.app, .memoryApp), (.wired, .memoryWired), (.compressed, .memoryCompressed), (.cached, .memoryCached)
    ]

    let start: Date
    let end: Date
    private(set) var lines: [HistoryMetric: [DashboardPoint]] = [:]
    private(set) var memoryStack: [MemoryStackPoint] = []
    private(set) var memoryPressure: [MemoryPressureSpan] = []
    private(set) var thermalPressure: [ThermalPressureSpan] = []

    /// Read and reduce every lane's series; runs off the main actor.
    static func load(from recorder: HistoryRecorder, start: Date, end: Date) async throws -> StoredHistory {
        var history = StoredHistory(start: start, end: end)
        for metric in lineMetrics {
            let samples = try await recorder.samples(metric, from: start, to: end)
            history.lines[metric] = Decimation.points(points(samples), start: start, end: end)
        }

        var layers: [MemoryCategory: [HistorySample]] = [:]
        for (category, metric) in stackMetrics {
            layers[category] = try await recorder.samples(metric, from: start, to: end)
        }
        history.memoryStack = Decimation.stack(stack(layers), start: start, end: end)

        history.memoryPressure = levelSpans(try await recorder.samples(.memoryPressure, from: start, to: end))
            .compactMap { span in
                MemoryPressureLevel(rawValue: span.level)
                    .map { MemoryPressureSpan(id: UUID(), start: span.start, end: span.end, level: $0) }
            }
        history.thermalPressure = levelSpans(try await recorder.samples(.thermalPressure, from: start, to: end))
            .compactMap { span in
                ThermalPressureLevel(rawValue: span.level)
                    .map { ThermalPressureSpan(id: UUID(), start: span.start, end: span.end, level: $0) }
            }
        return history
    }

    /// Missing readings and silences longer than `maximumGap` start new segments.
    static func points(_ samples: [HistorySample]) -> [DashboardPoint] {
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
    static func stack(_ layers: [MemoryCategory: [HistorySample]]) -> [MemoryStackPoint] {
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
    static func levelSpans(_ samples: [HistorySample]) -> [(start: Date, end: Date, level: Int)] {
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
