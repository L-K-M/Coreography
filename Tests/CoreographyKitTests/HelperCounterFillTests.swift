import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class HelperCounterFillTests: XCTestCase {
    private static let team = "AB12CD34EF"

    func testHandlerReadsEachPositivePIDOnce() async throws {
        let reads = ReadLog()
        let handler = HelperRequestHandler(readCounters: {
            reads.record($0)
            return $0 == 7 ? nil : Self.counters(pid: $0)
        })
        let reply = try HelperWire.decode(
            HelperReply.self, from: await handler.reply(to: HelperWire.encode(HelperRequest.processCounters(pids: [9, 7, 3, 9])))
        )
        XCTAssertEqual(reply, .processCounters([Self.counters(pid: 3), Self.counters(pid: 9)]), "sorted, unique, exited ones left out")
        XCTAssertEqual(reads.pids, [3, 7, 9], "each PID read once")

        // Distinct small PIDs keep the oversized list under the byte limit, so the count is what refuses it.
        let tooMany = Array(1...Int32(HelperWire.maximumPIDs + 1))
        XCTAssertLessThan(HelperWire.encode(HelperRequest.processCounters(pids: tooMany)).count, HelperRequest.maximumBytes)
        let cases: [([Int32], String)] = [
            ([0], "A process ID must be positive."),
            ([5, -1], "A process ID must be positive."),
            (tooMany, "At most \(HelperWire.maximumPIDs) processes per request.")
        ]
        for (pids, reason) in cases {
            let reply = try HelperWire.decode(
                HelperReply.self, from: await handler.reply(to: HelperWire.encode(HelperRequest.processCounters(pids: pids)))
            )
            XCTAssertEqual(reply, .refused(reason), "\(pids.prefix(2))")
        }
        XCTAssertEqual(reads.pids, [3, 7, 9], "a refused list reads nothing")
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

    func testKernelTaskDoesNotSpoilTheRequest() async {
        // PID 0 is listed and restricted like other root processes, but the helper refuses it.
        let base = Sample([
            Self.row(pid: 0, counters: .failure(.restricted(code: EPERM))),
            Self.row(pid: 3, counters: .failure(.restricted(code: EPERM)))
        ])
        let fill = HelperCounterFill(base: base, helper: Self.helper(Answering(Self.counters(pid: 3))))

        let processes = await fill.read().processes
        XCTAssertEqual(processes[0].counters, .failure(.restricted(code: EPERM)))
        XCTAssertEqual(processes[1].counters, .success(Self.counters(pid: 3).counters))
    }

    func testAnUnavailableHelperIsAskedAgainOnlyAfterAMinute() async {
        let rows = Sample([Self.row(pid: 3, counters: .failure(.restricted(code: EPERM)))])
        let registration = Registration(.notRegistered)
        let transport = Counting()
        let clock = Clock()
        let helper = PrivilegedHelper(registration: registration, transport: transport, teamID: Self.team, now: clock.now)
        let fill = HelperCounterFill(base: rows, helper: helper)

        _ = await fill.read()
        _ = await fill.read()
        XCTAssertEqual(registration.reads, 1, "one status check, then quiet")
        clock.advance(.seconds(59))
        _ = await fill.read()
        XCTAssertEqual(registration.reads, 1, "still quiet within the minute")
        clock.advance(.seconds(2))
        _ = await fill.read()
        XCTAssertEqual(registration.reads, 2, "asked again after a minute")
        let asked = await transport.requests
        XCTAssertEqual(asked, [])
    }

    func testAnOutdatedHelpersRefusalIsAskedAgainOnlyAfterAMinute() async {
        let refusing = Refusing()
        let clock = Clock()
        let helper = PrivilegedHelper(registration: Registration(.enabled), transport: refusing, teamID: Self.team, now: clock.now)

        let first = await helper.counters(for: [3])
        XCTAssertNil(first)
        clock.advance(.seconds(59))
        _ = await helper.counters(for: [3])
        var asked = await refusing.count
        XCTAssertEqual(asked, 1, "quiet within the minute")
        clock.advance(.seconds(2))
        _ = await helper.counters(for: [3])
        asked = await refusing.count
        XCTAssertEqual(asked, 2)
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

private actor Refusing: HelperTransport {
    private(set) var count = 0

    func exchange(_ message: Data) async throws -> Data {
        count += 1
        return HelperWire.encode(HelperReply.refused("no"))
    }
}

private final class ReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var read: [Int32] = []

    var pids: [Int32] { lock.withLock { read } }

    func record(_ pid: Int32) { lock.withLock { read.append(pid) } }
}

/// A clock the test moves by hand.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = ContinuousClock.now

    var now: @Sendable () -> ContinuousClock.Instant { { self.lock.withLock { self.current } } }

    func advance(_ duration: Duration) { lock.withLock { current += duration } }
}

/// Answers the way the real handler does, from fixed entries.
private struct Answering: HelperTransport {
    let handler: HelperRequestHandler

    init(_ entries: IdentifiedProcessCounters...) {
        handler = HelperRequestHandler(readCounters: { pid in entries.first { $0.pid == pid } })
    }

    func exchange(_ message: Data) async throws -> Data { await handler.reply(to: message) }
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
