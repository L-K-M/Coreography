import Foundation
import XCTest
@testable import CoreographyServices

final class SamplingRateTests: XCTestCase {
    /// Plan: a toolbar sampling rate, and Low Power Mode halving cadences.
    /// The slower of the two wins; neither stacks past what gap limits allow.
    func testTheSlowerOfTheChosenRateAndLowPowerModeWins() {
        XCTAssertEqual(SamplingRate.oneSecond.multiplier(with: .normal), 1)
        XCTAssertEqual(SamplingRate.twoSeconds.multiplier(with: .normal), 2)
        XCTAssertEqual(SamplingRate.oneSecond.multiplier(with: .lowPower), 2)
        XCTAssertEqual(SamplingRate.twoSeconds.multiplier(with: .lowPower), 2, "never 4: the monitors' gap limits")
    }

    func testTheChoiceIsKept() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SamplingRateTests-\(UUID().uuidString)"))
        XCTAssertEqual(SamplingRate.saved(in: defaults), .oneSecond)
        SamplingRate.twoSeconds.save(in: defaults)
        XCTAssertEqual(SamplingRate.saved(in: defaults), .twoSeconds)
    }
}
