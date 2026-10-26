import Foundation
import XCTest
@testable import CoreographyKit
import CoreographyDrivers

final class PluckToneTests: XCTestCase {
    func testAnAppAlwaysPlucksTheSameNoteFromTheScale() {
        let xcode = PluckTone.frequency(for: "Xcode")
        XCTAssertEqual(PluckTone.frequency(for: "Xcode"), xcode)
        XCTAssertTrue(PluckTone.scale.contains(xcode))
        let notes = Set(["Safari", "Xcode", "Mail", "WindowServer", "mds_stores", "Music"].map(PluckTone.frequency(for:)))
        XCTAssertGreaterThan(notes.count, 1, "different apps spread over the scale")
    }

    /// Cues are quiet and short: the scope pluck peaks at -22 dBFS over
    /// 110 ms, rings at its pitch and dies away.
    func testCuesPeakAtTheirLevelRingAndDecay() throws {
        let samples = PluckTone.samples(for: .scope(app: "Xcode"))
        XCTAssertEqual(samples.count, Int(0.11 * PluckTone.sampleRate))
        let peak = try XCTUnwrap(samples.map(abs).max())
        XCTAssertEqual(Double(peak), pow(10, -22.0 / 20), accuracy: 1e-4)

        let quarter = samples.count / 4
        func rms(_ slice: ArraySlice<Float>) -> Double {
            (slice.reduce(0) { $0 + Double($1 * $1) } / Double(slice.count)).squareRoot()
        }
        XCTAssertLessThan(rms(samples.suffix(quarter)), rms(samples.prefix(quarter)), "it decays like a string")
        XCTAssertEqual(samples.first, 0, "a fade-in, no click")
        XCTAssertEqual(PluckTone.samples(for: .scope(app: "Xcode")), samples, "seeded: the same every time")

        XCTAssertLessThan(try XCTUnwrap(PluckTone.samples(for: .fold).map(abs).max()), peak, "folding is quieter")
        XCTAssertEqual(PluckTone.samples(for: .open).count, Int(0.06 * PluckTone.sampleRate))
    }
}

@MainActor
final class FeedbackTonesTests: XCTestCase {
    private actor Recorder: TonePlaying {
        var played: [[Float]] = []
        func play(_ samples: [Float], sampleRate: Double) -> Bool {
            played.append(samples)
            return true
        }
    }

    func testCuesPlayUnlessEitherSwitchIsOff() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "feedback-\(UUID().uuidString)"))
        let output = Recorder()
        let tones = FeedbackTones(output: output, defaults: defaults)

        let played = await tones.play(.scope(app: "Xcode"))?.value
        XCTAssertEqual(played, true)
        let first = await output.played
        XCTAssertEqual(first, [PluckTone.samples(for: .scope(app: "Xcode"))], "both switches default to on")

        defaults.set(false, forKey: FeedbackTones.settingKey)
        XCTAssertNil(tones.play(.fold))
        defaults.set(true, forKey: FeedbackTones.settingKey)
        defaults.set(0, forKey: "com.apple.sound.uiaudio.enabled")
        XCTAssertNil(tones.play(.open), "the app's switch and macOS's both silence it")
        let count = await output.played.count
        XCTAssertEqual(count, 1)
    }
}
