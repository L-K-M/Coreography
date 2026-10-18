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

    func testSizeCapDropsOldestHistoryOnceRatherThanOnEveryBatch() async throws {
        let store = try HistoryStore(directory: directory, maximumBytes: 256 * 1024)
        let filled = (0..<20_000).map { sample(.cpu, TimeInterval($0 - 20_000), Double($0)) }
        try await store.append(filled, now: now)
        let afterCap = try await store.sampleCount()
        XCTAssertLessThan(afterCap, 20_000, "the cap dropped the oldest samples")
        let oldest = try await store.samples(.cpu, from: .distantPast, to: now).first?.value
        XCTAssertGreaterThan(oldest ?? 0, 0, "oldest first")

        // Freed pages are not history: a small batch under the cap must not drop more.
        try await store.append([sample(.memoryUsed, 0, 1)], now: now)
        let afterBatch = try await store.sampleCount()
        XCTAssertEqual(afterBatch, afterCap + 1)
    }

    func testLedgerRoundTripKeepsIdleIntervalsAndReplacesWholeIntervals() async throws {
        let store = try HistoryStore(directory: directory)
        let busy = interval(-4, -2, [entry("Safari", 1.5, 4096), entry("Mail", 0.25, 0, lowerBound: true)])
        let idle = interval(-2, 0, [])
        try await store.append([], ledger: [busy, idle], now: now)

        let read = try await store.ledger(from: now.addingTimeInterval(-10), to: now)
        XCTAssertEqual(read, [interval(-4, -2, [entry("Mail", 0.25, 0, lowerBound: true), entry("Safari", 1.5, 4096)]), idle])

        // A rewritten interval replaces every entry, so Mail's old figures go.
        try await store.append([], ledger: [interval(-4, -2, [entry("Safari", 2, 0)])], now: now)
        let rewritten = try await store.ledger(from: now.addingTimeInterval(-10), to: now.addingTimeInterval(-1))
        XCTAssertEqual(rewritten.first?.entries, [entry("Safari", 2, 0)])
    }

    func testLedgerAgesOutWithItsAppNamesAndDeletesWithHistory() async throws {
        let store = try HistoryStore(directory: directory)
        try await store.append([], ledger: [interval(-4, -2, [entry("Old App", 1, 0)])], now: now)
        let later = now.addingTimeInterval(HistoryStore.retention + 3600)
        try await store.append([], ledger: [interval(HistoryStore.retention + 3598, HistoryStore.retention + 3600, [entry("New App", 1, 0)])], now: later)

        let kept = try await store.ledger(from: .distantPast, to: later)
        XCTAssertEqual(kept.flatMap(\.entries).map(\.app), ["New App"])
        let names = try await store.storedAppNames()
        XCTAssertEqual(names, ["New App"], "no name outlives its intervals past the sweep")

        try await store.deleteAll()
        let afterDelete = try await store.ledger(from: .distantPast, to: later)
        XCTAssertTrue(afterDelete.isEmpty)
        let namesAfterDelete = try await store.storedAppNames()
        XCTAssertTrue(namesAfterDelete.isEmpty)

        // Interning starts over cleanly after deletion.
        try await store.append([], ledger: [interval(HistoryStore.retention + 3600, HistoryStore.retention + 3602, [entry("New App", 1, 0)])], now: later)
        let reinterned = try await store.ledger(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(reinterned.flatMap(\.entries).map(\.app), ["New App"])
    }

    func testSizeCapAlsoBoundsLedgerOnlyHistory() async throws {
        let store = try HistoryStore(directory: directory, maximumBytes: 256 * 1024)
        let intervals = (0..<10_000).map { index in
            interval(Double(index * 2 - 20_000), Double(index * 2 - 19_998), [entry("App \(index % 50)", 1, 4096)])
        }
        try await store.append([], ledger: intervals, now: now)
        let kept = try await store.ledger(from: .distantPast, to: now)
        XCTAssertLessThan(kept.count, intervals.count, "the cap applies when only the ledger holds data")
        XCTAssertEqual(kept.last?.end, intervals.last?.end, "newest intervals stay")
    }

    func testDayTierKeepsTenSecondExtremesAndMeansForSevenDays() async throws {
        let store = try HistoryStore(directory: directory)
        // now is a bucket boundary: 1_700_000_000 is a multiple of 10.
        try await store.append([
            sample(.cpu, -20, 10), sample(.cpu, -19, 30), sample(.cpu, -18, nil, .gap), sample(.cpu, -11, 20),
            sample(.cpu, -10, 50)
        ], now: now)
        // A later batch landing in an existing bucket combines with it.
        try await store.append([sample(.cpu, -15, 2)], now: now)

        let rollups = try await store.rollups(.cpu, from: now.addingTimeInterval(-60), to: now)
        XCTAssertEqual(rollups.map(\.time), [now.addingTimeInterval(-20), now.addingTimeInterval(-10)])
        let first = try XCTUnwrap(rollups.first)
        XCTAssertEqual(first.minimum, 2)
        XCTAssertEqual(first.maximum, 30)
        XCTAssertEqual(first.count, 4, "the gap is not a reading")
        XCTAssertEqual(first.mean, (10 + 30 + 20 + 2) / 4.0, accuracy: 1e-9)
        XCTAssertEqual(rollups.last?.mean, 50)

        // Readings older than six hours leave the Recent tier but stay in the Day tier for a week.
        let later = now.addingTimeInterval(10 * 3600)
        try await store.append([sample(.memoryUsed, 10 * 3600, 1)], now: later)
        let recent = try await store.samples(.cpu, from: .distantPast, to: later)
        XCTAssertTrue(recent.isEmpty)
        let kept = try await store.rollups(.cpu, from: .distantPast, to: later)
        XCTAssertEqual(kept.count, 2)

        let weekLater = now.addingTimeInterval(HistoryStore.dayRetention + 60)
        try await store.append([sample(.memoryUsed, HistoryStore.dayRetention + 60, 1)], now: weekLater)
        let expired = try await store.rollups(.cpu, from: .distantPast, to: weekLater)
        XCTAssertTrue(expired.isEmpty)

        try await store.deleteAll()
        let deleted = try await store.rollups(.memoryUsed, from: .distantPast, to: .distantFuture)
        XCTAssertTrue(deleted.isEmpty)
    }

    func testARetentionPlanAppliesFromTheNextWrite() async throws {
        let store = try HistoryStore(directory: directory)
        await store.setRetention(RetentionPlan(recent: 3600, day: 86_400))
        try await store.append([sample(.cpu, -7200, 1), sample(.cpu, -60, 2), sample(.memoryUsed, -2 * 86_400, 3)], now: now)
        let recent = try await store.samples(.cpu, from: .distantPast, to: now).map(\.value)
        XCTAssertEqual(recent, [2], "an hour of readings")
        let summary = try await store.rollups(.cpu, from: .distantPast, to: now).count
        XCTAssertEqual(summary, 2, "a day of buckets keeps the two-hour-old reading")
        let tooOld = try await store.rollups(.memoryUsed, from: .distantPast, to: now)
        XCTAssertTrue(tooOld.isEmpty)
        let size = try await store.size()
        XCTAssertGreaterThan(size, 0)
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

    private func interval(_ start: TimeInterval, _ end: TimeInterval, _ entries: [LedgerEntry]) -> LedgerInterval {
        LedgerInterval(start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), cores: 8, entries: entries)
    }

    private func entry(_ app: String, _ cpu: Double, _ disk: Double, lowerBound: Bool = false) -> LedgerEntry {
        LedgerEntry(app: app, cpuSeconds: cpu, diskBytes: disk, isLowerBound: lowerBound)
    }

    private func sample(
        _ metric: HistoryMetric, _ offset: TimeInterval, _ value: Double?, _ availability: MetricAvailability = .measured
    ) -> HistorySample {
        HistorySample(metric: metric, time: now.addingTimeInterval(offset), value: value, availability: availability)
    }
}
