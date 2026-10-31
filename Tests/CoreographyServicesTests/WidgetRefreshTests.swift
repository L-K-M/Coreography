import Foundation
import XCTest
@testable import CoreographyServices

@MainActor
final class WidgetRefreshTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testFirstSampleRefreshesAndForegroundSamplesCoalesceForFiveMinutes() {
        var requests = 0
        let widgets = WidgetRefresh { requests += 1 }
        widgets.request(at: start, activity: .foreground)
        XCTAssertEqual(requests, 1)
        for seconds in [0.0, 1, 299.999] {
            widgets.request(at: start.addingTimeInterval(seconds), activity: .foreground)
        }
        XCTAssertEqual(requests, 1)
        widgets.request(at: start.addingTimeInterval(300), activity: .foreground)
        XCTAssertEqual(requests, 2)
        widgets.request(at: start.addingTimeInterval(301), activity: .foreground)
        XCTAssertEqual(requests, 2)
    }

    func testBackgroundSamplesWaitFifteenMinutesWithoutExtendingTheWait() {
        var requests = 0
        let widgets = WidgetRefresh { requests += 1 }
        widgets.request(at: start, activity: .background)
        for seconds in [1.0, 300, 899.999] {
            widgets.request(at: start.addingTimeInterval(seconds), activity: .background)
        }
        XCTAssertEqual(requests, 1)
        widgets.request(at: start.addingTimeInterval(900), activity: .background)
        XCTAssertEqual(requests, 2)
    }

    func testActivityChangesUseTheLastActualRequest() {
        var requests = 0
        let widgets = WidgetRefresh { requests += 1 }
        widgets.request(at: start, activity: .background)
        widgets.request(at: start.addingTimeInterval(300), activity: .foreground)
        XCTAssertEqual(requests, 2)
        widgets.request(at: start.addingTimeInterval(600), activity: .background)
        XCTAssertEqual(requests, 2)
        widgets.request(at: start.addingTimeInterval(1200), activity: .background)
        XCTAssertEqual(requests, 3)
    }

    func testBackwardClockCorrectionDoesNotFreezeRefreshes() {
        var requests = 0
        let widgets = WidgetRefresh { requests += 1 }
        widgets.request(at: start, activity: .foreground)
        let corrected = start.addingTimeInterval(-3600)
        widgets.request(at: corrected, activity: .foreground)
        widgets.request(at: corrected.addingTimeInterval(299), activity: .foreground)
        XCTAssertEqual(requests, 2)
        widgets.request(at: corrected.addingTimeInterval(300), activity: .foreground)
        XCTAssertEqual(requests, 3)
    }
}
