import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class HistoryStatsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plan: the CLI's stats over a time range.
    func testStatsUseRecordedValuesAndCountGaps() {
        let values: [Double?] = (1...20).map(Double.init) + [nil, nil]
        let samples = values.enumerated().map { offset, value in
            HistorySample(metric: .cpu, time: epoch.addingTimeInterval(Double(offset)), value: value,
                          availability: value == nil ? .gap : .measured)
        }
        let stats = HistoryStats.stats(.cpu, samples.shuffled())
        XCTAssertEqual(stats.metric, "cpu")
        XCTAssertEqual(stats.storedSamples, 22)
        XCTAssertEqual(stats.valued, 20, "a gap is counted, not read as zero")
        XCTAssertEqual(stats.minimum, 1)
        XCTAssertEqual(stats.median, 10, "nearest rank: the 10th of 20")
        XCTAssertEqual(stats.p95, 19)
        XCTAssertEqual(stats.maximum, 20)
        XCTAssertEqual(stats.mean, 10.5)
    }

    func testPressureLevelsAreNotAveragedAndEmptyMetricsHaveNoValues() {
        let levels = [0.0, 0, 2].map {
            HistorySample(metric: .memoryPressure, time: epoch, value: $0, availability: .measured)
        }
        let pressure = HistoryStats.stats(.memoryPressure, levels)
        XCTAssertNil(pressure.mean, "a severity ordinal has no mean")
        XCTAssertEqual(pressure.median, 0)
        XCTAssertEqual(pressure.maximum, 2)

        let empty = HistoryStats.stats(.gpuBusy, [])
        XCTAssertEqual(empty, MetricStats(
            metric: "gpuBusy", storedSamples: 0, valued: 0, minimum: nil, median: nil, p95: nil, maximum: nil, mean: nil
        ))
    }
}
