import Foundation
import XCTest
@testable import CoreographyServices

final class BraidLensTests: XCTestCase {
    /// A stray click or a short wobble decides nothing; once decided, the
    /// direction with more travel wins, and Command keeps comparison.
    func testDragIntentWaitsThenLocksToTheDominantDirection() {
        XCTAssertEqual(BraidLens.intent(dx: 3, dy: 5, comparing: false), .undecided)
        XCTAssertEqual(BraidLens.intent(dx: 9, dy: 4, comparing: false), .range)
        XCTAssertEqual(BraidLens.intent(dx: 4, dy: -13, comparing: false), .pull)
        XCTAssertEqual(BraidLens.intent(dx: 10, dy: 11, comparing: false), .range, "a diagonal under 12 pt up stays a range")
        XCTAssertEqual(BraidLens.intent(dx: 2, dy: 30, comparing: true), .comparison, "a steep Command-drag never pulls")
        XCTAssertEqual(BraidLens.intent(dx: 2, dy: 3, comparing: true), .undecided)
    }

    func testSpreadIsLinearToFullyOpenThenGainsBoundedTension() {
        XCTAssertEqual(BraidLens.spread(travel: 0), 0)
        XCTAssertEqual(BraidLens.spread(travel: 24), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BraidLens.spread(travel: -48), 1, accuracy: 1e-9, "pulling down opens it as far")
        let tense = BraidLens.spread(travel: 96)
        XCTAssertGreaterThan(tense, 1.2)
        XCTAssertEqual(BraidLens.spread(travel: 400), tense, accuracy: 1e-9, "tension stops growing past 96 pt")
    }

    /// Strands only move up by whole gaps, most at the pointer, none at the
    /// lens edge or outside it, and never the bottom one.
    func testOffsetsPeakAtTheCenterAndVanishAtTheEdges() {
        let width = 600.0
        let half = BraidLens.halfWidth(spread: 1, plotWidth: width)
        XCTAssertEqual(half, 132, accuracy: 1e-9)
        XCTAssertEqual(BraidLens.offset(index: 3, x: 300, center: 300, spread: 1, plotWidth: width), 24, accuracy: 1e-9)
        XCTAssertEqual(BraidLens.offset(index: 0, x: 300, center: 300, spread: 1, plotWidth: width), 0)
        XCTAssertEqual(BraidLens.offset(index: 3, x: 300 + half, center: 300, spread: 1, plotWidth: width), 0)
        XCTAssertEqual(BraidLens.offset(index: 3, x: 10, center: 300, spread: 1, plotWidth: width), 0)
        let near = BraidLens.offset(index: 3, x: 330, center: 300, spread: 1, plotWidth: width)
        XCTAssertTrue((0..<24).contains(near))
        XCTAssertEqual(BraidLens.halfWidth(spread: 0, plotWidth: width), BraidLens.minimumHalfWidth)
    }

    func testSettlingNeverPassesItsTargetAndTheRingDiesAway() {
        XCTAssertEqual(BraidLens.settle(from: 1.2, to: 0, elapsed: 0, duration: 0.24), 1.2, accuracy: 1e-9)
        var previous = 1.2
        for step in 1...30 {
            let value = BraidLens.settle(from: 1.2, to: 0, elapsed: Double(step) * 0.01, duration: BraidLens.foldSeconds)
            XCTAssertLessThanOrEqual(value, previous)
            XCTAssertGreaterThanOrEqual(value, 0, "measured boundaries never overshoot")
            previous = value
        }
        XCTAssertEqual(BraidLens.settle(from: 1.2, to: 0, elapsed: 0.24, duration: 0.24), 0)
        XCTAssertEqual(BraidLens.settle(from: 0.4, to: 1, elapsed: 0.18, duration: BraidLens.openSeconds), 1)
        XCTAssertEqual(BraidLens.settle(from: 0, to: 1, elapsed: 0, duration: 0), 1, "Reduce Motion jumps")
        XCTAssertNotEqual(BraidLens.ring(elapsed: 0.02), 0)
        XCTAssertLessThanOrEqual(abs(BraidLens.ring(elapsed: 0.02)), 1.5)
        XCTAssertEqual(BraidLens.ring(elapsed: BraidLens.ringSeconds), 0)
    }

    func testHuesStayApartAndOffRed() {
        let hues = BraidLens.separatedHues([0.58, 0.57, 0.59, 0.0, 0.99])
        XCTAssertEqual(hues[0], 0.58, accuracy: 1e-9, "the biggest strand keeps its icon's hue")
        for (index, hue) in hues.enumerated() {
            for other in hues[..<index] {
                let distance = min(abs(hue - other), 1 - abs(hue - other))
                XCTAssertGreaterThanOrEqual(distance, BraidLens.minimumHueGap - 1e-9)
            }
            XCTAssertTrue((1.0 / 12...(1 - 1.0 / 12)).contains(hue), "red stays for bad states: \(hue)")
        }
    }

    func testFocusFollowsBandsWithHysteresisAndGivesThinStrandsATarget() {
        let bands = [(lower: 0.0, upper: 40.0), (lower: 48, upper: 50), (lower: 58, upper: 90)]
        XCTAssertEqual(BraidLens.focus(y: 20, bands: bands, current: nil), 0)
        XCTAssertEqual(BraidLens.focus(y: 44, bands: bands, current: 0), 0, "still within 6 pt of the current band")
        XCTAssertEqual(BraidLens.focus(y: 47, bands: bands, current: 0), 1, "the 2 pt strand still catches the pointer")
        XCTAssertEqual(BraidLens.focus(y: 70, bands: bands, current: 1), 2)
        XCTAssertNil(BraidLens.focus(y: 120, bands: bands, current: nil))
    }
}
