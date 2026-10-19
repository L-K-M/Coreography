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
