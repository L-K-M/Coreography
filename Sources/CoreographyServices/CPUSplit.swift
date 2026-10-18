import Foundation
import CoreographyKit

/// One sample's CPU split for the lane's stacked area (plan: user under
/// system). User includes nice time; both are shares of the whole machine.
public struct CPUSplitPoint: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let user: Double
    public let system: Double
    public let segment: Int
}

enum CPUSplit {
    /// Samples without both readings break the area, as gaps do for the line.
    static func points(_ frames: [CapturedSnapshot]) -> [CPUSplitPoint] {
        var result: [CPUSplitPoint] = []
        var segment = 0
        for frame in frames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let split = split(frame) else {
                segment += 1
                continue
            }
            result.append(CPUSplitPoint(
                id: frame.id, time: frame.stamp.wallTime, user: split.user, system: split.system, segment: segment
            ))
        }
        return result
    }

    /// The busy total minus the kernel's share; rounding never makes user negative.
    static func split(_ frame: CapturedSnapshot) -> (user: Double, system: Double)? {
        guard let busy = frame.cpuPercentOfMachine.numericValue,
              let system = frame.cpuSystemPercentOfMachine?.numericValue else { return nil }
        return (max(busy - system, 0), min(system, busy))
    }
}

extension DashboardModel {
    /// Live samples only: stored history keeps the total, not the split.
    public func cpuSplitPoints() -> [CPUSplitPoint] { CPUSplit.points(frames) }

    public var displayedCPUSplit: (user: Double, system: Double)? { displayedFrame.flatMap(CPUSplit.split) }
}
