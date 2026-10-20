import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class RecordingTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testARecordingRoundTripsAndRedactsAppsConsistently() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try Self.processes(at: 0, epoch: epoch, [("Secret Project", 50), ("Mail", 10)]), logicalCPUCount: 4)
        ledger.record(try Self.processes(at: 2, epoch: epoch, [("Secret Project", 50), ("Mail", 10)]), logicalCPUCount: 4)
        ledger.record(try Self.processes(at: 4, epoch: epoch, [("Secret Project", 50), ("Mail", 10)]), logicalCPUCount: 4)
        let range = epoch...epoch.addingTimeInterval(10)
        let frames = DashboardFrames(host: [], network: [], disks: [], gpu: [], power: [], sensors: [])
        let markers = [
            TimelineMarker(time: epoch.addingTimeInterval(3), label: "Launched the build", kind: .note),
            TimelineMarker(time: epoch.addingTimeInterval(3), label: "Sleep", kind: .system)
        ]

        let redacted = Recording.make(name: "Build", range: range, frames: frames, ledger: ledger, markers: markers, naming: .redacted)
        let data = try Recording.encode(redacted)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Secret"), "no app name leaves a redacted recording")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Mail"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Launched the build"), "nor the person's marker names")
        let read = try Recording.decode(data)
        XCTAssertEqual(read.ledger.count, 2)
        XCTAssertEqual(Set(read.ledger.flatMap(\.entries).map(\.app)), ["App 1", "App 2"])
        XCTAssertTrue(read.ledger.allSatisfy { interval in interval.entries.first { $0.app == "App 1" }?.cpuSeconds == 4 },
                      "the same app keeps one placeholder, ranked by CPU")
        XCTAssertTrue(read.ledger.allSatisfy { interval in interval.entries.first { $0.app == "App 2" }?.cpuSeconds == 0.8 })
        XCTAssertTrue(read.ledger.allSatisfy(\.coversEnergy))
        XCTAssertTrue(read.ledger.allSatisfy { interval in interval.entries.first { $0.app == "App 1" }?.energyJoules == 4 },
                      "2 W over each two-second interval")
        XCTAssertEqual(read.markers.map(\.label), ["Marker", "Sleep"])
        XCTAssertEqual(read.markers.map(\.kind), [.note, .system], "a marker keeps its kind")

        let named = Recording.make(name: "Build", range: range, frames: frames, ledger: ledger, markers: markers, naming: .named)
        XCTAssertTrue(named.ledger.flatMap(\.entries).contains { $0.app == "Secret Project" })
    }

    func testUnreadableNewerAndInvalidFilesAreRefusedWithAReason() throws {
        XCTAssertThrowsError(try Recording.decode(Data("nope".utf8))) {
            XCTAssertEqual($0 as? Recording.Failure, .unreadable("not a Coreography recording"))
        }
        XCTAssertThrowsError(try Recording.decode(Data(#"{"schemaVersion":99}"#.utf8))) {
            XCTAssertEqual($0 as? Recording.Failure, .newerSchema(99))
        }
        let backwards = Recording.make(
            name: "x", range: epoch...epoch, frames: DashboardFrames(host: [], network: [], disks: [], gpu: [], power: [], sensors: []),
            ledger: AppLedger(capacity: 1), markers: [], naming: .named
        )
        let encoded = try XCTUnwrap(String(data: try Recording.encode(backwards), encoding: .utf8))
        let json = encoded.replacingOccurrences(of: "\"start\":\"2023-11-14T22:13:20Z\"", with: "\"start\":\"2024-11-14T22:13:20Z\"")
        XCTAssertNotEqual(json, encoded, "the fixture moved the start past the end")
        XCTAssertThrowsError(try Recording.decode(Data(json.utf8))) { XCTAssertEqual($0 as? Recording.Failure, .invalidRange) }
    }

    /// A recording saved before energy was kept decodes with no coverage and no joules.
    func testARecordingSavedBeforeEnergyStillDecodes() throws {
        let saved = #"{"start":"2023-11-14T22:13:20Z","end":"2023-11-14T22:13:22Z","cores":4,"coversNetwork":true,"entries":[{"app":"Safari","cpuSeconds":1,"diskBytes":0,"networkBytes":2,"isLowerBound":false}]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let interval = try decoder.decode(Recording.Interval.self, from: Data(saved.utf8))
        XCTAssertFalse(interval.coversEnergy)
        XCTAssertEqual(interval.entries.first?.energyJoules, 0)
    }

    @MainActor
    func testOpeningARecordingHoldsTheWindowOnItUntilReturningToLive() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10))
        model.start()
        defer { model.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.frames.count < 5, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let start = try XCTUnwrap(model.frames.first?.stamp.wallTime)
        let end = try XCTUnwrap(model.frames.last?.stamp.wallTime)
        model.selection = start...end
        model.addMarker(named: "Here", at: start.addingTimeInterval(1))
        model.exportNaming = .named
        let data = try await model.recordingData(name: "Saved")
        model.returnToNow()

        let opened = await model.openRecording(data, fileName: "Build log")
        XCTAssertNil(opened)
        XCTAssertEqual(model.openRecording?.name, "Build log", "the file's name, which the person chose, names it")
        XCTAssertEqual(model.displayMode, .held)
        XCTAssertEqual(model.frames.first?.stamp.wallTime, start)
        XCTAssertNil(model.selection, "a recording opens without a selection")
        XCTAssertTrue(model.timelineMarkers.contains { $0.label == "Here" })
        XCTAssertEqual(model.timelineMarkers.filter { $0.label == "Memory pressure warning" }.count, 1,
                       "system markers come again from the frames, not twice")
        XCTAssertNil(model.processSnapshot, "no live process detail mixed into a replay")

        // Markers made during a replay show on it.
        model.addMarker(named: "Seen in replay", at: start)
        model.selection = start...end
        model.annotateSelection(named: "Replayed build")
        XCTAssertTrue(model.timelineMarkers.contains { $0.label == "Seen in replay" })
        XCTAssertTrue(model.timelineMarkers.contains { $0.label == "End of Replayed build" })

        model.toggleDisplayHold()
        XCTAssertNil(model.openRecording)
        XCTAssertEqual(model.displayMode, .live)
        let refused = await model.openRecording(Data("x".utf8))
        XCTAssertEqual(refused, "The recording could not be read: not a Coreography recording")
        XCTAssertEqual(model.actionMessage, "The recording could not be read: not a Coreography recording")
    }

    /// The later of two opens wins, even when the earlier file takes longer to read.
    @MainActor
    func testTheLastRecordingOpenedIsTheOneShown() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10))
        let range = epoch...epoch.addingTimeInterval(10)
        let frames = DashboardFrames(host: [], network: [], disks: [], gpu: [], power: [], sensors: [])
        let many = (0..<60_000).map { TimelineMarker(time: epoch.addingTimeInterval(Double($0 % 10)), label: "m\($0)", kind: .note) }
        let slow = try Recording.encode(Recording.make(
            name: "Slow", range: range, frames: frames, ledger: AppLedger(capacity: 1), markers: many, naming: .named
        ))
        let quick = try Recording.encode(Recording.make(
            name: "Quick", range: range, frames: frames, ledger: AppLedger(capacity: 1), markers: [], naming: .named
        ))
        let first = Task { await model.openRecording(slow, fileName: "Slow") }
        let second = Task { await model.openRecording(quick, fileName: "Quick") }
        _ = await (first.value, second.value)
        XCTAssertEqual(model.openRecording?.name, "Quick")

        // Returning to live while a file is still being read keeps the window live.
        let late = Task { await model.openRecording(slow, fileName: "Late") }
        await Task.yield()
        model.toggleDisplayHold()
        if model.displayMode == .held { model.toggleDisplayHold() }
        _ = await late.value
        XCTAssertNil(model.openRecording?.name == "Late" ? model.openRecording : nil, "a dismissed open does not land")
    }

    /// A version 1 file has no stored section; it decodes exactly as saved.
    func testAVersion1RecordingStillDecodesWithoutAStoredPart() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try Self.processes(at: 0, epoch: epoch, [("Mail", 10)]), logicalCPUCount: 4)
        ledger.record(try Self.processes(at: 2, epoch: epoch, [("Mail", 10)]), logicalCPUCount: 4)
        let frames = DashboardFrames(host: [], network: [], disks: [], gpu: [], power: [], sensors: [])
        let document = Recording.make(
            name: "Build", range: epoch...epoch.addingTimeInterval(10), frames: frames, ledger: ledger,
            markers: [], naming: .named
        )
        let encoded = try XCTUnwrap(String(data: try Recording.encode(document), encoding: .utf8))
        let version1 = encoded.replacingOccurrences(of: "\"schemaVersion\":2", with: "\"schemaVersion\":1")
        XCTAssertNotEqual(version1, encoded, "the fixture pinned the version field")

        let read = try Recording.decode(Data(version1.utf8))
        XCTAssertEqual(read.schemaVersion, 1)
        XCTAssertNil(read.stored)
        XCTAssertEqual(read.ledger.count, 1)
        XCTAssertEqual(read.ledger.first?.entries.first?.app, "Mail")
    }

    /// The part of a range before the first live frame carries its stored
    /// values and ledger, the values keyed by the metric's on-disk code.
    func testARecordingSpanningStoredAndLiveHistoryCarriesTheStoredPart() async throws {
        let (document, storedStart) = try await Self.spanningDocument(naming: .named, at: epoch)
        let read = try Recording.decode(try Recording.encode(document))

        let section = try XCTUnwrap(read.stored)
        XCTAssertEqual(section.tier, .recent)
        let values = try XCTUnwrap(section.series[HistoryMetric.cpu.recordingKey], "CPU readings are kept")
        XCTAssertEqual(values.count, 10)
        XCTAssertTrue(values.allSatisfy { $0.value == 40 })
        // Every stored metric a lane, stack or band is drawn from is carried.
        for metric in [
            HistoryMetric.networkReceived, .networkSent, .memoryApp, .memoryWired,
            .memoryCompressed, .memoryCached, .memoryPressure, .thermalPressure
        ] {
            XCTAssertEqual(section.series[metric.recordingKey]?.count, 10, "\(metric) readings are kept")
        }
        XCTAssertEqual(section.ledger.first?.entries.map(\.app), ["Archive", "Shared"],
                       "the stored ledger keeps its attribution")
        XCTAssertEqual(read.ledger.count, 1, "the live part is unchanged")
        XCTAssertEqual(read.start, storedStart, "the recording starts where the selection did")
    }

    /// Stored and live apps share one placeholder ranking over the whole
    /// range, so an app keeps its number across the seam.
    func testRedactionRanksStoredAndLiveAppsInOneOrder() async throws {
        let (document, _) = try await Self.spanningDocument(naming: .redacted, at: epoch)
        let data = try Recording.encode(document)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("Archive"), "no stored app name leaves a redacted recording")
        XCTAssertFalse(json.contains("Shared"))

        let read = try Recording.decode(data)
        // Archive's 100 stored CPU-seconds outrank Shared's 2 stored + 4 live.
        XCTAssertEqual(read.stored?.ledger.first?.entries.map(\.app), ["App 1", "App 2"])
        XCTAssertEqual(read.ledger.first?.entries.map(\.app), ["App 2"],
                       "the same app keeps its placeholder across the seam")
    }

    /// A replayed recording can carry no live frames at all; a range inside
    /// its stored part still saves, and the save carries that stored part.
    @MainActor
    func testResavingARangeInsideAReplayedRecordingsStoredPart() async throws {
        let (document, storedStart) = try await Self.spanningDocument(naming: .named, at: epoch)
        let section = try XCTUnwrap(document.stored)
        let storedOnly = Recording.make(
            name: "Stored", range: document.start...document.end,
            frames: DashboardFrames(host: [], network: [], disks: [], gpu: [], power: [], sensors: []),
            ledger: AppLedger(capacity: 1),
            stored: StoredHistory.RawData(replaying: section, range: document.start...document.end),
            markers: [], naming: .named
        )
        let model = DashboardModel(monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10))
        let refused = await model.openRecording(try Recording.encode(storedOnly), fileName: "Stored")
        XCTAssertNil(refused)
        XCTAssertTrue(model.frames.isEmpty, "the replayed recording holds its stored part only")

        model.selection = storedStart...storedStart.addingTimeInterval(10)
        let resaved = try await model.recordingData(name: "Cut")
        let reread = try Recording.decode(resaved)
        XCTAssertEqual(reread.start, storedStart)
        XCTAssertEqual(reread.stored?.series[HistoryMetric.cpu.recordingKey]?.count, 10,
                       "the stored readings inside the saved range are carried")

        // With neither live frames nor stored history the range stays invalid.
        let bare = DashboardModel(monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10))
        bare.selection = storedStart...storedStart.addingTimeInterval(10)
        do {
            _ = try await bare.recordingData(name: "Cut")
            XCTFail("expected .invalidRange")
        } catch {
            XCTAssertEqual(error, .invalidRange)
        }
    }

    /// A stored load still in flight when a recording opens must not land
    /// over the recording's own stored part, whenever it settles.
    @MainActor
    func testOpeningARecordingDuringAStoredLoadKeepsTheRecordingsStoredPart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-race-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let now = Date()
        try await store.append((0..<600).map {
            HistorySample(metric: .cpu, time: now.addingTimeInterval(Double($0 - 600)), value: 50, availability: .measured)
        }, now: now)
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10),
            historyRecorder: HistoryRecorder(store: store)
        )
        model.timeRange = .sixHours
        let (document, _) = try await Self.spanningDocument(naming: .named, at: epoch)

        let refused = await model.openRecording(try Recording.encode(document), fileName: "Shift")
        XCTAssertNil(refused)
        // Give a load that outlived the open time to settle; it must not land.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.points(for: .cpu).contains { $0.value == 50 },
                       "the store's load did not land over the replay")
        XCTAssertTrue(model.points(for: .cpu).contains { $0.time < epoch && $0.value == 40 },
                      "the recording's stored part is what shows")
        XCTAssertNil(model.storedHistoryProblem)
    }

    /// A recording longer than the longest live-only range needs a window
    /// that covers it, or its stored part sits outside what the lanes show.
    @MainActor
    func testOpeningAMultiHourStoredRecordingPicksARangeThatShowsIt() async throws {
        let storedStart = epoch
        let end = storedStart.addingTimeInterval(2 * 3600)
        let buckets = (0..<6).map {
            StoredPoint(
                time: storedStart.addingTimeInterval(Double($0) * HistoryStore.dayBucket),
                minimum: 10, maximum: 90, mean: 50, count: 10
            )
        }
        let stored = StoredHistory.RawData(
            start: storedStart, end: end, tier: .day, series: [.cpu: buckets], ledger: []
        )
        let document = Recording.make(
            name: "Long", range: storedStart...end,
            frames: DashboardFrames(host: [try Self.hostFrame(at: end)], network: [], disks: [], gpu: [], power: [], sensors: []),
            ledger: AppLedger(capacity: 1), stored: stored, markers: [], naming: .named
        )
        let model = DashboardModel(monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10))

        let refused = await model.openRecording(try Recording.encode(document), fileName: "Long")
        XCTAssertNil(refused)
        XCTAssertEqual(model.timeRange, .sixHours, "the smallest range covering the recording")
        XCTAssertLessThanOrEqual(try XCTUnwrap(model.visibleWindow).lowerBound, storedStart,
                                 "the stored part is inside the shown window")
        XCTAssertTrue(model.points(for: .cpu).contains { $0.time < end.addingTimeInterval(-3600) },
                      "the stored part draws right after opening")
    }

    /// A document the encoder cannot write reports .uncodable, not a read error.
    func testAnEncodingFailureIsReportedAsUncodable() throws {
        let document = Recording.Document(
            schemaVersion: 2, name: "x", savedAt: epoch, start: epoch, end: epoch, appNames: .named,
            host: [], network: [], disks: [], gpu: [], power: [], sensors: [],
            ledger: [Recording.Interval(
                start: epoch, end: epoch, cores: 4, coversNetwork: false,
                entries: [Recording.Entry(app: "A", cpuSeconds: .infinity, diskBytes: 0, networkBytes: 0, isLowerBound: false)]
            )],
            markers: [], stored: nil
        )
        XCTAssertThrowsError(try Recording.encode(document)) {
            guard case .uncodable(let detail) = $0 as? Recording.Failure else {
                return XCTFail("expected .uncodable, got \($0)")
            }
            XCTAssertEqual(
                Recording.Failure.uncodable(detail).message,
                "The recording could not be written: \(detail)"
            )
        }
    }

    /// A saved stored part opens back as stored history: lanes draw it and
    /// a range report over the earlier part reads it, until returning live.
    @MainActor
    func testOpeningARecordingWithAStoredPartReplaysIt() async throws {
        let (document, storedStart) = try await Self.spanningDocument(naming: .named, at: epoch)
        let data = try Recording.encode(document)
        let model = DashboardModel(monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10))

        let refused = await model.openRecording(data, fileName: "Shift")
        XCTAssertNil(refused)
        XCTAssertTrue(model.points(for: .cpu).contains { $0.time < epoch }, "the stored part draws behind live data")
        XCTAssertTrue(model.points(for: .networkReceived).contains { $0.time < epoch },
                      "a stored network line replays")
        XCTAssertTrue(model.memoryStack().contains { $0.time < epoch }, "the stored memory stack replays")
        XCTAssertTrue(model.memoryPressureSpans().contains { $0.start < epoch },
                      "a stored pressure band replays")

        model.selection = storedStart...storedStart.addingTimeInterval(10)
        let report = try XCTUnwrap(model.rangeReport)
        XCTAssertEqual(report.cpuMeanPercent ?? 0, 40, accuracy: 1e-9, "ten stored readings of 40%")
        XCTAssertEqual(report.topCPUApps.first?.name, "Archive")

        model.toggleDisplayHold()
        XCTAssertNil(model.openRecording)
        XCTAssertNil(model.rangeReport?.cpuMeanPercent, "returning to live discards the replayed stored part")
    }

    /// A stored part saved from the Day tier keeps each bucket's minimum
    /// and maximum, so the replayed line draws both extremes where the
    /// window drew them: the minimum at the bucket's start, the maximum
    /// mid-bucket.
    func testADayTierStoredPartReplaysBucketExtremes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-rec-day-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        // One bucket holding a 10% floor and a 90% spike; bucket times
        // align to the Day tier's bucket width.
        let bucketStart = Date(timeIntervalSince1970:
            (epoch.timeIntervalSince1970 / HistoryStore.dayBucket).rounded(.down) * HistoryStore.dayBucket)
        let samples = [
            HistorySample(metric: .cpu, time: bucketStart.addingTimeInterval(1), value: 10, availability: .measured),
            HistorySample(metric: .cpu, time: bucketStart.addingTimeInterval(6), value: 90, availability: .measured)
        ]
        let end = bucketStart.addingTimeInterval(100)
        try await store.append(samples, now: end)
        let stored = try await StoredHistory.rawData(
            from: HistoryRecorder(store: store), tier: .day, start: bucketStart, end: end
        )
        let document = Recording.make(
            name: "Day", range: bucketStart...end,
            frames: DashboardFrames(host: [], network: [], disks: [], gpu: [], power: [], sensors: []),
            ledger: AppLedger(capacity: 1), stored: stored, markers: [], naming: .named
        )

        let read = try Recording.decode(try Recording.encode(document))
        let section = try XCTUnwrap(read.stored)
        XCTAssertEqual(section.tier, .day)
        let history = StoredHistory(replaying: section, range: read.start...read.end)
        let cpu = try XCTUnwrap(history.lines[.cpu])
        XCTAssertTrue(cpu.contains { $0.time == bucketStart && $0.value == 10 },
                      "a bucket's minimum draws at its start")
        XCTAssertTrue(
            cpu.contains { $0.time == bucketStart.addingTimeInterval(HistoryStore.dayBucket / 2) && $0.value == 90 },
            "a bucket's maximum draws mid-bucket"
        )
        let report = try XCTUnwrap(history.values(.cpu, in: read.start...read.end, before: .distantFuture).first)
        XCTAssertEqual(report.mean, 50, accuracy: 1e-9)
        XCTAssertEqual(report.maximum, 90)
        XCTAssertEqual(report.count, 2)
    }

    // MARK: Fixtures

    /// A recording whose range begins 100 s before the first live frame at
    /// epoch: ten stored readings for CPU, both network rates, the memory
    /// stack layers and both pressure bands, and a stored ledger interval
    /// behind two live host frames and the one ledger interval the two
    /// recorded samples make (the first sample opens no interval).
    /// Host frames hold machine readings only — a recording keeps no process
    /// list — so nothing in them names an app for redaction to cover.
    private static func spanningDocument(
        naming: ExportNaming, at epoch: Date
    ) async throws -> (document: Recording.Document, storedStart: Date) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-rec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let storedStart = epoch.addingTimeInterval(-100)
        var samples: [HistorySample] = []
        for second in 0..<10 {
            let time = storedStart.addingTimeInterval(Double(second))
            func sample(_ metric: HistoryMetric, _ value: Double) {
                samples.append(HistorySample(metric: metric, time: time, value: value, availability: .measured))
            }
            sample(.cpu, 40)
            sample(.networkReceived, 1000)
            sample(.networkSent, 500)
            sample(.memoryApp, 1)
            sample(.memoryWired, 2)
            sample(.memoryCompressed, 3)
            sample(.memoryCached, 4)
            // The bands rise halfway through the stored part.
            sample(.memoryPressure, second < 5 ? 0 : 1)
            sample(.thermalPressure, second < 5 ? 0 : 1)
        }
        let storedInterval = LedgerInterval(
            start: storedStart, end: storedStart.addingTimeInterval(2), cores: 4,
            entries: [
                LedgerEntry(app: "Archive", cpuSeconds: 100, diskBytes: 0, isLowerBound: false),
                LedgerEntry(app: "Shared", cpuSeconds: 2, diskBytes: 0, isLowerBound: false)
            ]
        )
        try await store.append(samples, ledger: [storedInterval], now: epoch)
        let stored = try await StoredHistory.rawData(
            from: HistoryRecorder(store: store), tier: .recent,
            start: storedStart, end: epoch.addingTimeInterval(4)
        )

        let monitor = try SystemMonitor(driver: Host())
        var frames: [CapturedSnapshot] = []
        for _ in 0..<2 { frames.append(try await monitor.sample()) }
        var ledger = AppLedger(capacity: 10)
        ledger.record(try Self.processes(at: 0, epoch: epoch, [("Shared", 50)]), logicalCPUCount: 4)
        ledger.record(try Self.processes(at: 2, epoch: epoch, [("Shared", 50)]), logicalCPUCount: 4)

        let document = Recording.make(
            name: "Shift", range: storedStart...epoch.addingTimeInterval(4),
            frames: DashboardFrames(host: frames, network: [], disks: [], gpu: [], power: [], sensors: []),
            ledger: ledger, stored: stored, markers: [], naming: naming
        )
        return (document, storedStart)
    }

    /// One deterministic host frame; machine readings only, no process names.
    private static func hostFrame(at time: Date) throws -> CapturedSnapshot {
        try CapturedSnapshot(
            stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: time),
            inventory: HostInventory(
                operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30
            ),
            cpuPercentOfMachine: .measured(50), memoryUsedBytes: .measured(1),
            memory: MemoryDetail(
                appBytes: .measured(1), wiredBytes: .measured(1), compressedBytes: .measured(1),
                cachedBytes: .measured(1), compressionRatio: .measured(1), swapUsedBytes: .measured(0),
                swapTotalBytes: .measured(1), pageInBytesPerSecond: .measured(0),
                swapInBytesPerSecond: .measured(0), swapOutBytesPerSecond: .measured(0),
                pressure: .measured(0)
            ),
            thermalPressure: .measured(0), continuity: .continuous
        )
    }

    private static func processes(
        at second: TimeInterval, epoch: Date, _ rows: [(String, Double)]
    ) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: UInt64(1 + second * 1e9), wallTime: epoch.addingTimeInterval(second))
        let readings = try rows.enumerated().map { offset, row in
            ProcessReading(
                id: try ProcessIdentity(pid: Int32(100 + offset), startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501,
                name: row.0, stamp: stamp, cpuPercentOfMachine: try .measured(row.1), memoryFootprintBytes: try .measured(1),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                cpuPowerWatts: try .estimated(2, method: "Energy model"),
                executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(readings.count)), enumerationTruncated: false,
            processes: readings, issues: [], continuity: .continuous
        )
    }
}

private actor Host: HostSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawHostSnapshot {
        reads += 1
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30),
            cpu: .success(ProcessorTicks(user: reads, system: 0, idle: reads * 3, nice: 0)),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0, wired: 2, compressed: 3, compressorContents: 6, purgeable: 0,
                fileBacked: 1, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 8192, usedBytes: 0)),
            // Pressure rises once, so the recording holds one system marker.
            memoryPressure: .success(reads >= 3 ? .warning : .normal), thermalPressure: .success(.nominal)
        )
    }
}
