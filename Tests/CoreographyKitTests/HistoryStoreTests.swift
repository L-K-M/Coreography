import Foundation
import XCTest
import CoreographyDrivers
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
        // The Month tier's daily totals keep the name; it leaves with them (see the app-days test).
        let names = try await store.storedAppNames()
        XCTAssertEqual(names, ["New App", "Old App"], "a name lives as long as its intervals or its days")

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
        // Separate inference steps so Xcode can compile this stress fixture.
        let intervals: [LedgerInterval] = (0..<10_000).map { index in
            let start = Double(index * 2 - 20_000)
            let end = Double(index * 2 - 19_998)
            let app = entry("App \(index % 50)", 1, 4096)
            return interval(start, end, [app])
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

    func testMonthTierKeepsMinuteExtremesAndMeans() async throws {
        let store = try HistoryStore(directory: directory)
        // now - 20 is a minute boundary: 1_699_999_980 is a multiple of 60.
        try await store.append([sample(.cpu, -21, 5), sample(.cpu, -20, 10), sample(.cpu, 30, 40), sample(.cpu, 31, nil, .gap)], now: now)
        let minutes = try await store.rollups(.cpu, tier: .month, from: now.addingTimeInterval(-120), to: now.addingTimeInterval(60))
        XCTAssertEqual(minutes.map(\.time), [now.addingTimeInterval(-80), now.addingTimeInterval(-20)])
        let last = try XCTUnwrap(minutes.last)
        XCTAssertEqual([last.minimum, last.maximum, last.mean], [10, 40, 25])
        XCTAssertEqual(last.count, 2, "the gap is not a reading")

        // A week on, the Day tier has let go and the Month tier still holds the minute.
        let weekLater = now.addingTimeInterval(HistoryStore.dayRetention + 60)
        try await store.append([sample(.memoryUsed, HistoryStore.dayRetention + 60, 1)], now: weekLater)
        let day = try await store.rollups(.cpu, from: .distantPast, to: weekLater)
        let month = try await store.rollups(.cpu, tier: .month, from: .distantPast, to: weekLater)
        XCTAssertTrue(day.isEmpty)
        XCTAssertEqual(month.count, 2)

        let monthLater = now.addingTimeInterval(HistoryStore.monthRetention + 60)
        try await store.append([sample(.memoryUsed, HistoryStore.monthRetention + 60, 1)], now: monthLater)
        let expired = try await store.rollups(.cpu, tier: .month, from: .distantPast, to: monthLater)
        XCTAssertTrue(expired.isEmpty)
    }

    func testAppDaysTotalTheLedgerPerLocalDayWithoutDoubleCountingReplacements() async throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let store = try HistoryStore(directory: directory, maximumBytes: HistoryStore.maximumBytes, calendar: utc)
        // now is 22:13:20 UTC; the next midnight is 6400 s later.
        let today = utc.startOfDay(for: now)
        let tomorrow = today.addingTimeInterval(86_400)
        try await store.append([], ledger: [
            interval(-12, -10, [entry("Safari", 2, 100)]),
            interval(-10, 0, [entry("Safari", 3, 50), entry("Mail", 1, 0, lowerBound: true)]),
            interval(6_400, 6_410, [entry("Safari", 4, 0)])
        ], now: now.addingTimeInterval(6_410))

        let days = try await store.appDays(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(days, [
            AppDayTotal(day: today, app: "Mail", cpuSeconds: 1, diskBytes: 0, isLowerBound: true),
            AppDayTotal(day: today, app: "Safari", cpuSeconds: 5, diskBytes: 150, isLowerBound: false),
            AppDayTotal(day: tomorrow, app: "Safari", cpuSeconds: 4, diskBytes: 0, isLowerBound: false)
        ])

        // A replaced interval takes its old figures out of the day; an app idle in it leaves.
        try await store.append([], ledger: [interval(-10, 0, [entry("Safari", 1, 0)])], now: now.addingTimeInterval(6_410))
        let replaced = try await store.appDays(from: today, to: today)
        XCTAssertEqual(replaced, [AppDayTotal(day: today, app: "Safari", cpuSeconds: 3, diskBytes: 100, isLowerBound: false)])

        // Names outlive the six-hour ledger while their days are kept, then leave with them.
        let dayLater = now.addingTimeInterval(86_400)
        try await store.append([sample(.cpu, 86_400, 1)], now: dayLater)
        let ledger = try await store.ledger(from: .distantPast, to: dayLater)
        XCTAssertTrue(ledger.isEmpty)
        let kept = try await store.storedAppNames()
        XCTAssertEqual(kept, ["Safari"])
        let monthLater = now.addingTimeInterval(HistoryStore.monthRetention + 2 * 86_400)
        try await store.append([sample(.cpu, HistoryStore.monthRetention + 2 * 86_400, 1)], now: monthLater)
        let gone = try await store.appDays(from: .distantPast, to: .distantFuture)
        XCTAssertTrue(gone.isEmpty)
        let names = try await store.storedAppNames()
        XCTAssertTrue(names.isEmpty, "no identifier outlives its retention")
    }

    func testAStoreFromBeforeNetworkGainsItsColumnsAndKeepsItsRows() async throws {
        // A schema-4 store: the ledger and app days without network columns.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let old = try SQLiteConnection(path: directory.appendingPathComponent("history.sqlite").path)
            try old.execute("""
                CREATE TABLE apps(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
                CREATE TABLE ledger_intervals(t_end REAL PRIMARY KEY, t_start REAL NOT NULL, cores REAL NOT NULL) WITHOUT ROWID;
                CREATE TABLE ledger_entries(
                    t_end REAL NOT NULL, app INTEGER NOT NULL, cpu_seconds REAL NOT NULL,
                    disk_bytes REAL NOT NULL, lower_bound INTEGER NOT NULL, PRIMARY KEY(t_end, app)
                ) WITHOUT ROWID;
                CREATE TABLE app_days(
                    day REAL NOT NULL, app INTEGER NOT NULL, cpu_seconds REAL NOT NULL,
                    disk_bytes REAL NOT NULL, lower_bound INTEGER NOT NULL, PRIMARY KEY(day, app)
                ) WITHOUT ROWID;
                INSERT INTO apps(id, name) VALUES (1, 'Old App');
                INSERT INTO ledger_intervals VALUES (\(now.timeIntervalSince1970), \(now.timeIntervalSince1970 - 2), 8);
                INSERT INTO ledger_entries VALUES (\(now.timeIntervalSince1970), 1, 3, 4, 0);
                PRAGMA user_version=4;
                """)
        }

        let store = try HistoryStore(directory: directory)
        let old = try await store.ledger(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(old, [LedgerInterval(
            start: now.addingTimeInterval(-2), end: now, cores: 8, coversNetwork: false,
            entries: [LedgerEntry(app: "Old App", cpuSeconds: 3, diskBytes: 4, networkBytes: 0, isLowerBound: false)]
        )], "earlier rows read as not covering network")

        let covered = interval(2, 4, [entry("New App", 1, 0, network: 500)], coversNetwork: true)
        try await store.append([], ledger: [covered], now: now.addingTimeInterval(4))
        let both = try await store.ledger(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(both.last, covered)
        let days = try await store.appDays(from: .distantPast, to: .distantFuture)
        XCTAssertEqual(days.first { $0.app == "New App" }?.networkBytes, 500)
    }

    /// Retention runs on every write; a full scan of six hours of samples would cost CPU every second.
    func testRetentionDeletesSeekTheKey() throws {
        _ = try HistoryStore(directory: directory)
        let connection = try SQLiteConnection(path: directory.appendingPathComponent("history.sqlite").path)
        for statement in HistoryStore.Prune.all {
            // One value per placeholder; the plan does not depend on them.
            let values = Array(repeating: SQLiteValue.real(0), count: statement.filter { $0 == "?" }.count)
            let plan = try connection.query("EXPLAIN QUERY PLAN " + statement, values)
                .compactMap { row in row.last.flatMap { if case .text(let detail) = $0 { detail } else { nil } } }
            XCTAssertFalse(plan.isEmpty, statement)
            XCTAssertTrue(plan.allSatisfy { $0.hasPrefix("SEARCH") }, "\(statement): \(plan)")
        }
    }

    func testANewerStoreIsRefusedRatherThanRelabelled() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("history.sqlite").path
        try SQLiteConnection(path: path).execute("PRAGMA user_version=\(HistoryStore.schemaVersion + 1)")
        XCTAssertThrowsError(try HistoryStore(directory: directory)) { error in
            guard case HistoryStoreError.storage(let reason) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(reason.hasPrefix("History was written by a newer Coreography"), reason)
        }
        let version = try SQLiteConnection(path: path).query("PRAGMA user_version").first?.first
        XCTAssertEqual(version, .integer(Int64(HistoryStore.schemaVersion + 1)), "an older build leaves the newer label alone")
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

    /// coreo opens the store beside the app; a held write lock must make it wait, not fail.
    func testASecondWriterWaitsForTheLockInsteadOfFailing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("lock.sqlite").path
        nonisolated(unsafe) let holder = try SQLiteConnection(path: path)
        try holder.execute("PRAGMA journal_mode=WAL; CREATE TABLE t(x)")
        try holder.execute("BEGIN IMMEDIATE")
        nonisolated(unsafe) var committed = false
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { committed = (try? holder.execute("COMMIT")) != nil }

        let waiter = try SQLiteConnection(path: path)
        XCTAssertNoThrow(try waiter.execute("INSERT INTO t VALUES (1)"))
        // COMMIT releases the lock inside execute, a moment before the flag is set.
        let deadline = Date().addingTimeInterval(2)
        while !committed, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(committed, "the fixture's own commit worked, so a failure above is the wait's")
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

    private func interval(
        _ start: TimeInterval, _ end: TimeInterval, _ entries: [LedgerEntry], coversNetwork: Bool = false
    ) -> LedgerInterval {
        LedgerInterval(
            start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), cores: 8,
            coversNetwork: coversNetwork, entries: entries
        )
    }

    private func entry(_ app: String, _ cpu: Double, _ disk: Double, network: Double = 0, lowerBound: Bool = false) -> LedgerEntry {
        LedgerEntry(app: app, cpuSeconds: cpu, diskBytes: disk, networkBytes: network, isLowerBound: lowerBound)
    }

    private func sample(
        _ metric: HistoryMetric, _ offset: TimeInterval, _ value: Double?, _ availability: MetricAvailability = .measured
    ) -> HistorySample {
        HistorySample(metric: metric, time: now.addingTimeInterval(offset), value: value, availability: availability)
    }
}
