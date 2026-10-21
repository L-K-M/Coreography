import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class HelperCounterFillTests: XCTestCase {
    private static let team = "AB12CD34EF"

    func testHandlerReadsEachPositivePIDOnce() throws {
        let handler = HelperRequestHandler(readCounters: { $0 == 7 ? nil : Self.counters(pid: $0) })
        let reply = try HelperWire.decode(
            HelperReply.self, from: handler.reply(to: HelperWire.encode(HelperRequest.processCounters(pids: [9, 7, 3, 9])))
        )
        XCTAssertEqual(reply, .processCounters([Self.counters(pid: 3), Self.counters(pid: 9)]), "sorted, unique, exited ones left out")

        for pids: [Int32] in [[0], [-1], [Int32](repeating: 1, count: HelperWire.maximumPIDs + 1)] {
            guard case .refused = try HelperWire.decode(
                HelperReply.self, from: handler.reply(to: HelperWire.encode(HelperRequest.processCounters(pids: pids)))
            ) else { return XCTFail("\(pids.prefix(2)) must be refused") }
        }
    }

    func testARestrictedRowTakesTheHelpersCountersForTheSameProcess() async {
        let base = Sample([
            Self.row(pid: 3, counters: .failure(.restricted(code: EPERM)), threads: .failure(.restricted(code: EPERM))),
            Self.row(pid: 4, counters: .failure(.restricted(code: EPERM)), start: 99),
            Self.row(pid: 5, counters: .success(Self.counters(pid: 5).counters))
        ])
        let transport = Counting(Self.counters(pid: 3), Self.counters(pid: 4))
        let fill = HelperCounterFill(base: base, helper: Self.helper(transport))

        let processes = await fill.read().processes
        XCTAssertEqual(processes[0].counters, .success(Self.counters(pid: 3).counters))
        XCTAssertEqual(processes[0].threads, .success(12))
        XCTAssertEqual(processes[0].monotonicNanoseconds, 2_000, "rates use the helper's read time")
        XCTAssertEqual(processes[1].counters, .failure(.restricted(code: EPERM)), "another start time is a reused PID")
        XCTAssertEqual(processes[2].monotonicNanoseconds, 1_000, "readable rows are left alone")
        let asked = await transport.requests
        XCTAssertEqual(asked, [.processCounters(pids: [3, 4])])
    }

    func testAnUnavailableHelperIsAskedAgainOnlyAfterAMinute() async {
        let rows = Sample([Self.row(pid: 3, counters: .failure(.restricted(code: EPERM)))])
        let registration = Registration(.notRegistered)
        let transport = Counting()
        let helper = PrivilegedHelper(registration: registration, transport: transport, teamID: Self.team)
        let fill = HelperCounterFill(base: rows, helper: helper)

        _ = await fill.read()
        _ = await fill.read()
        XCTAssertEqual(registration.reads, 1, "one status check, then quiet")
        let asked = await transport.requests
        XCTAssertEqual(asked, [])
    }

    func testOnlyTheTeamSignedAppAsks() async {
        let transport = Counting(Self.counters(pid: 3))
        let cli = PrivilegedHelper(
            registration: Registration(.enabled), transport: transport, teamID: Self.team,
            identifier: "ch.lkmc.Coreography.coreo"
        )
        let unsigned = PrivilegedHelper(registration: Registration(.enabled), transport: transport, teamID: nil)
        let fromCLI = await cli.counters(for: [3])
        let fromUnsigned = await unsigned.counters(for: [3])
        XCTAssertNil(fromCLI)
        XCTAssertNil(fromUnsigned)
        let asked = await transport.requests
        XCTAssertEqual(asked, [])
    }

    func testAFullReplyFitsTheReplyLimit() throws {
        let all = (1...Int32(HelperWire.maximumPIDs)).map { Self.counters(pid: $0) }
        let message = HelperWire.encode(HelperReply.processCounters(all))
        XCTAssertLessThan(message.count, HelperReply.maximumBytes)
        XCTAssertEqual(try HelperWire.decode(HelperReply.self, from: message), .processCounters(all))
    }

    private static func helper(_ transport: any HelperTransport) -> PrivilegedHelper {
        PrivilegedHelper(registration: Registration(.enabled), transport: transport, teamID: team)
    }

    private static func counters(pid: Int32) -> IdentifiedProcessCounters {
        IdentifiedProcessCounters(
            pid: pid, startSeconds: 10, startMicroseconds: 0, monotonicNanoseconds: 2_000,
            counters: ProcessCounters(
                userNanoseconds: UInt64(pid) * 1_000_000, systemNanoseconds: 500, physicalFootprintBytes: 4096,
                diskReadBytes: 1, diskWriteBytes: 2, qosNanoseconds: [.utility: 7]
            ),
            threads: 12
        )
    }

    private static func row(
        pid: Int32, counters: Result<ProcessCounters, ProcessDriverError>,
        threads: Result<Int, ProcessDriverError> = .success(1), start: UInt64 = 10
    ) -> RawProcessInfo {
        RawProcessInfo(
            pid: pid, parentPID: 1, uid: 0, startSeconds: start, startMicroseconds: 0, name: "p\(pid)",
            monotonicNanoseconds: 1_000, counters: counters, threads: threads
        )
    }
}

private extension RawProcessSnapshot {
    var processes: [RawProcessInfo] { (try? enumeration.get())?.processes ?? [] }
}

private struct Sample: ProcessSampleReading {
    let rows: [RawProcessInfo]
    init(_ rows: [RawProcessInfo]) { self.rows = rows }

    func read() async -> RawProcessSnapshot {
        RawProcessSnapshot(
            clockID: UUID(), monotonicNanoseconds: 1_000, wallTime: Date(), logicalCPUCount: 8, collectorPID: 1,
            enumeration: .success(ProcessEnumeration(processes: rows, failures: [], isTruncated: false))
        )
    }
}

/// Answers counter requests with fixed entries and records every request.
private actor Counting: HelperTransport {
    private let entries: [IdentifiedProcessCounters]
    private(set) var requests: [HelperRequest] = []

    init(_ entries: IdentifiedProcessCounters...) { self.entries = entries }

    func exchange(_ message: Data) async throws -> Data {
        let request = try HelperWire.decode(HelperRequest.self, from: message)
        requests.append(request)
        return HelperWire.encode(HelperReply.processCounters(entries))
    }
}

private final class Registration: HelperRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private let current: HelperRegistrationStatus
    private var count = 0

    init(_ status: HelperRegistrationStatus) { current = status }

    var reads: Int { lock.withLock { count } }

    func status() -> HelperRegistrationStatus { lock.withLock { count += 1; return current } }
    func register() throws {}
    func unregister() async throws {}
    func openApprovalSettings() {}
}
