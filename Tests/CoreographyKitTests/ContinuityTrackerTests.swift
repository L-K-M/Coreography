import Foundation
import XCTest
@testable import CoreographyKit

final class ContinuityTrackerTests: XCTestCase {
    private let clock = UUID()
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testClassifiesGapsClockChangesAndBackwardsTime() {
        var tracker = ContinuityTracker(maximumGap: .seconds(3))
        XCTAssertEqual(tracker.record(stamp(seconds: 0)), .continuous)
        XCTAssertEqual(tracker.record(stamp(seconds: 1)), .continuous)
        // Sleep: the uptime clock barely moves while the wall clock jumps.
        XCTAssertEqual(tracker.record(stamp(seconds: 2, wall: 3600)), .interrupted)
        XCTAssertEqual(tracker.record(stamp(seconds: 7, wall: 3605)), .interrupted)
        XCTAssertEqual(tracker.record(stamp(seconds: 7, wall: 3606)), .interrupted)
        XCTAssertEqual(tracker.record(stamp(seconds: 8, wall: 3500)), .discontinuous)
        XCTAssertEqual(tracker.record(stamp(seconds: 9, wall: 3501, clock: UUID())), .discontinuous)

        tracker.reset()
        XCTAssertEqual(tracker.record(stamp(seconds: 100, wall: 1)), .continuous)
    }

    private func stamp(seconds: UInt64, wall: TimeInterval? = nil, clock: UUID? = nil) -> SampleStamp {
        SampleStamp(
            clockID: clock ?? self.clock, monotonicNanoseconds: seconds * 1_000_000_000,
            wallTime: epoch.addingTimeInterval(wall ?? TimeInterval(seconds))
        )
    }
}
