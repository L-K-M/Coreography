import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class HelperActionTests: XCTestCase {
    private static let team = "AB12CD34EF"
    private static let other = HelperProcessIdentity(pid: 300, startSeconds: 5, startMicroseconds: 0)

    func testHandlerActsOnTheNamedProcessAndNeverOnTheKernelLaunchdOrItself() async throws {
        let calls = Calls()
        let handler = HelperRequestHandler(
            sendSignal: { calls.record("\($1.rawValue) \($0.pid)@\($0.startSeconds)"); return $0.pid == 301 ? .failure(.identityChanged) : .success(()) },
            setNice: { calls.record("nice \($1) \($0.pid)"); return .failure(.needsAdministrator) },
            ownPID: 400
        )

        var reply = try await Self.reply(handler, .signal(process: Self.other, signal: .kill))
        XCTAssertEqual(reply, .actionDone)
        reply = try await Self.reply(handler, .signal(process: HelperProcessIdentity(pid: 301, startSeconds: 5, startMicroseconds: 0), signal: .suspend))
        XCTAssertEqual(reply, .actionFailed(.identityChanged))
        reply = try await Self.reply(handler, .renice(process: Self.other, niceValue: 10))
        XCTAssertEqual(reply, .actionFailed(.notPermitted))

        for pid: Int32 in [0, 1, 400] {
            reply = try await Self.reply(handler, .signal(process: HelperProcessIdentity(pid: pid, startSeconds: 5, startMicroseconds: 0), signal: .terminate))
            XCTAssertEqual(reply, .actionFailed(.invalidTarget), "PID \(pid)")
        }
        reply = try await Self.reply(handler, .renice(process: Self.other, niceValue: 21))
        XCTAssertEqual(reply, .refused("A nice value must be between -20 and 20."))
        XCTAssertEqual(calls.all, ["kill 300@5", "suspend 301@5", "nice 10 300"], "refused requests reach no process")
    }

    func testTheControllerFallsBackOnlyThroughAnAnsweringHelper() async throws {
        let target = try ProcessIdentity(pid: 300, startSeconds: 5, startMicroseconds: 0)
        let transport = Acting()
        let helper = PrivilegedHelper(registration: Enabled(), transport: transport, teamID: Self.team)
        let controller = ProcessController(driver: Refusing(), signaler: Refusing(), helper: helper)

        XCTAssertEqual(controller.send(.hangUp, to: target), .notPermitted(reason: "Not permitted: the process belongs to another user or is protected"))
        XCTAssertTrue(controller.canAskHelper)
        let sent = await controller.sendThroughHelper(.hangUp, to: target)
        XCTAssertEqual(sent, .requested)
        let quit = await controller.terminateThroughHelper(target, mode: .graceful)
        XCTAssertEqual(quit, .requested)
        let lowered = await controller.lowerPriorityThroughHelper(of: target)
        XCTAssertEqual(lowered, .requested)
        let raised = await controller.raisePriorityThroughHelper(of: target)
        XCTAssertEqual(raised, .requested)
        let requests = await transport.requests
        XCTAssertEqual(requests, [
            .signal(process: target.helperIdentity, signal: .hangUp),
            .signal(process: target.helperIdentity, signal: .terminate),
            .renice(process: target.helperIdentity, niceValue: ProcessController.lowPriorityNice),
            .renice(process: target.helperIdentity, niceValue: ProcessController.highPriorityNice)
        ])

        XCTAssertFalse(ProcessController(driver: Refusing(), signaler: Refusing()).canAskHelper)
    }

    func testAProtectedTargetDoesNotSilenceTheHelper() async throws {
        // A Force Quit of launchd is refused by the helper itself, which is still answering.
        let launchd = try ProcessIdentity(pid: 1, startSeconds: 5, startMicroseconds: 0)
        let transport = RealHandler()
        let helper = PrivilegedHelper(registration: Enabled(), transport: transport, teamID: Self.team)
        let controller = ProcessController(driver: Refusing(), signaler: Refusing(), helper: helper)

        let quit = await controller.terminateThroughHelper(launchd, mode: .forced)
        XCTAssertEqual(quit, .failed(reason: "This process cannot be targeted"))
        _ = await helper.counters(for: [300])
        let asked = await transport.count
        XCTAssertEqual(asked, 2, "the next request still goes to the helper")
    }

    func testAnAnswerOfTheWrongKindStartsTheQuietMinute() async {
        let transport = WrongKind()
        let helper = PrivilegedHelper(registration: Enabled(), transport: transport, teamID: Self.team)
        let first = await helper.counters(for: [3])
        let second = await helper.counters(for: [3])
        XCTAssertNil(first)
        XCTAssertNil(second)
        let asked = await transport.count
        XCTAssertEqual(asked, 1)
    }

    private static func reply(_ handler: HelperRequestHandler, _ request: HelperRequest) async throws -> HelperReply {
        try HelperWire.decode(HelperReply.self, from: await handler.reply(to: HelperWire.encode(request)))
    }
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    var all: [String] { lock.withLock { calls } }
    func record(_ call: String) { lock.withLock { calls.append(call) } }
}

private actor Acting: HelperTransport {
    private(set) var requests: [HelperRequest] = []

    func exchange(_ message: Data) async throws -> Data {
        requests.append(try HelperWire.decode(HelperRequest.self, from: message))
        return HelperWire.encode(HelperReply.actionDone)
    }
}

/// The helper's real request handling, with no process to act on.
private actor RealHandler: HelperTransport {
    private let handler = HelperRequestHandler(ownPID: 400)
    private(set) var count = 0

    func exchange(_ message: Data) async throws -> Data {
        count += 1
        return await handler.reply(to: message)
    }
}

/// Answers every request with sockets, as only a broken helper would.
private actor WrongKind: HelperTransport {
    private(set) var count = 0

    func exchange(_ message: Data) async throws -> Data {
        count += 1
        return HelperWire.encode(HelperReply.sockets([]))
    }
}

private struct Enabled: HelperRegistering {
    func status() -> HelperRegistrationStatus { .enabled }
    func register() throws {}
    func unregister() async throws {}
    func openApprovalSettings() {}
}

/// Every request refused for permission, as for another user's process.
private struct Refusing: ProcessTerminating, ProcessSignaling {
    @MainActor
    func terminate(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, mode: ProcessTermination) -> Result<Void, ProcessControlError> {
        .failure(.notPermitted)
    }

    func send(_ signal: ProcessSignal, pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) -> Result<Void, ProcessControlError> {
        .failure(.notPermitted)
    }

    func renice(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, to niceValue: Int32) -> Result<Void, ProcessControlError> {
        .failure(.needsAdministrator)
    }
}
