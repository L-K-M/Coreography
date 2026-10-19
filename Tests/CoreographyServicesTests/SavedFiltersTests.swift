import Foundation
import XCTest
@testable import CoreographyServices

final class SavedFiltersTests: XCTestCase {
    func testChipsAreNewestFirstWithoutDuplicatesOrBlanksAndBounded() throws {
        let suite = "coreo-filters-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedFilters(defaults: defaults)

        store.save("cpu:>10")
        store.save("  ")
        store.save("#listening")
        XCTAssertEqual(store.save(" cpu:>10 "), ["cpu:>10", "#listening"], "saving again moves it to the front")
        XCTAssertEqual(store.remove("#listening"), ["cpu:>10"])

        for index in 0..<20 { store.save("pid:\(index)") }
        XCTAssertEqual(store.all.count, SavedFilters.limit)
        XCTAssertEqual(store.all.first, "pid:19")
    }

    func testStoredDuplicatesAndBlanksNeverReachTheChips() throws {
        let suite = "coreo-filters-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // An older build or a hand edit: the row keys chips by their text.
        defaults.set(["cpu:>10", "\n", "cpu:>10", "#new"], forKey: "savedProcessFilters")
        let store = SavedFilters(defaults: defaults)
        XCTAssertEqual(store.all, ["cpu:>10", "#new"])
        XCTAssertEqual(store.remove("#absent"), ["cpu:>10", "#new"])
    }

    @MainActor
    func testTheModelSavesTheCurrentFilter() async throws {
        let suite = "coreo-model-filters-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DashboardModel()
        model.useFilterStore(defaults)
        model.processFilter = "mem:>1GB"
        model.saveProcessFilter()
        XCTAssertEqual(model.savedFilters, ["mem:>1GB"])
        model.removeSavedFilter("mem:>1GB")
        XCTAssertTrue(model.savedFilters.isEmpty)
    }
}
