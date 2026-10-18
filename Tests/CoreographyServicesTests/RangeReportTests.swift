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

    func testUnknownCoreCountRecordsALowerBoundInsteadOfZeroCPU() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("App", 10, 0)]), logicalCPUCount: nil)
        ledger.record(try snapshot(at: 2, rows: [("App", 10, 0)]), logicalCPUCount: nil)
        let app = try XCTUnwrap(ledger.totals(in: epoch...epoch.addingTimeInterval(5)).apps.first)
        XCTAssertEqual(app.cpuSeconds, 0)
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
