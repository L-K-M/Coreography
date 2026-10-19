import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class RangeComparisonTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testAppsCompareByRateSoRangesOfDifferentLengthsAgree() throws {
        // First range: 10 s, Safari 2 CPU-s (0.2 cores). Second: 20 s, Safari 20 CPU-s (1.0 core), Mail new.
        let first = report(seconds: 10, apps: [("Safari", 2, 0), ("Xcode", 9, 100)], mean: 12)
        let second = report(seconds: 20, apps: [("Safari", 20, 0), ("Mail", 0.1, 0), ("Xcode", 18, 0)], mean: 38)
        let comparison = RangeComparison.make(first: first, second: second)
        XCTAssertEqual(comparison.changes.map(\.app), ["Safari"], "Xcode kept 0.9 cores; Mail moved under a hundredth")
        let safari = try XCTUnwrap(comparison.changes.first)
        XCTAssertEqual(safari.firstCores, 0.2, accuracy: 1e-9)
        XCTAssertEqual(safari.secondCores, 1.0, accuracy: 1e-9)
        XCTAssertEqual(comparison.cpuMeanChange ?? 0, 26, accuracy: 1e-9)
        XCTAssertNil(comparison.memoryPeakChange)
    }

    func testARangeWithoutCoverageComparesNoApps() {
        let empty = RangeReport(
            requested: epoch...epoch.addingTimeInterval(5), covered: nil, topCPUApps: [], topDiskApps: [], topNetworkApps: nil,
            topEnergyApps: nil, activeAppCount: 0, apps: [], cpuMeanPercent: nil, cpuPeakPercent: nil, memoryPeakBytes: nil,
            gpuPeakPercent: nil, hottest: nil
        )
        let comparison = RangeComparison.make(first: empty, second: report(seconds: 10, apps: [("Safari", 5, 0)], mean: 1))
        XCTAssertTrue(comparison.changes.isEmpty)
        XCTAssertFalse(comparison.coversBoth, "no change is unknown here, not stable")
        XCTAssertTrue(RangeComparison.make(first: report(seconds: 5, apps: [], mean: 1), second: report(seconds: 5, apps: [], mean: 1)).coversBoth)
    }

    private func report(seconds: TimeInterval, apps: [(String, Double, Double)], mean: Double) -> RangeReport {
        let range = epoch...epoch.addingTimeInterval(seconds)
        let totals = apps.map { AppRangeTotal(name: $0.0, cpuSeconds: $0.1, diskBytes: $0.2, isLowerBound: false) }
        return RangeReport(
            requested: range, covered: range, topCPUApps: totals, topDiskApps: [], topNetworkApps: nil,
            topEnergyApps: nil, activeAppCount: totals.count, apps: totals, cpuMeanPercent: mean, cpuPeakPercent: mean,
            memoryPeakBytes: nil, gpuPeakPercent: nil, hottest: nil
        )
    }
}
