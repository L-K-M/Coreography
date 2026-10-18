import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class SleepAssertionsTests: XCTestCase {
    func testDecoderKeepsActiveAssertionsWithTheirAge() {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let decoded = PowerAssertionDecoder.assertions([
            90: [
                ["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Playing audio", "AssertLevel": NSNumber(value: 255), "AssertStartWhen": since],
                ["AssertType": "PreventUserIdleDisplaySleep", "AssertLevel": NSNumber(value: 0)],
                ["AssertName": "no type"]
            ],
            12: [["AssertType": "BackgroundTask"]]
        ])
        XCTAssertEqual(decoded, [
            RawAssertion(pid: 12, type: "BackgroundTask", name: nil, since: nil),
            RawAssertion(pid: 90, type: "PreventUserIdleSystemSleep", name: "Playing audio", since: since)
        ], "released and untyped assertions are left out")
    }

    func testReaderClassifiesWhatEachAssertionHoldsOff() async {
        let snapshot = await AssertionReader(driver: Assertions(.success([
            RawAssertion(pid: 1, type: "PreventUserIdleSystemSleep", name: "Download", since: nil),
            RawAssertion(pid: 2, type: "NoDisplaySleepAssertion", name: "Video", since: nil),
            RawAssertion(pid: 3, type: "BackgroundTask", name: nil, since: nil)
        ]))).read()
        XCTAssertEqual(snapshot.assertions.map(\.effect), [.preventsSystemSleep, .preventsDisplaySleep, .other])
        XCTAssertEqual(snapshot.sleepPreventers, [1, 2])

        let unsupported = await AssertionReader(driver: Assertions(.failure(.unsupportedPlatform))).read()
        XCTAssertEqual(unsupported.unavailableReason, "Power assertions need macOS")
    }
}

private struct Assertions: PowerAssertionReading {
    let result: Result<[RawAssertion], PowerAssertionError>

    init(_ result: Result<[RawAssertion], PowerAssertionError>) { self.result = result }

    func read() async -> Result<[RawAssertion], PowerAssertionError> { result }
}
