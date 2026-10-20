import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class ProcessEnergyTests: XCTestCase {
    private let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date(timeIntervalSince1970: 1_700_000_000))

    func testTheLedgerTotalsEnergyOnlyWhereItWasRead() throws {
        var ledger = AppLedger(capacity: 10)
        let first = try snapshot(at: 0, [(10, "Safari", 10, 1.5)])
        let second = try snapshot(at: 2, [(10, "Safari", 10, 1.5)])
        ledger.record(first, logicalCPUCount: 4)
        let interval = try XCTUnwrap(ledger.record(second, logicalCPUCount: 4))
        XCTAssertTrue(interval.coversEnergy)
        XCTAssertEqual(interval.entries.first?.energyJoules ?? 0, 3, accuracy: 1e-9, "1.5 W for 2 s")
        let range = stamp.wallTime.addingTimeInterval(-10)...stamp.wallTime.addingTimeInterval(10)
        XCTAssertEqual(ledger.totals(in: range).apps.first?.energyJoules ?? 0, 3, accuracy: 1e-9)

        var unread = AppLedger(capacity: 10)
        unread.record(try snapshot(at: 0, [(10, "Safari", 10, nil)]), logicalCPUCount: 4)
        let uncovered = try XCTUnwrap(unread.record(try snapshot(at: 2, [(10, "Safari", 10, nil)]), logicalCPUCount: 4))
        XCTAssertFalse(uncovered.coversEnergy, "no process had an energy counter")
        XCTAssertNil(unread.totals(in: range).apps.first?.energyJoules, "no energy read is unknown, not zero")
        let snapshot = DiagnosticSnapshot(
            takenAt: stamp.wallTime.addingTimeInterval(2), host: [], network: [], gpu: [], power: [], sensors: [],
            processes: second, ledger: unread
        )
        XCTAssertThrowsError(try DiagnosticTools.topApps(snapshot, metric: .energy)) {
            XCTAssertEqual($0 as? DiagnosticError, .unavailable("Per-process energy was not modeled in this range"))
        }
        let ranked = try DiagnosticTools.topApps(DiagnosticSnapshot(
            takenAt: stamp.wallTime.addingTimeInterval(2), host: [], network: [], gpu: [], power: [], sensors: [],
            processes: second, ledger: ledger
        ), metric: .energy)
        XCTAssertEqual(ranked.rows.map(\.app), ["Safari"])
        XCTAssertEqual(ranked.rows.first?.value, 3)
        XCTAssertEqual(ranked.rows.first?.unit, "joules")
    }

    /// An app whose only figure is energy still gets an entry, so the joules are not lost.
    func testAnAppWithOnlyEnergyStillGetsAnEntry() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, [(10, "Meter", 0, 2)]), logicalCPUCount: 4)
        let interval = try XCTUnwrap(ledger.record(try snapshot(at: 2, [(10, "Meter", 0, 2)]), logicalCPUCount: 4))
        let entry = try XCTUnwrap(interval.entries.first { $0.app == "Meter" })
        XCTAssertEqual(entry.energyJoules, 4, accuracy: 1e-9)
        XCTAssertEqual(entry.cpuSeconds, 0)
        XCTAssertEqual(ledger.totals(in: interval.start...interval.end).apps.first?.name, "Meter")
    }

    /// Energy read in some intervals of a range is a lower bound for the range.
    func testPartlyCoveredEnergyIsALowerBound() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, [(10, "Safari", 10, 1.5)]), logicalCPUCount: 4)
        ledger.record(try snapshot(at: 2, [(10, "Safari", 10, 1.5)]), logicalCPUCount: 4)
        ledger.record(try snapshot(at: 4, [(10, "Safari", 10, nil)]), logicalCPUCount: 4)
        let range = stamp.wallTime.addingTimeInterval(-10)...stamp.wallTime.addingTimeInterval(10)
        let total = try XCTUnwrap(ledger.totals(in: range).apps.first)
        XCTAssertEqual(total.energyJoules ?? 0, 3, accuracy: 1e-9)
        XCTAssertTrue(total.energyIsLowerBound, "the uncovered interval may have used energy")
        XCTAssertFalse(total.isLowerBound, "CPU and disk were read throughout")

        // A stored part that covered no energy leaves the live part's joules a lower bound.
        let stored = (apps: [
            AppRangeTotal(name: "Safari", cpuSeconds: 1, diskBytes: 0, isLowerBound: false),
            AppRangeTotal(name: "Mail", cpuSeconds: 1, diskBytes: 0, isLowerBound: false)
        ], covered: Optional(range))
        let live = (apps: [AppRangeTotal(name: "Safari", cpuSeconds: 1, diskBytes: 0, energyJoules: 3, isLowerBound: false)],
                    covered: Optional(range))
        let combined = Dictionary(uniqueKeysWithValues: AppLedger.combine(stored, live).apps.map { ($0.name, $0) })
        XCTAssertEqual(combined["Safari"]?.energyJoules, 3)
        XCTAssertEqual(combined["Safari"]?.energyIsLowerBound, true)
        XCTAssertEqual(combined["Mail"]?.energyJoules, 0, "read as zero where energy was covered")
        XCTAssertEqual(combined["Mail"]?.energyIsLowerBound, true)
        // A stored part with intervals but no app activity says nothing about its energy either.
        let quiet = (apps: [AppRangeTotal](), covered: Optional(range))
        XCTAssertEqual(AppLedger.combine(quiet, live).apps.first?.energyIsLowerBound, true)
        XCTAssertEqual(AppLedger.combine((apps: [AppRangeTotal](), covered: nil), live).apps.first?.energyIsLowerBound, false,
                       "a part with no intervals at all changes nothing")
        let whole = AppLedger.combine(live, live).apps.first
        XCTAssertEqual(whole?.energyJoules, 6)
        XCTAssertEqual(whole?.energyIsLowerBound, false)
    }

    func testTheRangeReportRanksAppsByEnergyOnlyWhereCovered() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, [(10, "Bright", 10, 3), (11, "Dim", 10, 1)]), logicalCPUCount: 4)
        ledger.record(try snapshot(at: 2, [(10, "Bright", 10, 3), (11, "Dim", 10, 1)]), logicalCPUCount: 4)
        let range = stamp.wallTime.addingTimeInterval(-10)...stamp.wallTime.addingTimeInterval(10)
        let report = RangeReport.make(range: range, ledger: ledger, frames: [], gpuFrames: [], sensorFrames: [])
        XCTAssertEqual(report.topEnergyApps?.map(\.name), ["Bright", "Dim"])
        XCTAssertEqual(report.topEnergyApps?.first?.energyJoules ?? 0, 6, accuracy: 1e-9)

        var dark = AppLedger(capacity: 10)
        dark.record(try snapshot(at: 0, [(10, "Bright", 10, nil)]), logicalCPUCount: 4)
        dark.record(try snapshot(at: 2, [(10, "Bright", 10, nil)]), logicalCPUCount: 4)
        let unlit = RangeReport.make(range: range, ledger: dark, frames: [], gpuFrames: [], sensorFrames: [])
        XCTAssertNil(unlit.topEnergyApps, "no coverage is unknown, not zero")
    }

    func testTotalsSavedBeforeEnergyStillDecode() throws {
        let saved = #"{"name":"Safari","cpuSeconds":1,"diskBytes":0,"isLowerBound":false}"#
        let total = try JSONDecoder().decode(AppRangeTotal.self, from: Data(saved.utf8))
        XCTAssertNil(total.energyJoules)
        XCTAssertFalse(total.energyIsLowerBound)
    }

    // MARK: Fixtures

    /// Rows: (pid, app name, CPU % of machine, CPU watts or nil without an energy counter).
    private func snapshot(at second: TimeInterval = 0, _ rows: [(Int32, String, Double, Double?)]) throws -> CapturedProcesses {
        let stamp = SampleStamp(
            clockID: self.stamp.clockID, monotonicNanoseconds: UInt64(1 + second * 1e9), wallTime: self.stamp.wallTime.addingTimeInterval(second)
        )
        let processes = try rows.map { pid, name, cpu, watts in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501, name: name,
                stamp: stamp, cpuPercentOfMachine: try .measured(cpu), memoryFootprintBytes: try .measured(1),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                cpuPowerWatts: try watts.map { try .estimated($0, method: "Energy model") } ?? .unsupported(reason: "No energy counter"),
                executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(processes.count)), enumerationTruncated: false,
            processes: processes, issues: [], continuity: .continuous
        )
    }
}
