import Foundation
import XCTest
@testable import CoreographyServices

final class LaneLayoutTests: XCTestCase {
    func testMovesSkipHiddenLanesAndStopAtTheEnds() {
        var layout = LaneLayout.standard
        layout.set(.memory, .hidden)
        XCTAssertFalse(layout.canMove(.cpu, .up))
        layout.move(.gpu, .up)
        XCTAssertEqual(layout.visible, [.gpu, .cpu, .power, .disk, .network, .thermal], "past the hidden memory lane")
        XCTAssertEqual(layout.order, [.gpu, .memory, .cpu, .power, .disk, .network, .thermal], "hidden lanes keep their place")
        layout.move(.thermal, .down)
        XCTAssertEqual(layout.visible.last, .thermal)
    }

    func testTheLastVisibleLaneStays() {
        var layout = LaneLayout.standard
        for lane in LaneKind.allCases { layout.set(lane, .hidden) }
        XCTAssertEqual(layout.visible, [.thermal])
        layout.set(.cpu, .shown)
        XCTAssertEqual(layout.visible, [.cpu, .thermal])
    }

    func testSizesDefaultToRegular() {
        var layout = LaneLayout.standard
        layout.set(.power, .tall)
        XCTAssertEqual(layout.size(of: .power), .tall)
        XCTAssertEqual(layout.size(of: .cpu), .regular)
        layout.set(.power, .regular)
        XCTAssertEqual(layout, .standard)
    }

    func testSavedLayoutsSurviveUnknownAndNewLanes() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lanes-\(UUID().uuidString)"))
        var layout = LaneLayout.standard
        layout.move(.network, .up)
        layout.set(.gpu, .hidden)
        layout.set(.disk, .compact)
        layout.save(in: defaults)
        XCTAssertEqual(LaneLayout.saved(in: defaults), layout)

        // An older or newer version: an unknown lane, duplicates, a missing lane, everything hidden.
        let foreign = #"{"order":["network","cpu","sonar","cpu","memory"],"hidden":["network","cpu","memory","gpu","power","disk","thermal"],"sizes":{"cpu":"huge","memory":"tall"}}"#
        defaults.set(Data(foreign.utf8), forKey: "laneLayout")
        let restored = LaneLayout.saved(in: defaults)
        // Missing lanes follow their default predecessor: thermal after network, gpu after memory.
        XCTAssertEqual(restored.order, [.network, .thermal, .cpu, .memory, .gpu, .power, .disk])
        XCTAssertEqual(restored.visible, restored.order, "a layout hiding everything shows everything")
        XCTAssertEqual(restored.size(of: .memory), .tall)
        XCTAssertEqual(restored.size(of: .cpu), .regular)
    }
}
