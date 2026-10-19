import Foundation
import CoreographyKit

/// One interface's or device's two directions over time, for a lane's
/// small multiples (plan: per-interface and per-volume detail views).
public struct TransferSeries: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Received or read.
    public let above: [DashboardPoint]
    /// Sent or written.
    public let below: [DashboardPoint]

    /// Whether it moved any bytes; idle ones crowd the detail out.
    public var isActive: Bool { (above + below).contains { $0.value > 0 } }
}

/// Builds one series per device across frames, in first-seen order.
///
/// ```text
/// frame:   t0   t1        t2      t3 (after sleep)
/// en0:     1    3         –       5      segments 0 0 | 2
/// en5:          9         8       7      segments 0 0 | 1
/// ```
enum TransferSeriesBuilder {
    struct Sample {
        let key: String
        let name: String
        let above: Double?
        let below: Double?
    }

    struct Frame {
        let id: UUID
        let time: Date
        let interrupted: Bool
        let samples: [Sample]
    }

    private enum Direction: Hashable { case above, below }

    static func series(_ frames: [Frame]) -> [TransferSeries] {
        var order: [String] = []
        var names: [String: String] = [:]
        var points: [String: [Direction: [DashboardPoint]]] = [:]
        var breaks: [String: [Direction: Int]] = [:]
        var interruptions = 0

        for frame in frames {
            if frame.interrupted { interruptions += 1 }
            let present = Set(frame.samples.map(\.key))
            // A device absent from a frame must not be bridged across it.
            for key in order where !present.contains(key) {
                breaks[key, default: [:]][.above, default: 0] += 1
                breaks[key, default: [:]][.below, default: 0] += 1
            }
            for sample in frame.samples {
                if names[sample.key] == nil { order.append(sample.key) }
                names[sample.key] = sample.name
                for (direction, value) in [(Direction.above, sample.above), (.below, sample.below)] {
                    guard let value else {
                        breaks[sample.key, default: [:]][direction, default: 0] += 1
                        continue
                    }
                    let segment = interruptions + (breaks[sample.key]?[direction] ?? 0)
                    points[sample.key, default: [:]][direction, default: []].append(
                        DashboardPoint(id: frame.id, time: frame.time, value: value, segment: segment)
                    )
                }
            }
        }
        return order.map { key in
            TransferSeries(
                id: key, name: names[key] ?? key,
                above: points[key]?[.above] ?? [], below: points[key]?[.below] ?? []
            )
        }
    }
}
