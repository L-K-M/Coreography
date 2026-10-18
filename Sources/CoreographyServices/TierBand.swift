import Foundation
import CoreographyKit

/// One core tier's activity over one sample interval, for the CPU lane's
/// sub-band (plan: "E 44% @ 1.5 GHz | P 38% @ 3.9 GHz" under the graph).
public struct TierBandCell: Identifiable, Sendable {
    public let id: String
    /// "E", "M" or "P".
    public let tier: String
    public let start: Date
    public let end: Date
    public let activePercent: Double
}

enum TierBand {
    /// Each cell reaches the next sample; after a break, or at the newest
    /// sample, it covers one nominal interval instead of bridging the gap.
    /// A tier without a reading leaves a hole, never an idle cell.
    static func cells(_ frames: [CapturedSilicon], nominalSeconds: TimeInterval = 1) -> [TierBandCell] {
        var cells: [TierBandCell] = []
        for (index, frame) in frames.enumerated() {
            let start = frame.stamp.wallTime
            let next = frames.indices.contains(index + 1) ? frames[index + 1] : nil
            let end = next.flatMap { $0.continuity == .continuous ? $0.stamp.wallTime : nil }
                ?? start.addingTimeInterval(nominalSeconds)
            for tier in frame.cpuTiers {
                guard let active = tier.activePercent.numericValue else { continue }
                cells.append(TierBandCell(
                    id: "\(frame.id)-\(tier.kind.rawValue)", tier: tier.kind.rawValue,
                    start: start, end: end, activePercent: min(max(active, 0), 100)
                ))
            }
        }
        return cells
    }
}

extension DashboardModel {
    /// The displayed silicon frames as sub-band cells; empty off Apple silicon.
    public func tierBandCells() -> [TierBandCell] { TierBand.cells(siliconFrames) }
}
