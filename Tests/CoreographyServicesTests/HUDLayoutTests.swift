import Foundation
import XCTest
@testable import CoreographyServices

final class HUDLayoutTests: XCTestCase {
    func testLevelsGrowAndNeverDrawAnEmptyFrameRate() {
        XCTAssertEqual(HUDLayout.items(.single, frameRateAvailable: false, hasHint: false), [.cpu], "no FPS source: CPU, not a blank")
        XCTAssertEqual(HUDLayout.items(.single, frameRateAvailable: true, hasHint: true), [.frameRate])
        XCTAssertEqual(HUDLayout.items(.line, frameRateAvailable: false, hasHint: true), [.cpu, .gpu, .power, .temperature])
        let block = HUDLayout.items(.block, frameRateAvailable: false, hasHint: true)
        XCTAssertEqual(block.last, .hint)
        XCTAssertFalse(block.contains(.frameRate))
        let detailed = HUDLayout.items(.detailed, frameRateAvailable: true, hasHint: false)
        XCTAssertEqual(detailed.first, .frameRate)
        XCTAssertTrue(Set(detailed).isSuperset(of: [.tiers, .memoryPressure, .swap, .network, .batteryTime, .fans]))
        XCTAssertEqual(HUDDensity.detailed.next, .single, "cycling wraps")
    }

    func testSettingsAreSavedAndClamped() throws {
        let suite = "HUDLayoutTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(HUDSettings.saved(in: defaults), HUDSettings())
        var settings = HUDSettings()
        settings.density = .detailed
        settings.corner = .bottomLeft
        settings.opacity = 5
        settings.textScale = 0.1
        settings.scrim = false
        settings.clickThrough = false
        settings.save(in: defaults)
        let saved = HUDSettings.saved(in: defaults)
        XCTAssertEqual(saved.density, .detailed)
        XCTAssertEqual(saved.corner, .bottomLeft)
        XCTAssertEqual(saved.opacity, 1)
        XCTAssertEqual(saved.textScale, 0.8)
        XCTAssertFalse(saved.scrim)
        XCTAssertFalse(saved.clickThrough)
    }
}
