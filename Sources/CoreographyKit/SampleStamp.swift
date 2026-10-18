import Foundation
import Dispatch

/// Identity of one sampling instant.
///
/// `clockID` names the clock session: it changes when the monotonic
/// timeline restarts (process or system restart), so deltas across two
/// stamps are only valid while the clock ID matches.
public struct SampleStamp: Codable, Equatable, Sendable {
    /// Identity of the clock session that produced `monotonicNanoseconds`.
    public let clockID: UUID
    /// Nanoseconds on the session's monotonic clock; comparable only
    /// within one `clockID`.
    public let monotonicNanoseconds: UInt64
    /// Wall-clock time for display; never used for deltas.
    public let wallTime: Date

    public init(clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
    }

    /// Stamp the current instant on `clockID`'s timeline.
    public static func now(clockID: UUID) -> Self {
        SampleStamp(
            clockID: clockID,
            monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            wallTime: Date()
        )
    }
}
