import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class SessionsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testReportUsesEveryRawReadingAndSkipsGaps() throws {
        var recording = SessionRecording(name: "Render", start: epoch)
        // CPU 1…20 % over 20 s, one unreadable second, and memory once.
        for second in 1...20 {
            recording.record([HistorySample(metric: .cpu, time: epoch.addingTimeInterval(Double(second)), value: Double(second), availability: .measured)])
        }
        recording.record([
            HistorySample(metric: .cpu, time: epoch.addingTimeInterval(21), value: nil, availability: .gap),
            HistorySample(metric: .memoryUsed, time: epoch.addingTimeInterval(21), value: 4096, availability: .estimated)
        ])
        recording.record(LedgerInterval(
            start: epoch, end: epoch.addingTimeInterval(2), cores: 4,
            entries: [LedgerEntry(app: "Blender", cpuSeconds: 6, diskBytes: 0, isLowerBound: false)]
        ))
        let session = recording.finish(at: epoch.addingTimeInterval(22))

        let cpu = try XCTUnwrap(session.summaries.first { $0.metric == "cpu" })
        XCTAssertEqual(cpu.samples, 20, "the gap is not a reading")
        XCTAssertEqual(cpu.minimum, 1)
        XCTAssertEqual(cpu.maximum, 20)
        XCTAssertEqual(cpu.mean, 10.5)
        XCTAssertEqual(cpu.percentile95, 19, "nearest rank of twenty readings")
        XCTAssertEqual(session.summaries.map(\.metric), ["cpu", "memoryUsed"], "metrics without readings are left out")
        XCTAssertEqual(session.topApps.map(\.name), ["Blender"])
        XCTAssertEqual(session.series["cpu"]?.first?.offset, 1)
    }

    /// Slower sources keep their newest frame between updates; a repeat is not a new reading.
    func testARepeatedFrameIsOneReading() throws {
        var recording = SessionRecording(name: "Idle", start: epoch)
        let reading = HistorySample(metric: .hottestCelsius, time: epoch.addingTimeInterval(4), value: 50, availability: .measured)
        recording.record([reading])
        recording.record([reading])
        recording.record([HistorySample(metric: .hottestCelsius, time: epoch.addingTimeInterval(8), value: 52, availability: .measured)])
        let summary = try XCTUnwrap(recording.finish(at: epoch.addingTimeInterval(9)).summaries.first)
        XCTAssertEqual(summary.samples, 2)
        XCTAssertEqual(summary.mean, 51)
    }

    func testSessionsWithOneNameStayTwoLines() {
        var first = SessionRecording(name: "Baseline", start: epoch)
        var second = SessionRecording(name: "Baseline", start: epoch.addingTimeInterval(86_400))
        for recording in [0, 1] {
            let sample = HistorySample(metric: .cpu, time: epoch.addingTimeInterval(Double(recording * 86_400 + 1)), value: 5, availability: .measured)
            if recording == 0 { first.record([sample]) } else { second.record([sample]) }
        }
        let comparison = SessionComparison.make(first.finish(at: epoch.addingTimeInterval(2)), second.finish(at: epoch.addingTimeInterval(86_402)))
        let labels = comparison.metrics.first?.series.map(\.label) ?? []
        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(Set(labels).count, 2, "a chart keys lines by label")
    }

    func testArchiveKeepsSessionsPrivateNewestFirst() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-sessions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = SessionArchive(store: try SessionStore(directory: directory))
        let older = SessionRecording(name: "Older", start: epoch).finish(at: epoch.addingTimeInterval(1))
        let newer = SessionRecording(name: "Newer", start: epoch.addingTimeInterval(100)).finish(at: epoch.addingTimeInterval(101))
        try await archive.save(older)
        try await archive.save(newer)

        let names = await archive.all().map(\.name)
        XCTAssertEqual(names, ["Newer", "Older"])
        let file = directory.appendingPathComponent(newer.id.uuidString).appendingPathExtension("json")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(folder?.intValue, 0o700)

        try await archive.delete(older.id)
        let remaining = await archive.all().map(\.name)
        XCTAssertEqual(remaining, ["Newer"])
    }

    func testComparisonAlignsSharedMetricsAndExportsRedactApps() throws {
        var first = SessionRecording(name: "Before", start: epoch)
        var second = SessionRecording(name: "After", start: epoch.addingTimeInterval(3600))
        first.record([HistorySample(metric: .cpu, time: epoch.addingTimeInterval(1), value: 80, availability: .measured)])
        first.record([HistorySample(metric: .gpuBusy, time: epoch.addingTimeInterval(1), value: 50, availability: .measured)])
        second.record([HistorySample(metric: .cpu, time: epoch.addingTimeInterval(3601), value: 40, availability: .measured)])
        second.record(LedgerInterval(
            start: epoch.addingTimeInterval(3600), end: epoch.addingTimeInterval(3602), cores: 4,
            entries: [LedgerEntry(app: "Secret Tool", cpuSeconds: 1, diskBytes: 0, isLowerBound: false)]
        ))
        let before = first.finish(at: epoch.addingTimeInterval(2))
        let after = second.finish(at: epoch.addingTimeInterval(3602))

        let comparison = SessionComparison.make(before, after)
        XCTAssertEqual(comparison.metrics.map(\.metric), ["cpu"], "only metrics both sessions recorded")
        XCTAssertEqual(comparison.metrics.first?.series.map(\.name), ["Before", "After"])
        XCTAssertEqual(comparison.metrics.first?.series.map { $0.points.first?.offset }, [1, 1], "aligned at each start")

        let redacted = String(decoding: try SessionExport.json(after, naming: .redacted), as: UTF8.self)
        XCTAssertFalse(redacted.contains("Secret Tool"))
        XCTAssertTrue(redacted.contains("App 1"))
        let named = String(decoding: try SessionExport.json(after, naming: .named), as: UTF8.self)
        XCTAssertTrue(named.contains("Secret Tool"))
        XCTAssertEqual(SessionExport.csv(after).split(separator: "\n"), ["offset_seconds,metric,value", "1.0,cpu,40.0"])
    }

    @MainActor
    func testRecordingThroughTheModelSavesAReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-model-sessions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Busy()), interval: .milliseconds(10),
            sessionArchive: SessionArchive(store: try SessionStore(directory: directory))
        )
        model.start()
        defer { model.stop() }
        model.startRecording(name: "  Export render  ")
        XCTAssertEqual(model.recordingName, "Export render")
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (model.frames.count < 5), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }

        let problem = await model.stopRecording()
        XCTAssertNil(problem)
        XCTAssertNil(model.recordingName)
        let session = try XCTUnwrap(model.sessions.first)
        XCTAssertEqual(session.name, "Export render")
        XCTAssertGreaterThan(session.summaries.first { $0.metric == "cpu" }?.samples ?? 0, 0)

        await model.renameSession(session.id, to: "Final render")
        await model.refreshSessions()
        XCTAssertEqual(model.sessions.first?.name, "Final render", "the new name is saved")

        model.toggleComparison(session.id)
        XCTAssertNil(model.sessionComparison, "a comparison needs two sessions")

        // A delete the disk refuses keeps the row, its comparison pick, and says why.
        try XCTSkipIf(getuid() == 0, "root writes through the permission this relies on")
        let pickedBefore = model.comparedSessions
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        await model.deleteSession(session.id)
        XCTAssertEqual(model.sessions.map(\.id), [session.id])
        XCTAssertTrue(model.actionMessage?.hasPrefix("The session could not be deleted") == true, "\(model.actionMessage ?? "nil")")
        XCTAssertEqual(model.comparedSessions, pickedBefore, "a session still on disk stays picked")
    }
}

/// A quarter of every tick busy, one sample per call.
private actor Busy: HostSampleReading {
    private let clock = UUID()
    private var step: UInt64 = 0

    func read() async -> RawHostSnapshot {
        step += 1
        let inventory = HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30)
        let pages = MemoryPages(
            active: 10, inactive: 0, speculative: 0, wired: 2, compressed: 3, compressorContents: 6, purgeable: 0,
            fileBacked: 1, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
        )
        let monotonic: UInt64 = step * 1_000_000_000
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: monotonic, wallTime: Date(),
            inventory: inventory, cpu: .success(ProcessorTicks(user: step, system: 0, idle: step * 3, nice: 0)),
            memory: .success(pages), swap: .success(SwapUsage(totalBytes: 0, usedBytes: 0)),
            memoryPressure: .success(.normal), thermalPressure: .success(.nominal)
        )
    }
}
