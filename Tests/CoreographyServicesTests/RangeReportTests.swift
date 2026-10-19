import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class RangeReportTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testLedgerIntegratesRatesOverRealIntervalsAndKeepsTailApps() throws {
        var ledger = AppLedger(capacity: 10)
        // Baseline sample opens the first interval; no totals yet.
        ledger.record(try snapshot(at: 0, rows: [("Big", 50, 0), ("Tail", 0.5, 0)]), logicalCPUCount: 4)
        XCTAssertTrue(ledger.intervals.isEmpty)
        ledger.record(try snapshot(at: 2, rows: [("Big", 50, 1000), ("Tail", 0.5, 0), ("Idle", 0, 0)]), logicalCPUCount: 4)

        let (apps, covered) = ledger.totals(in: epoch...epoch.addingTimeInterval(10))
        // 50% of a 4-core machine for 2 s = 4 CPU-seconds; 1 kB/s for 2 s = 2 kB.
        let big = try XCTUnwrap(apps.first { $0.name == "Big" })
        XCTAssertEqual(big.cpuSeconds, 4, accuracy: 1e-9)
        XCTAssertEqual(big.diskBytes, 2000, accuracy: 1e-9)
        XCTAssertEqual(apps.first { $0.name == "Tail" }?.cpuSeconds ?? 0, 0.04, accuracy: 1e-9)
        XCTAssertNil(apps.first { $0.name == "Idle" }, "idle apps are not recorded")
        XCTAssertEqual(covered, epoch...epoch.addingTimeInterval(2))
    }

    func testInterruptedSamplesAndOutOfRangeIntervalsAreExcluded() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("App", 10, 0)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 2, rows: [("App", 10, 0)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 3600, rows: [("App", 90, 0)], continuity: .interrupted), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 3602, rows: [("App", 20, 0)]), logicalCPUCount: 1)
        XCTAssertEqual(ledger.intervals.count, 2)

        // Only the interval whose midpoint lies in the range counts.
        let early = ledger.totals(in: epoch...epoch.addingTimeInterval(1.5))
        XCTAssertEqual(early.apps.first?.cpuSeconds ?? 0, 0.2, accuracy: 1e-9)
        let none = ledger.totals(in: epoch.addingTimeInterval(100)...epoch.addingTimeInterval(200))
        XCTAssertTrue(none.apps.isEmpty)
        XCTAssertNil(none.covered)
    }

    func testUnreadableMembersMarkTotalsAsLowerBounds() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("App", 10, nil)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 2, rows: [("App", 10, nil)]), logicalCPUCount: 1)
        let app = try XCTUnwrap(ledger.totals(in: epoch...epoch.addingTimeInterval(5)).apps.first)
        XCTAssertTrue(app.isLowerBound)
    }

    func testUnknownCoreCountRecordsALowerBoundInsteadOfZeroCPU() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("App", 10, 0)]), logicalCPUCount: nil)
        ledger.record(try snapshot(at: 2, rows: [("App", 10, 0)]), logicalCPUCount: nil)
        let app = try XCTUnwrap(ledger.totals(in: epoch...epoch.addingTimeInterval(5)).apps.first)
        XCTAssertEqual(app.cpuSeconds, 0)
        XCTAssertTrue(app.isLowerBound)
    }

    func testStoredHistoryAnswersOnlyForTimeBeforeLiveData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-range-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        func stored(_ start: TimeInterval, _ cpu: Double) -> LedgerInterval {
            LedgerInterval(
                start: epoch.addingTimeInterval(start), end: epoch.addingTimeInterval(start + 2), cores: 2,
                entries: [LedgerEntry(app: "A", cpuSeconds: cpu, diskBytes: 0, isLowerBound: false)]
            )
        }
        // The recorder also stored the interval the live ledger still holds ([4, 6]).
        let samples = [10.0, 20, 30, 40].enumerated().map {
            HistorySample(metric: .cpu, time: epoch.addingTimeInterval(Double($0.offset)), value: $0.element, availability: .measured)
        } + [HistorySample(metric: .hottestCelsius, time: epoch.addingTimeInterval(1), value: 90, availability: .measured)]
        try await store.append(samples, ledger: [stored(0, 1), stored(2, 1), stored(4, 1)], now: epoch.addingTimeInterval(10))
        let history = try await StoredHistory.load(
            from: HistoryRecorder(store: store), start: epoch, end: epoch.addingTimeInterval(10)
        )

        var live = AppLedger(capacity: 10)
        live.record(try snapshot(at: 4, rows: [("A", 50, 0)]), logicalCPUCount: 2)
        live.record(try snapshot(at: 6, rows: [("A", 50, 0)]), logicalCPUCount: 2)
        let report = RangeReport.make(
            range: epoch...epoch.addingTimeInterval(10), ledger: live, frames: [], gpuFrames: [], sensorFrames: [],
            stored: history
        )

        // Stored [0, 2] and [2, 4], then live [4, 6] (half of two cores for 2 s), never [4, 6] twice.
        XCTAssertEqual(report.topCPUApps.first?.cpuSeconds ?? 0, 1 + 1 + 2, accuracy: 1e-9)
        XCTAssertEqual(report.covered, epoch...epoch.addingTimeInterval(6))
        XCTAssertEqual(report.cpuMeanPercent ?? 0, 25, accuracy: 1e-9, "the true mean of stored readings")
        XCTAssertEqual(report.cpuPeakPercent, 40)
        XCTAssertEqual(report.hottest?.celsius, 90)
        XCTAssertNil(report.hottest?.key, "stored history keeps no sensor key")

        XCTAssertEqual(history.values(.cpu, in: epoch...epoch.addingTimeInterval(10), before: epoch.addingTimeInterval(2)).map(\.mean), [10, 20])
    }

    func testStoredValuesStopWhereEachLiveSeriesStarts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-cutoff-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        // Stored CPU is 10% before live data starts at +5 s and an impossible 999% after it.
        let samples = (0..<10).map { second in
            HistorySample(metric: .cpu, time: epoch.addingTimeInterval(Double(second)), value: second < 5 ? 10 : 999, availability: .measured)
        }
        try await store.append(samples, now: epoch.addingTimeInterval(10))
        let history = try await StoredHistory.load(from: HistoryRecorder(store: store), start: epoch, end: epoch.addingTimeInterval(10))

        let monitor = try SystemMonitor(driver: QuarterBusyHost(start: epoch.addingTimeInterval(5)))
        var frames: [CapturedSnapshot] = []
        for _ in 0..<4 { frames.append(try await monitor.sample()) }
        let report = RangeReport.make(
            range: epoch...epoch.addingTimeInterval(10), ledger: AppLedger(capacity: 1), frames: frames,
            gpuFrames: [], sensorFrames: [], stored: history
        )
        XCTAssertEqual(report.cpuPeakPercent ?? 0, 25, accuracy: 1e-9, "stored readings after the live start are not counted")
        // Five stored readings of 10% and three live ones of 25% (the first live sample has no baseline).
        let expectedMean = (5.0 * 10 + 3 * 25) / 8
        XCTAssertEqual(report.cpuMeanPercent ?? 0, expectedMean, accuracy: 1e-9)
    }

    func testReportRanksAppsAndSummarisesLanes() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("A", 10, 5), ("B", 30, 1)]), logicalCPUCount: 2)
        ledger.record(try snapshot(at: 2, rows: [("A", 10, 5), ("B", 30, 1)]), logicalCPUCount: 2)
        let report = RangeReport.make(
            range: epoch...epoch.addingTimeInterval(5), ledger: ledger, frames: [], gpuFrames: [], sensorFrames: []
        )
        XCTAssertEqual(report.topCPUApps.map(\.name), ["B", "A"])
        XCTAssertEqual(report.topDiskApps.map(\.name), ["A", "B"])
        XCTAssertEqual(report.activeAppCount, 2)
        XCTAssertNil(report.cpuMeanPercent, "no host frames, no invented mean")
    }

    /// Rows: (app name, CPU % of machine, disk read bytes/s or nil when unreadable).
    private func snapshot(
        at second: TimeInterval, rows: [(String, Double, Double?)], continuity: SamplingContinuity = .continuous
    ) throws -> CapturedProcesses {
        let stamp = SampleStamp(
            clockID: UUID(), monotonicNanoseconds: UInt64(second * 1_000_000_000),
            wallTime: epoch.addingTimeInterval(second)
        )
        let processes = try rows.enumerated().map { offset, row in
            ProcessReading(
                id: try ProcessIdentity(pid: Int32(100 + offset), startSeconds: 1, startMicroseconds: 0),
                parentPID: 1, uid: 501, name: row.0, stamp: stamp,
                cpuPercentOfMachine: try .measured(row.1),
                memoryFootprintBytes: try .measured(1024),
                diskReadBytesPerSecond: try row.2.map { try .measured($0) } ?? .restricted(reason: "EPERM"),
                diskWriteBytesPerSecond: try .measured(0),
                executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(rows.count)),
            enumerationTruncated: false, processes: processes, issues: [], continuity: continuity
        )
    }
}

final class AppSeriesTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testScopedSeriesShowsIdleAsZeroAndMissingIntervalsAsGaps() throws {
        var ledger = AppLedger(capacity: 10)
        for (second, cpu, continuity) in [(0.0, 10.0, SamplingContinuity.continuous), (2, 10, .continuous),
                                          (4, 0, .continuous), (3600, 50, .interrupted), (3602, 30, .continuous)] {
            ledger.record(try snapshot(at: second, app: cpu > 0 ? "App" : "Other", cpu: max(cpu, 1), continuity: continuity),
                          logicalCPUCount: 2)
        }
        let series = ledger.series(for: "App")
        // Intervals end at 2, 4 and 3602; the interrupted sample opens no interval.
        XCTAssertEqual(series.cpu.map(\.value), [10, 0, 30])
        XCTAssertEqual(series.cpu.map(\.time), [2, 4, 3602].map { epoch.addingTimeInterval($0) })
        XCTAssertEqual(Set(series.cpu.prefix(2).map(\.segment)).count, 1)
        XCTAssertNotEqual(series.cpu[1].segment, series.cpu[2].segment)
        XCTAssertEqual(ledger.series(for: "Unknown").cpu.map(\.value), [0, 0, 0])
    }

    private func snapshot(
        at second: TimeInterval, app: String, cpu: Double, continuity: SamplingContinuity
    ) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: epoch.addingTimeInterval(second))
        let process = ProcessReading(
            id: try ProcessIdentity(pid: 10, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501,
            name: app, stamp: stamp, cpuPercentOfMachine: try .measured(cpu),
            memoryFootprintBytes: try .measured(1), diskReadBytesPerSecond: try .measured(0),
            diskWriteBytesPerSecond: try .measured(0), executablePath: nil, responsiblePID: nil
        )
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(1), enumerationTruncated: false,
            processes: [process], issues: [], continuity: continuity
        )
    }
}

/// One busy tick in four, one sample per second from `start`.
private actor QuarterBusyHost: HostSampleReading {
    private let clock = UUID()
    private let start: Date
    private var step: UInt64 = 0

    init(start: Date) { self.start = start }

    func read() async -> RawHostSnapshot {
        defer { step += 1 }
        let inventory = HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30)
        let ticks = ProcessorTicks(user: step, system: 0, idle: step * 3, nice: 0)
        let pages = MemoryPages(
            active: 10, inactive: 0, speculative: 0, wired: 2, compressed: 3, compressorContents: 6, purgeable: 0,
            fileBacked: 1, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
        )
        let monotonic: UInt64 = (step + 1) * 1_000_000_000
        let wall = start.addingTimeInterval(Double(step))
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: monotonic, wallTime: wall, inventory: inventory,
            cpu: .success(ticks), memory: .success(pages), swap: .success(SwapUsage(totalBytes: 8192, usedBytes: 0)),
            memoryPressure: .success(.normal), thermalPressure: .success(.nominal)
        )
    }
}
