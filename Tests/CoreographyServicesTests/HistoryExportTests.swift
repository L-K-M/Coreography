import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class HistoryExportTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plan: the CLI's export. Each stored sample is one row; a gap is an empty cell.
    func testTheCSVHasOneRowPerStoredSampleInTimeOrder() {
        let samples: [HistoryMetric: [HistorySample]] = [
            .cpu: [
                HistorySample(metric: .cpu, time: epoch.addingTimeInterval(2), value: 30, availability: .measured),
                HistorySample(metric: .cpu, time: epoch, value: 12.5, availability: .measured)
            ],
            .gpuBusy: [HistorySample(metric: .gpuBusy, time: epoch, value: nil, availability: .gap)]
        ]
        let document = HistoryExport.document(window: epoch...epoch.addingTimeInterval(60), samples: samples)
        XCTAssertEqual(document.metrics.count, HistoryMetric.allCases.count, "metrics without samples are listed, empty")
        XCTAssertEqual(HistoryExport.csv(document), """
        time,metric,value,availability
        2023-11-14T22:13:20Z,cpu,12.5,measured
        2023-11-14T22:13:20Z,gpuBusy,,gap
        2023-11-14T22:13:22Z,cpu,30.0,measured

        """)
    }
}
