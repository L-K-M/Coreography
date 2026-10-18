import Foundation
import XCTest
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
