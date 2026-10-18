import Foundation
import XCTest
@testable import CoreographyServices

final class DecimationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testOneSampleSpikeSurvivesAnHourAtDefaultBuckets() {
        var points = (0..<3600).map { point(second: $0, value: 10, segment: 0) }
        points[1234] = point(second: 1234, value: 97, segment: 0)
        let kept = Decimation.points(points, start: start, end: start.addingTimeInterval(3600))

        XCTAssertLessThanOrEqual(kept.count, Decimation.defaultBuckets * 2)
        XCTAssertTrue(kept.contains { $0.value == 97 })
        XCTAssertEqual(kept.map(\.time), kept.map(\.time).sorted())
    }

    func testBucketsNeverMergeAcrossSegmentsAndShortSeriesPassThrough() {
        // A gap at second 1800 splits the series; both sides keep their own extremes.
        let points = (0..<3600).map { point(second: $0, value: Double($0 % 7), segment: $0 < 1800 ? 0 : 1) }
        let kept = Decimation.points(points, start: start, end: start.addingTimeInterval(3600))
        XCTAssertEqual(Set(kept.map(\.segment)), [0, 1])
        XCTAssertTrue(kept.filter { $0.segment == 0 }.allSatisfy { $0.time < start.addingTimeInterval(1800) })

        let short = (0..<60).map { point(second: $0, value: 1, segment: 0) }
        XCTAssertEqual(Decimation.points(short, start: start, end: start.addingTimeInterval(60)).count, 60)
    }

    func testStackedLayersDecimateTogetherAndKeepThePeakTotal() {
        var stack: [MemoryStackPoint] = []
        for second in 0..<3600 {
            let total = second == 2000 ? 900.0 : 400
            var lower = 0.0
            for (category, share) in zip(MemoryCategory.allCases, [0.5, 0.2, 0.2, 0.1]) {
                let upper = lower + total * share
                stack.append(MemoryStackPoint(
                    id: "\(second)-\(category.rawValue)", time: start.addingTimeInterval(TimeInterval(second)),
                    category: category, lower: lower, upper: upper, segment: 0
                ))
                lower = upper
            }
        }
        let kept = Decimation.stack(stack, start: start, end: start.addingTimeInterval(3600))
        let byTime = Dictionary(grouping: kept, by: \.time)
        XCTAssertTrue(byTime.values.allSatisfy { $0.count == MemoryCategory.allCases.count })
        XCTAssertTrue(kept.contains { $0.category == .cached && $0.upper == 900 })
        XCTAssertLessThan(kept.count, stack.count / 2)
    }

    private func point(second: Int, value: Double, segment: Int) -> DashboardPoint {
        DashboardPoint(id: UUID(), time: start.addingTimeInterval(TimeInterval(second)), value: value, segment: segment)
    }
}
