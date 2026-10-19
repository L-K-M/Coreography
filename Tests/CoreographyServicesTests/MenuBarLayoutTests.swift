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

    /// Picking a reading another slot shows swaps the two; nothing is lost.
    func testChoosingASlotSwapsMovesOrRemovesWithoutLoss() {
        let items: [MenuBarItem] = [.init(metric: .cpu, style: .value), .init(metric: .memory, style: .graph)]
        XCTAssertEqual(
            MenuBarLayout.choosing(.memory, at: 0, in: items),
            [.init(metric: .memory, style: .graph), .init(metric: .cpu, style: .value)], "each keeps its style"
        )
        XCTAssertEqual(
            MenuBarLayout.choosing(.gpu, at: 1, in: items),
            [.init(metric: .cpu, style: .value), .init(metric: .gpu, style: .graph)], "a new reading takes the slot's style"
        )
        XCTAssertEqual(MenuBarLayout.choosing(.cpu, at: 2, in: items).map(\.metric), [.memory, .cpu], "an empty slot moves it last")
        XCTAssertEqual(MenuBarLayout.choosing(.gpu, at: 2, in: items).map(\.metric), [.cpu, .memory, .gpu])
        XCTAssertEqual(MenuBarLayout.choosing(nil, at: 1, in: items).map(\.metric), [.cpu])
        XCTAssertEqual(MenuBarLayout.choosing(.cpu, at: 0, in: items), items)
    }
}
