import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class CPUBraidTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plan: cause beside symptom. On a 4-core machine over one 2 s
    /// interval, each app's share and the remainder add up to the host mean.
    func testStrandsAndRemainderAddUpToTheHostMeanOverEachInterval() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("Xcode", 30), ("Safari", 10)]), logicalCPUCount: 4)
        ledger.record(try snapshot(at: 2, rows: [("Xcode", 30), ("Safari", 10)]), logicalCPUCount: 4)
        let host = try hostReadings([(0, 5), (1, 45), (2, 55)])

        let braid = try XCTUnwrap(Braids.cpu(
            intervals: ledger.intervals, names: ledger.names, host: host, window: window(0, 10)
        ))
        XCTAssertEqual(braid.strands.map(\.kind), [.app("Xcode"), .app("Safari"), .unattributed])
        let column = try XCTUnwrap(braid.columns.first)
        XCTAssertEqual(column.shares.map { $0 ?? -1 }, [30, 10, 10], "host 45 % and 55 % average 50 %; apps used 40 %")
        XCTAssertEqual(column.total, 50, accuracy: 1e-9)
        XCTAssertEqual(column.hostMean, 50)
        XCTAssertTrue(column.reconciles)
        XCTAssertEqual(braid.strands[0].cpuSeconds, 2.4, accuracy: 1e-9, "30 % of 4 cores for 2 s")
        XCTAssertEqual(braid.strands[2].cpuSeconds, 0.8, accuracy: 1e-9)
    }

    func testTheTailFoldsIntoOtherAppsAndAPinnedAppKeepsItsOwnStrand() throws {
        var ledger = AppLedger(capacity: 10)
        let rows = (1...8).map { ("App\($0)", Double($0)) }
        ledger.record(try snapshot(at: 0, rows: rows), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 2, rows: rows), logicalCPUCount: 1)

        let plain = try XCTUnwrap(Braids.cpu(intervals: ledger.intervals, names: ledger.names, host: [], window: window(0, 10)))
        XCTAssertEqual(plain.strands.map(\.kind), [
            .app("App8"), .app("App7"), .app("App6"), .app("App5"), .app("App4"), .otherApps(count: 3), .unattributed
        ])
        XCTAssertEqual(plain.columns.first?.shares[5] ?? 0, 6, accuracy: 1e-9, "1 + 2 + 3 %")

        let pinned = try XCTUnwrap(Braids.cpu(
            intervals: ledger.intervals, names: ledger.names, host: [], window: window(0, 10), pinned: "App1"
        ))
        XCTAssertEqual(pinned.strands.map(\.kind), [
            .app("App8"), .app("App7"), .app("App6"), .app("App5"), .app("App4"), .app("App1"),
            .otherApps(count: 2), .unattributed
        ])
    }

    /// Without host readings over an interval, the remainder is unknown,
    /// not zero; a gap in sampling starts a new segment.
    func testMissingHostReadingsLeaveTheRemainderUnknownAndBreaksStartSegments() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("App", 10)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 2, rows: [("App", 10)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 60, rows: [("App", 10)], continuity: .interrupted), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 62, rows: [("App", 20)]), logicalCPUCount: 1)
        let host = [(time: epoch.addingTimeInterval(2), cpu: MetricReading.gap(reason: "Sleep"))]
            + (try hostReadings([(61, 30), (62, 30)]))

        let braid = try XCTUnwrap(Braids.cpu(intervals: ledger.intervals, names: ledger.names, host: host, window: window(0, 100)))
        XCTAssertEqual(braid.columns.count, 2)
        let remainder = try XCTUnwrap(braid.columns[0].shares.last)
        XCTAssertNil(remainder, "an unmeasured host reading leaves the remainder unknown")
        XCTAssertEqual(braid.columns[1].shares.last ?? nil, 10)
        XCTAssertEqual(braid.columns.map(\.segment), [0, 1])
    }

    func testSkewNeverMakesTheRemainderNegativeAndAnEmptyWindowHasNoBraid() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("App", 60)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 2, rows: [("App", 60)]), logicalCPUCount: 1)
        let braid = try XCTUnwrap(Braids.cpu(
            intervals: ledger.intervals, names: ledger.names, host: try hostReadings([(0, 0), (2, 50)]), window: window(0, 10)
        ))
        XCTAssertEqual(braid.columns.first?.shares.last ?? nil, 0)
        XCTAssertEqual(braid.columns.first?.reconciles, false, "apps at 60 % over a host at 50 % is a disagreement to show")
        XCTAssertNil(Braids.cpu(intervals: ledger.intervals, names: ledger.names, host: [], window: window(100, 200)))
    }

    func testColumnLookupFindsTheIntervalHoldingATime() throws {
        var ledger = AppLedger(capacity: 10)
        for second in stride(from: 0.0, through: 8, by: 2) {
            ledger.record(try snapshot(at: second, rows: [("App", second)]), logicalCPUCount: 1)
        }
        let braid = try XCTUnwrap(Braids.cpu(intervals: ledger.intervals, names: ledger.names, host: [], window: window(0, 10)))
        XCTAssertEqual(braid.column(at: epoch.addingTimeInterval(3))?.end, epoch.addingTimeInterval(4))
        XCTAssertEqual(braid.column(at: epoch.addingTimeInterval(8))?.end, epoch.addingTimeInterval(8))
        XCTAssertNil(braid.column(at: epoch.addingTimeInterval(9)))
    }

    /// The reading card opens "other apps" into the members it folded.
    func testTheLedgerListsEveryAppsShareInTheIntervalHoldingATime() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("A", 50), ("B", 2), ("C", 0)]), logicalCPUCount: 2)
        ledger.record(try snapshot(at: 2, rows: [("A", 50), ("B", 2), ("C", 0)]), logicalCPUCount: 2)
        let shares = try XCTUnwrap(ledger.cpuShares(at: epoch.addingTimeInterval(1)))
        XCTAssertEqual(shares.map(\.name), ["A", "B"], "idle apps are not contributors")
        XCTAssertFalse(shares[0].isEstimate)
        XCTAssertEqual(shares[0].value, 50, accuracy: 1e-9)
        XCTAssertNil(ledger.cpuShares(at: epoch.addingTimeInterval(5)))
    }

    func testArrowKeysStepIntervalsAndOptionArrowsFindPeaks() throws {
        var ledger = AppLedger(capacity: 10)
        for (second, cpu) in [(0.0, 5.0), (2, 10), (4, 40), (6, 20), (8, 30), (10, 30), (12, 5)] {
            ledger.record(try snapshot(at: second, rows: [("App", cpu)]), logicalCPUCount: 1)
        }
        let braid = try XCTUnwrap(Braids.cpu(intervals: ledger.intervals, names: ledger.names, host: [], window: window(0, 20)))
        let at = { (second: TimeInterval) in self.epoch.addingTimeInterval(second) }
        XCTAssertEqual(braid.column(from: nil, offset: -1)?.end, at(12), "nothing inspected starts at the newest")
        XCTAssertEqual(braid.column(from: at(5), offset: -1)?.end, at(4))
        XCTAssertNil(braid.column(from: at(1), offset: -1))
        XCTAssertEqual(braid.peak(from: at(1), forward: true)?.end, at(4))
        XCTAssertEqual(braid.peak(from: at(4), forward: true)?.end, at(8), "the 30 % plateau counts once")
        XCTAssertEqual(braid.peak(from: at(11), forward: false)?.end, at(8))
        XCTAssertNil(braid.peak(from: at(11), forward: true), "the newest interval has no neighbour after it")
    }

    func testAnIntervalAtAGapsEdgeIsNoPeak() throws {
        var ledger = AppLedger(capacity: 10)
        for (second, cpu) in [(0.0, 5.0), (2, 10), (4, 60)] {
            ledger.record(try snapshot(at: second, rows: [("App", cpu)]), logicalCPUCount: 1)
        }
        ledger.record(try snapshot(at: 30, rows: [("App", 5)], continuity: .interrupted), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 32, rows: [("App", 5)]), logicalCPUCount: 1)
        let braid = try XCTUnwrap(Braids.cpu(intervals: ledger.intervals, names: ledger.names, host: [], window: window(0, 40)))
        XCTAssertNil(braid.peak(from: nil, forward: true), "60 % right before a gap is a rise, not a peak")
        XCTAssertNil(braid.peak(from: epoch.addingTimeInterval(3), forward: true))
        XCTAssertEqual(braid.peak(from: epoch.addingTimeInterval(1), forward: true)?.end, nil)

        // From inside the gap, arrows and peaks look outward, not from the window's far end.
        let inGap = epoch.addingTimeInterval(15)
        XCTAssertEqual(braid.column(from: inGap, offset: -1)?.end, epoch.addingTimeInterval(4))
        XCTAssertEqual(braid.column(from: inGap, offset: 1)?.end, epoch.addingTimeInterval(32))
    }

    /// A host reading covers the span since the reading before it, so an
    /// interval's host share weighs each reading by its overlap.
    func testHostShareIsWeightedByTheTimeEachReadingCovers() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("App", 10)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 3, rows: [("App", 10)]), logicalCPUCount: 1)
        let host = try hostReadings([(0, 99), (1, 40), (3, 60), (4, 20)])
        let means = Braids.hostMeans(over: ledger.intervals, host: host)
        XCTAssertEqual(try XCTUnwrap(means.first ?? nil), 160.0 / 3, accuracy: 1e-9, "1 s at 40 % and 2 s at 60 %")

        let short = Braids.hostMeans(over: ledger.intervals, host: try hostReadings([(0, 10), (2, 40)]))
        XCTAssertNil(short.first ?? nil, "readings end before the interval does: nothing is extrapolated")
    }

    /// The remainder counts only the part of an interval inside the window,
    /// as the apps do, so the strands describe the same span.
    func testTheRemainderIsCountedInsideTheWindowLikeTheApps() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("App", 10)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 10, rows: [("App", 10)]), logicalCPUCount: 1)
        let host = try hostReadings([(0, 0), (10, 30)])
        let braid = try XCTUnwrap(Braids.cpu(intervals: ledger.intervals, names: ledger.names, host: host, window: window(5, 20)))
        XCTAssertEqual(braid.strands[0].cpuSeconds, 0.5, accuracy: 1e-9, "10 % for the 5 s inside")
        XCTAssertEqual(braid.strands[1].cpuSeconds, 1, accuracy: 1e-9, "20 % remainder for the same 5 s")
        XCTAssertEqual(braid.columns.first?.appsShare ?? 0, 10, accuracy: 1e-9)
    }

    /// The window ranks apps by what they did inside it, so a long interval
    /// it barely touches does not crown its app.
    func testRankingCountsOnlyThePartOfAnIntervalInsideTheWindow() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try snapshot(at: 0, rows: [("Before", 90), ("Inside", 0)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 10, rows: [("Before", 90), ("Inside", 0)]), logicalCPUCount: 1)
        ledger.record(try snapshot(at: 12, rows: [("Before", 0), ("Inside", 50)]), logicalCPUCount: 1)
        let braid = try XCTUnwrap(Braids.cpu(
            intervals: ledger.intervals, names: ledger.names, host: [], window: window(9.5, 20)
        ))
        XCTAssertEqual(braid.strands.map(\.kind).prefix(2), [.app("Inside"), .app("Before")])
        XCTAssertEqual(braid.strands[1].cpuSeconds, 0.45, accuracy: 1e-9, "90 % for the half second inside")
    }

    /// Every interval of the live hour is kept: thinning to the total's
    /// extremes would misplace the strands under it.
    func testAnHourKeepsEveryIntervalAndItsSpike() throws {
        var ledger = AppLedger(capacity: 2000)
        for index in 0...1800 {
            let spike = index == 900 ? 90.0 : 5
            ledger.record(try snapshot(at: Double(index) * 2, rows: [("A", spike), ("B", 1)]), logicalCPUCount: 1)
        }
        let braid = try XCTUnwrap(Braids.cpu(intervals: ledger.intervals, names: ledger.names, host: [], window: window(0, 3600)))
        XCTAssertEqual(braid.columns.count, 1800)
        XCTAssertTrue(braid.columns.contains { ($0.shares[0] ?? 0) == 90 })
        XCTAssertTrue(braid.columns.allSatisfy { $0.shares.count == braid.strands.count })
    }

    private func window(_ start: TimeInterval, _ end: TimeInterval) -> ClosedRange<Date> {
        epoch.addingTimeInterval(start)...epoch.addingTimeInterval(end)
    }

    private func hostReadings(_ values: [(TimeInterval, Double)]) throws -> [(time: Date, cpu: MetricReading)] {
        try values.map { (time: epoch.addingTimeInterval($0.0), cpu: try MetricReading.measured($0.1)) }
    }

    private func snapshot(
        at second: TimeInterval, rows: [(String, Double)], continuity: SamplingContinuity = .continuous
    ) throws -> CapturedProcesses {
        let stamp = SampleStamp(
            clockID: UUID(), monotonicNanoseconds: UInt64(second * 1_000_000_000), wallTime: epoch.addingTimeInterval(second)
        )
        let processes = try rows.enumerated().map { offset, row in
            ProcessReading(
                id: try ProcessIdentity(pid: Int32(100 + offset), startSeconds: 1, startMicroseconds: 0),
                parentPID: 1, uid: 501, name: row.0, stamp: stamp,
                cpuPercentOfMachine: try .measured(row.1), memoryFootprintBytes: try .measured(1024),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(rows.count)),
            enumerationTruncated: false, processes: processes, issues: [], continuity: continuity
        )
    }
}
