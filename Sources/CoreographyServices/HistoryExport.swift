import Foundation
import CoreographyKit

/// Every recorded metric over a window, for `coreo export` (plan: the
/// command-line tool's export).
///
/// JSON keeps each metric's samples with their availability. CSV is one
/// row per stored sample, because metrics are not stored at shared times
/// and pairing them would invent readings; a sample without a value is an
/// empty cell, never zero.
///
/// ```text
/// time,metric,value,availability
/// 2026-10-19T14:02:00Z,cpu,12.5,measured
/// 2026-10-19T14:02:00Z,gpuBusy,,gap
/// ```
public enum HistoryExport {
    public static let schemaVersion = 1

    public struct Document: Codable, Sendable {
        public let schemaVersion: Int
        public let windowStart: Date
        public let windowEnd: Date
        public let metrics: [Series]
    }

    public struct Series: Codable, Sendable {
        public let metric: String
        public let samples: [HistoryReport.Sample]
    }

    private static let csvColumns = ["time", "metric", "value", "availability"]

    static func document(window: ClosedRange<Date>, samples: [HistoryMetric: [HistorySample]]) -> Document {
        Document(
            schemaVersion: schemaVersion, windowStart: window.lowerBound, windowEnd: window.upperBound,
            metrics: HistoryMetric.allCases.map { metric in
                Series(metric: "\(metric)", samples: (samples[metric] ?? []).map {
                    HistoryReport.Sample(time: $0.time, value: $0.value, availability: $0.availability)
                })
            }
        )
    }

    /// Rows in time order; metrics at the same time keep their catalogue order.
    public static func csv(_ document: Document) -> String {
        let timeFormat = ISO8601DateFormatter()
        let rows = document.metrics.enumerated()
            .flatMap { order, series in series.samples.map { (order: order, metric: series.metric, sample: $0) } }
            .sorted { ($0.sample.time, $0.order) < ($1.sample.time, $1.order) }

        var lines = [csvColumns.joined(separator: ",")]
        for row in rows {
            let value = row.sample.value.map { String($0) } ?? ""
            lines.append([timeFormat.string(from: row.sample.time), row.metric, value, row.sample.availability.rawValue]
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
