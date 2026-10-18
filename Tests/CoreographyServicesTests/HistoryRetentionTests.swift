import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class HistoryRetentionTests: XCTestCase {
    func testPresetsGrowWithinTheSizeCapAndPersist() throws {
        let estimates = HistoryRetention.allCases.map(\.estimatedBytes)
        XCTAssertEqual(estimates, estimates.sorted(), "longer presets cost more")
        XCTAssertLessThan(estimates.max() ?? 0, HistoryStore.maximumBytes, "every preset fits the hard cap")
        XCTAssertEqual(HistoryRetention.standard.plan, RetentionPlan(recent: HistoryStore.retention, day: HistoryStore.dayRetention))
        XCTAssertEqual(HistoryRetention.standard.detailedHours, 6)
        XCTAssertEqual(HistoryRetention.standard.summaryDays, 7)

        let suite = "coreo-retention-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(HistoryRetention.saved(in: defaults), .standard)
        HistoryRetention.extended.save(in: defaults)
        XCTAssertEqual(HistoryRetention.saved(in: defaults), .extended)
    }

    func testRangesBeyondTheDetailedRetentionReadTheDayTier() {
        XCTAssertEqual(StoredTier.reading(6 * 3600, recentRetention: 6 * 3600), .recent)
        XCTAssertEqual(StoredTier.reading(6 * 3600, recentRetention: 3600), .day, "a compact store has no six hours of detail")
        XCTAssertEqual(StoredTier.reading(86_400, recentRetention: 12 * 3600), .day)
    }
}
