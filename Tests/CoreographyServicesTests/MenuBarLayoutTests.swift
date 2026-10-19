import Foundation
import XCTest
@testable import CoreographyServices

final class MenuBarLayoutTests: XCTestCase {
    func testItemsAreUniqueAtMostThreeAndNeverEmpty() throws {
        XCTAssertEqual(MenuBarLayout.normalized([]), MenuBarLayout.defaultItems)
        let many: [MenuBarItem] = [
            .init(metric: .cpu, style: .both), .init(metric: .cpu, style: .value), .init(metric: .memory, style: .graph),
            .init(metric: .gpu, style: .value), .init(metric: .download, style: .value)
        ]
        XCTAssertEqual(MenuBarLayout.normalized(many).map(\.metric), [.cpu, .memory, .gpu], "first of each, three at most")
        XCTAssertEqual(MenuBarLayout.normalized(many).first?.style, .both)

        let suite = "MenuBarLayoutTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(MenuBarLayout.saved(in: defaults), MenuBarLayout.defaultItems)
        MenuBarLayout.save(many, in: defaults)
        XCTAssertEqual(MenuBarLayout.saved(in: defaults).count, 3)
    }
}
