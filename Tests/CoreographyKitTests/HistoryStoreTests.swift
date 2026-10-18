import Foundation
import XCTest
@testable import CoreographyKit

final class HistoryStoreTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-history-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripKeepsGapsAndReplacesDuplicates() async throws {
        let store = try HistoryStore(directory: directory)
        try await store.append([
            sample(.cpu, -2, 10), sample(.cpu, -1, nil, .gap), sample(.cpu, 0, 30),
            sample(.memoryUsed, 0, 4096, .estimated), sample(.cpu, 0, 35)
        ], now: now)

        let cpu = try await store.samples(.cpu, from: now.addingTimeInterval(-10), to: now)
        XCTAssertEqual(cpu.map(\.value), [10, nil, 35], "a gap stays a gap; a repeat replaces")
        XCTAssertEqual(cpu.map(\.availability), [.measured, .gap, .measured])
        let memory = try await store.samples(.memoryUsed, from: now, to: now)
        XCTAssertEqual(memory.first?.availability, .estimated)
        let count = try await store.sampleCount()
        XCTAssertEqual(count, 4)
    }

    func testRetentionDropsSamplesOlderThanSixHours() async throws {
        let store = try HistoryStore(directory: directory)
        try await store.append([sample(.cpu, -HistoryStore.retention - 5, 1), sample(.cpu, -60, 2)], now: now)
        let kept = try await store.samples(.cpu, from: .distantPast, to: now)
        XCTAssertEqual(kept.map(\.value), [2])
    }

    func testPersistsAcrossReopenWithPrivateFilesInWALMode() async throws {
        do {
            let store = try HistoryStore(directory: directory)
            try await store.append([sample(.thermalPressure, 0, 1)], now: now)
        }
        let reopened = try HistoryStore(directory: directory)
        let values = try await reopened.samples(.thermalPressure, from: now, to: now).map(\.value)
        XCTAssertEqual(values, [1])

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let file = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("history.sqlite").path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.sqlite-wal").path))

        try await reopened.deleteAll()
        let count = try await reopened.sampleCount()
        XCTAssertEqual(count, 0)
    }

    private func sample(
        _ metric: HistoryMetric, _ offset: TimeInterval, _ value: Double?, _ availability: MetricAvailability = .measured
    ) -> HistorySample {
        HistorySample(metric: metric, time: now.addingTimeInterval(offset), value: value, availability: availability)
    }
}
