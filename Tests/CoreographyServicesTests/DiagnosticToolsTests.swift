import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class DiagnosticToolsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testSummaryReportsFactsWithUnitsAndEvidence() async throws {
        let snapshot = try await makeSnapshot(seconds: 10, busyShare: 0.9, pressure: .warning, swapping: true)
        let summary = DiagnosticTools.summary(snapshot)

        XCTAssertEqual(summary.snapshotID, snapshot.id)
        XCTAssertEqual(summary.cpuPercentOfMachine?.unit, "%")
        XCTAssertEqual(summary.cpuPeakPercent ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(summary.memoryPressure, "warning")
        XCTAssertTrue(summary.memoryUsedBytes?.evidence.hasPrefix("frame:") ?? false)
        XCTAssertEqual(Set(summary.signals.map(\.kind)), [.cpuSaturated, .memoryPressureElevated, .swapping])
        XCTAssertNil(summary.gpuBusyPercent, "no GPU frames, no invented value")

        let calm = try await makeSnapshot(seconds: 10, busyShare: 0.1, pressure: .normal, swapping: false)
        XCTAssertTrue(DiagnosticTools.summary(calm).signals.isEmpty)
    }

    func testTopAppsPagesWithCursorsBoundToTheQuery() async throws {
        let snapshot = try await makeSnapshot(seconds: 10, busyShare: 0.5, pressure: .normal, swapping: false,
                                              apps: [("A", 30), ("B", 20), ("C", 10)])
        let first = try DiagnosticTools.topApps(snapshot, metric: .cpu, limit: 2)
        XCTAssertEqual(first.rows.map(\.app), ["A", "B"])
        XCTAssertEqual(first.rows.first?.unit, "CPU-seconds")
        XCTAssertEqual(first.remaining, 1)
        let cursor = try XCTUnwrap(first.nextCursor)

        let second = try DiagnosticTools.topApps(snapshot, metric: .cpu, limit: 2, cursor: cursor)
        XCTAssertEqual(second.rows.map(\.app), ["C"])
        XCTAssertNil(second.nextCursor)

        // A cursor only continues the query, snapshot and range it came from.
        XCTAssertThrowsError(try DiagnosticTools.topApps(snapshot, metric: .disk, limit: 2, cursor: cursor)) {
            XCTAssertEqual($0 as? DiagnosticError, .invalidCursor)
        }
        let other = try await makeSnapshot(seconds: 10, busyShare: 0.5, pressure: .normal, swapping: false)
        XCTAssertThrowsError(try DiagnosticTools.topApps(other, metric: .cpu, limit: 2, cursor: cursor))
        XCTAssertThrowsError(try DiagnosticTools.topApps(snapshot, metric: .cpu, limit: 0))
        XCTAssertThrowsError(try DiagnosticTools.topApps(
            snapshot, metric: .cpu, range: epoch...epoch.addingTimeInterval(7200)
        )) { XCTAssertEqual($0 as? DiagnosticError, .rangeTooLarge(maximumSeconds: 3600)) }
    }

    func testHistoryIsBoundedAndKeepsGaps() async throws {
        let snapshot = try await makeSnapshot(seconds: 10, busyShare: 0.5, pressure: .normal, swapping: false, gapAt: 5)
        let history = try DiagnosticTools.history(snapshot, metric: .cpu, range: epoch...epoch.addingTimeInterval(120))
        XCTAssertEqual(history.unit, "% of machine")
        XCTAssertGreaterThan(Set(history.points.map(\.segment)).count, 1, "the gap separates segments")
        XCTAssertFalse(history.decimated)
        XCTAssertThrowsError(try DiagnosticTools.history(snapshot, metric: .cpu, maximumPoints: 601))
        XCTAssertTrue(try DiagnosticTools.history(snapshot, metric: .gpuBusy).points.isEmpty)
    }

    func testProcessDetailsOmitPathsAndSleepHistoryWaitsForItsImport() async throws {
        let snapshot = try await makeSnapshot(seconds: 4, busyShare: 0.5, pressure: .normal, swapping: false,
                                              apps: [("Worker", 5)])
        let details = try XCTUnwrap(DiagnosticTools.processDetails(snapshot, pid: 100))
        XCTAssertEqual(details.app, "Worker")
        XCTAssertNil(DiagnosticTools.processDetails(snapshot, pid: 4242))
        let encoded = String(decoding: try JSONEncoder().encode(details), as: UTF8.self)
        XCTAssertFalse(encoded.contains("/Applications"), "paths stay out of diagnostic results")
        XCTAssertThrowsError(try DiagnosticTools.sleepHistory(snapshot)) {
            guard case .unavailable = $0 as? DiagnosticError else { return XCTFail("expected unavailable") }
        }
        XCTAssertTrue(DiagnosticTools.dataSources(snapshot).contains { $0.metric == "cpu" && $0.availability == .measured })
    }

    func testSleepHistoryIsWindowedCappedAndCarriesCoverage() throws {
        // One sleep per hour for 300 hours, each followed by a wake; the snapshot is taken at the end.
        let events = (0..<300).flatMap { hour -> [PowerEvent] in
            let start = epoch.addingTimeInterval(Double(hour) * 3600)
            return [
                PowerEvent(time: start, kind: .sleep, reason: "Idle Sleep", powerSource: .battery, batteryPercent: 90),
                PowerEvent(time: start.addingTimeInterval(1800), kind: .wake, reason: "UserActivity", powerSource: .battery, batteryPercent: 88)
            ]
        }
        let history = SleepHistory(
            importedAt: epoch, coveredFrom: events.first?.time, coveredTo: events.last?.time,
            coverage: .partial("older records exceeded the import cap"), events: events,
            periods: SleepHistoryProvider.periods(events)
        )
        let takenAt = epoch.addingTimeInterval(300 * 3600)
        let snapshot = DiagnosticSnapshot(
            takenAt: takenAt, host: [], network: [], gpu: [], power: [], sensors: [], processes: nil,
            ledger: AppLedger(capacity: 1), sleep: .imported(history)
        )

        let day = try DiagnosticTools.sleepHistory(snapshot)
        XCTAssertEqual(day.windowStart, takenAt.addingTimeInterval(-24 * 3600))
        XCTAssertEqual(day.events.count, 48)
        XCTAssertEqual(day.periods.count, 24)
        XCTAssertEqual(day.periods.first?.batteryChangePercent, -2)
        XCTAssertEqual(day.partialCoverage, "older records exceeded the import cap")
        XCTAssertEqual(day.omittedEvents, 0)

        let week = try DiagnosticTools.sleepHistory(snapshot, hours: DiagnosticTools.maximumSleepHours)
        XCTAssertEqual(week.events.count, DiagnosticTools.maximumSleepEvents)
        XCTAssertEqual(week.omittedEvents, 2 * 168 - DiagnosticTools.maximumSleepEvents)
        XCTAssertEqual(week.events.last?.time, events.last?.time, "the newest records are kept")
        XCTAssertThrowsError(try DiagnosticTools.sleepHistory(snapshot, hours: 0))

        let failed = DiagnosticSnapshot(
            takenAt: takenAt, host: [], network: [], gpu: [], power: [], sensors: [], processes: nil,
            ledger: AppLedger(capacity: 1), sleep: .failed("pmset could not start")
        )
        XCTAssertThrowsError(try DiagnosticTools.sleepHistory(failed)) {
            XCTAssertEqual($0 as? DiagnosticError, .unavailable("Sleep history is unavailable: pmset could not start"))
        }
    }

    // MARK: Fixtures

    private func makeSnapshot(
        seconds: Int, busyShare: Double, pressure: KernelMemoryPressure, swapping: Bool,
        apps: [(String, Double)] = [], gapAt: Int? = nil
    ) async throws -> DiagnosticSnapshot {
        let monitor = try SystemMonitor(driver: ScriptedHostDriver(
            epoch: epoch, busyShare: busyShare, pressure: pressure, swapping: swapping, gapAt: gapAt
        ))
        var ledger = AppLedger(capacity: 100)
        for second in 0...seconds {
            _ = try await monitor.sample()
            ledger.record(try processes(at: second, apps: apps), logicalCPUCount: 4)
        }
        let host = await monitor.history()
        return DiagnosticSnapshot(
            takenAt: host.last?.stamp.wallTime ?? epoch, host: host, network: [], gpu: [], power: [],
            sensors: [], processes: try processes(at: seconds, apps: apps), ledger: ledger
        )
    }

    private func processes(at second: Int, apps: [(String, Double)]) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: epoch.addingTimeInterval(Double(second)))
        let rows = try apps.enumerated().map { offset, app in
            ProcessReading(
                id: try ProcessIdentity(pid: Int32(100 + offset), startSeconds: 1, startMicroseconds: 0),
                parentPID: 1, uid: 501, name: app.0, stamp: stamp, cpuPercentOfMachine: try .measured(app.1),
                memoryFootprintBytes: try .measured(1), diskReadBytesPerSecond: try .measured(0),
                diskWriteBytesPerSecond: try .measured(0),
                executablePath: "/Applications/\(app.0).app/Contents/MacOS/\(app.0)", responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(rows.count)), enumerationTruncated: false,
            processes: rows, issues: [], continuity: .continuous
        )
    }
}

private actor ScriptedHostDriver: HostSampleReading {
    private let clock = UUID()
    private let epoch: Date
    private let busyShare: Double
    private let pressure: KernelMemoryPressure
    private let swapping: Bool
    private let gapAt: Int?
    private var step: UInt64 = 0

    init(epoch: Date, busyShare: Double, pressure: KernelMemoryPressure, swapping: Bool, gapAt: Int?) {
        self.epoch = epoch
        self.busyShare = busyShare
        self.pressure = pressure
        self.swapping = swapping
        self.gapAt = gapAt
    }

    func read() async -> RawHostSnapshot {
        defer { step += 1 }
        let busy = UInt64(busyShare * 100) * step
        let skipped = gapAt.map { step >= UInt64($0) } ?? false
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: step * 1_000_000_000,
            wallTime: epoch.addingTimeInterval(Double(step) + (skipped ? 30 : 0)),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30),
            cpu: .success(ProcessorTicks(user: busy, system: 0, idle: 100 * step - busy, nice: 0)),
            memory: .success(MemoryPages(
                active: 100, inactive: 0, speculative: 0, wired: 10, compressed: 5, compressorContents: 10,
                purgeable: 0, fileBacked: 0, pageIns: 0, swapIns: 0, swapOuts: swapping ? step : 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 1 << 20, usedBytes: swapping ? 1 << 19 : 0)),
            memoryPressure: .success(pressure), thermalPressure: .success(.nominal)
        )
    }
}
