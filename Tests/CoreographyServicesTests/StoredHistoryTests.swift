import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class StoredHistoryTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let layers: [HistoryMetric] = [.memoryApp, .memoryWired, .memoryCompressed, .memoryCached]

    func testLoadReducesLinesAndKeepsGapsPeaksStacksAndBands() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-stored-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)

        // Two hours at 1 s with a ten-minute silence and one unreadable CPU sample.
        var samples: [HistorySample] = []
        for second in (0..<7200) where !(3600..<4200).contains(second) {
            let time = epoch.addingTimeInterval(TimeInterval(second))
            let unreadable = second == 100
            samples.append(HistorySample(
                metric: .cpu, time: time, value: unreadable ? nil : Double(second % 100),
                availability: unreadable ? .gap : .measured
            ))
            for (index, metric) in layers.enumerated() {
                samples.append(HistorySample(metric: metric, time: time, value: Double(index + 1), availability: .measured))
            }
            samples.append(HistorySample(
                metric: .memoryPressure, time: time, value: second < 1000 ? 0 : 1, availability: .measured
            ))
        }
        let end = epoch.addingTimeInterval(7200)
        try await store.append(samples, now: end)

        let history = try await StoredHistory.load(from: HistoryRecorder(store: store), start: epoch, end: end)

        let cpu = try XCTUnwrap(history.lines[.cpu])
        XCTAssertLessThan(cpu.count, 1000, "reduced once at load")
        XCTAssertTrue(cpu.contains { $0.value == 99 }, "peaks survive the reduction")
        XCTAssertEqual(Set(cpu.map(\.segment)).count, 3, "the unreadable sample and the silence both break the line")
        XCTAssertEqual(history.lines[.gpuBusy]?.isEmpty, true)

        let first = history.memoryStack.prefix(4).map { [$0.lower, $0.upper] }
        XCTAssertEqual(first, [[0, 1], [1, 3], [3, 6], [6, 10]])
        XCTAssertEqual(Set(history.memoryStack.map(\.segment)).count, 2)

        XCTAssertEqual(history.memoryPressure.map(\.level), [.normal, .warning, .warning])
        XCTAssertEqual(history.memoryPressure.last?.start, epoch.addingTimeInterval(4200), "no band bridges the silence")
    }

    func testLongRangesReadTheDayTierKeepingPeaksAndExactMeans() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-day-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let end = epoch.addingTimeInterval(20 * 3600)
        // Ten hours ago: one minute at 10% with a single 90% spike, then pressure turns critical.
        let start = end.addingTimeInterval(-10 * 3600)
        var samples: [HistorySample] = []
        for second in 0..<60 {
            let time = start.addingTimeInterval(Double(second))
            samples.append(HistorySample(metric: .cpu, time: time, value: second == 33 ? 90 : 10, availability: .measured))
            samples.append(HistorySample(metric: .memoryPressure, time: time, value: second < 30 ? 0 : 2, availability: .measured))
        }
        try await store.append(samples, now: end)

        let history = try await StoredHistory.load(
            from: HistoryRecorder(store: store), start: end.addingTimeInterval(-86_400), end: end
        )
        XCTAssertEqual(history.tier, .day)
        XCTAssertEqual(history.lines[.cpu]?.map(\.value).max(), 90, "the spike survives the 10 s rollup")
        let values = history.values(.cpu, in: start...end, before: end)
        XCTAssertFalse(values.isEmpty, "the 24 h range reads Day-tier buckets")
        // Live data starting mid-bucket: that bucket's readings would be counted twice.
        let seam = history.values(.cpu, in: start...end, before: start.addingTimeInterval(15))
        XCTAssertEqual(seam.map(\.count), [10], "only buckets that end before live data starts")
        let mean = values.reduce(0) { $0 + $1.mean * Double($1.count) } / Double(values.reduce(0) { $0 + $1.count })
        XCTAssertEqual(mean, (59 * 10 + 90) / 60.0, accuracy: 1e-9, "count-weighted bucket means stay exact")
        XCTAssertEqual(history.memoryPressure.map(\.level).last, .critical)
        XCTAssertEqual(Set(history.lines[.cpu]?.map(\.segment) ?? []).count, 1, "10 s buckets are not gaps")
    }

    func testStackSkipsInstantsWithAMissingLayer() {
        let time = epoch
        var layers: [MemoryCategory: [HistorySample]] = [:]
        for (category, metric) in zip(MemoryCategory.allCases, self.layers) {
            layers[category] = [
                HistorySample(metric: metric, time: time, value: 1, availability: .measured),
                HistorySample(
                    metric: metric, time: time.addingTimeInterval(1), value: category == .cached ? nil : 1,
                    availability: category == .cached ? .unavailable : .measured
                )
            ]
        }
        let stack = StoredHistory.stack(layers)
        XCTAssertEqual(Set(stack.map(\.time)), [time])
    }
}
