import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class ProcessTrafficTests: XCTestCase {
    private let safari = TrafficLedger.Identity(uniqueID: 900, pid: 42, name: "Safari")

    func testClosedConnectionsKeepTheirBytesSoTotalsNeverDrop() {
        var ledger = TrafficLedger()
        ledger.update(source: 1, identity: safari, received: 1_000, sent: 100)
        XCTAssertEqual(ledger.totals().map(\.receivedBytes), [1_000])

        // One connection closes as another opens: the total keeps growing.
        ledger.update(source: 1, identity: nil, received: 1_500, sent: 150)
        ledger.remove(source: 1)
        ledger.update(source: 2, identity: safari, received: 200, sent: 20)
        XCTAssertEqual(ledger.totals(), [RawProcessTraffic(uniqueID: 900, pid: 42, name: "Safari", receivedBytes: 1_700, sentBytes: 170)])

        // A counter never moves backwards within a source.
        ledger.update(source: 2, identity: nil, received: 100, sent: nil)
        XCTAssertEqual(ledger.totals().first?.receivedBytes, 1_700)
    }

    func testRetiredProcessesLeaveOnceReported() {
        var ledger = TrafficLedger()
        ledger.update(source: 1, identity: safari, received: 10, sent: 1)
        _ = ledger.totals()
        ledger.remove(source: 1)
        XCTAssertEqual(ledger.totals().count, 1, "the closed connection's bytes are reported once")
        XCTAssertTrue(ledger.totals().isEmpty, "then the process with no open socket leaves")
    }

    func testConnectionsWithoutAProcessAreUnattributed() {
        var ledger = TrafficLedger()
        ledger.update(source: 1, identity: nil, received: 64, sent: 32)
        ledger.update(source: 2, identity: .init(uniqueID: 1, pid: 0, name: "kernel_task"), received: 8, sent: 8)
        ledger.remove(source: 1)
        ledger.remove(source: 2)
        XCTAssertTrue(ledger.totals().isEmpty)
        XCTAssertEqual(ledger.unattributedReceived, 72)
        XCTAssertEqual(ledger.unattributedSent, 40)
    }

    func testRatesAreDeltasPerUniqueProcessOverTheRealInterval() async throws {
        let driver = ScriptedTraffic(reads: [
            [traffic(1, pid: 42, received: 1_000)],
            [traffic(1, pid: 42, received: 5_000)],
            // PID 42 was reused by another process: its bytes start a new baseline.
            [traffic(2, pid: 42, received: 9_000)]
        ])
        let monitor = try ProcessTrafficMonitor(driver: driver)
        let first = try await monitor.sample()
        XCTAssertEqual(first.processes.first?.receivedBytesPerSecond.availability, .collecting)
        let second = try await monitor.sample()
        XCTAssertEqual(second.processes.first?.receivedBytesPerSecond.numericValue ?? 0, 2_000, accuracy: 1e-9, "4000 bytes over 2 s")
        XCTAssertEqual(second.processes.first?.receivedBytesPerSecond.availability, .measured)
        let third = try await monitor.sample()
        XCTAssertEqual(third.processes.first?.receivedBytesPerSecond.availability, .collecting, "a reused PID inherits nothing")
        XCTAssertEqual(third.byPID()[42]?.uniqueID, 2)
    }

    func testUnavailableFrameworkIsNamed() async throws {
        let snapshot = try await ProcessTrafficMonitor(driver: ScriptedTraffic(failure: .unavailable("NStatManagerCreate failed"))).sample()
        XCTAssertEqual(snapshot.unavailableReason, "NStatManagerCreate failed")
        XCTAssertTrue(snapshot.processes.isEmpty)
    }

    private func traffic(_ unique: UInt64, pid: Int32, received: UInt64) -> RawProcessTraffic {
        RawProcessTraffic(uniqueID: unique, pid: pid, name: "fixture", receivedBytes: received, sentBytes: 0)
    }
}

private actor ScriptedTraffic: ProcessTrafficSampleReading {
    private let clock = UUID()
    private var reads: [[RawProcessTraffic]]
    private let failure: TrafficDriverError?
    private var count: UInt64 = 0

    init(reads: [[RawProcessTraffic]] = [], failure: TrafficDriverError? = nil) {
        self.reads = reads
        self.failure = failure
    }

    func read() async -> RawTrafficSnapshot {
        count += 1
        let traffic: Result<[RawProcessTraffic], TrafficDriverError> = failure.map { .failure($0) }
            ?? .success(reads.isEmpty ? [] : reads.removeFirst())
        return RawTrafficSnapshot(
            clockID: clock, monotonicNanoseconds: count * 2_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(count) * 2), traffic: traffic
        )
    }
}
