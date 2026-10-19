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
    /// Each cell reaches the next sample; after a break, or at the newest
    /// sample, it covers one nominal interval. A core without a reading
    /// leaves a hole, never an idle cell.
    static func cells(_ frames: [CapturedSnapshot], nominalSeconds: TimeInterval) -> [CoreHeatCell] {
        var cells: [CoreHeatCell] = []
        for (index, frame) in frames.enumerated() {
            guard let cores = frame.coreBusyPercent else { continue }
            let start = frame.stamp.wallTime
            let next = frames.indices.contains(index + 1) ? frames[index + 1] : nil
            let end = next.flatMap { $0.continuity == .continuous ? $0.stamp.wallTime : nil }
                ?? start.addingTimeInterval(nominalSeconds)
            for (core, reading) in cores.enumerated() {
                guard let busy = reading.numericValue else { continue }
                cells.append(CoreHeatCell(
                    id: "\(frame.id)-\(core)", core: core, start: start, end: end, busyPercent: min(max(busy, 0), 100)
                ))
            }
        }
        return cells
    }
}

extension DashboardModel {
    /// The displayed frames as per-core cells; empty where cores are not read.
    public func coreHeatCells() -> [CoreHeatCell] { CoreHeat.cells(frames, nominalSeconds: samplingSeconds) }
}
