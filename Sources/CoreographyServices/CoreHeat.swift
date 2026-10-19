import Foundation
import CoreographyKit

/// One logical CPU's busy share over one sample interval, for the CPU
/// lane's detail (plan: a per-core heat strip over time).
public struct CoreHeatCell: Identifiable, Sendable {
    public let id: String
    /// The logical CPU number, from 0.
    public let core: Int
    public let start: Date
    public let end: Date
    public let busyPercent: Double
}

enum CoreHeat {
    /// One sample's shares over the interval they measure.
    private struct Column {
        let id: String
        let start: Date
        let end: Date
        let busy: [Double?]
    }

    /// A share measures the interval ending at its sample, so each cell
    /// reaches back to the previous sample; the first, and one after a break,
    /// cover one nominal interval. Only columns meeting `window` count, and
    /// neighbours merge (busy shares averaged) so a long range draws at most
    /// `maximumColumns` per core. A core without a reading leaves a hole.
    static func cells(
        _ frames: [CapturedSnapshot], nominalSeconds: TimeInterval, in window: ClosedRange<Date>? = nil,
        maximumColumns: Int = .max
    ) -> [CoreHeatCell] {
        var columns: [Column] = []
        for (index, frame) in frames.enumerated() {
            guard let cores = frame.coreBusyPercent else { continue }
            let end = frame.stamp.wallTime
            let previous = index > 0 && frame.continuity == .continuous ? frames[index - 1] : nil
            let start = previous?.stamp.wallTime ?? end.addingTimeInterval(-nominalSeconds)
            if let window, end < window.lowerBound || start > window.upperBound { continue }
            let busy = cores.map { $0.numericValue.map { min(max($0, 0), 100) } }
            // A baseline sample measures nothing yet and must not widen its neighbours.
            guard busy.contains(where: { $0 != nil }) else { continue }
            columns.append(Column(id: "\(frame.id)", start: start, end: end, busy: busy))
        }

        let size = max(1, Int((Double(columns.count) / Double(max(maximumColumns, 1))).rounded(.up)))
        var cells: [CoreHeatCell] = []
        var index = 0
        while index < columns.count {
            var chunk = [columns[index]]
            index += 1
            // Only touching columns merge, so a break stays a break.
            while chunk.count < size, index < columns.count, columns[index].start == chunk[chunk.count - 1].end {
                chunk.append(columns[index])
                index += 1
            }
            let coreCount = chunk.map(\.busy.count).max() ?? 0
            for core in 0..<coreCount {
                let spans = chunk.compactMap { column in
                    (column.busy.indices.contains(core) ? column.busy[core] : nil).map { (start: column.start, end: column.end, busy: $0) }
                }
                guard let busy = merge(spans) else { continue }
                cells.append(CoreHeatCell(
                    id: "\(chunk[0].id)-\(core)", core: core, start: chunk[0].start, end: chunk[chunk.count - 1].end,
                    busyPercent: busy
                ))
            }
        }
        return cells
    }
}

extension CoreHeat {
    /// Shares weighted by the time each covers, since columns after a break
    /// or across a cadence change differ in length. Example: 1 s at 100 %
    /// and 3 s at 0 % merge to 25 %. Nil for no spans.
    static func merge(_ spans: [(start: Date, end: Date, busy: Double)]) -> Double? {
        let seconds = spans.map { max($0.end.timeIntervalSince($0.start), 0) }
        let total = seconds.reduce(0, +)
        guard !spans.isEmpty else { return nil }
        guard total > 0 else { return spans.map(\.busy).reduce(0, +) / Double(spans.count) }
        return zip(spans, seconds).map { $0.busy * $1 }.reduce(0, +) / total
    }
}

extension DashboardModel {
    /// The displayed frames inside `window` as per-core cells, at most
    /// `maximumColumns` per core; empty where cores are not read.
    public func coreHeatCells(in window: ClosedRange<Date>, maximumColumns: Int) -> [CoreHeatCell] {
        CoreHeat.cells(frames, nominalSeconds: samplingSeconds, in: window, maximumColumns: maximumColumns)
    }
}
