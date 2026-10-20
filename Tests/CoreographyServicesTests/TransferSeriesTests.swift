import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class TransferSeriesTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plan: per-interface and per-volume small multiples in the network and
    /// disk details. A device missing from a frame or unreadable is a break,
    /// never bridged, and an interruption breaks every series.
    func testEachDeviceGetsItsOwnSeriesWithBreaksNeverBridged() throws {
        let en0 = { (a: Double?, b: Double?) in TransferSeriesBuilder.Sample(key: "en0", name: "Wi-Fi", above: a, below: b) }
        let en5 = { (a: Double?, b: Double?) in TransferSeriesBuilder.Sample(key: "en5", name: "Ethernet", above: a, below: b) }
        let frames: [TransferSeriesBuilder.Frame] = [
            .init(id: UUID(), time: epoch, interrupted: false, samples: [en0(1, 2)]),
            .init(id: UUID(), time: epoch.addingTimeInterval(1), interrupted: false, samples: [en0(3, nil), en5(9, 9)]),
            .init(id: UUID(), time: epoch.addingTimeInterval(2), interrupted: false, samples: [en5(8, 8)]),
            .init(id: UUID(), time: epoch.addingTimeInterval(3), interrupted: true, samples: [en0(5, 6), en5(7, 7)])
        ]
        let series = TransferSeriesBuilder.series(frames)
        XCTAssertEqual(series.map(\.name), ["Wi-Fi", "Ethernet"], "first-seen order")

        let wifi = try XCTUnwrap(series.first)
        XCTAssertEqual(wifi.above.map(\.value), [1, 3, 5])
        XCTAssertEqual(wifi.above.map(\.segment), [0, 0, 2], "absent at 2 s, then interrupted at 3 s")
        XCTAssertEqual(wifi.below.map(\.value), [2, 6])
        XCTAssertEqual(Set(wifi.below.map(\.segment)).count, 2, "the unreadable send at 1 s breaks the line")

        let ethernet = try XCTUnwrap(series.last)
        XCTAssertEqual(ethernet.above.map(\.segment), [0, 0, 1], "the interruption breaks it too")
    }
}
