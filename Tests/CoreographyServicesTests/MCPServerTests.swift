import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class MCPServerTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testHandshakeNotificationsAndToolCatalog() async throws {
        let server = try makeServer()
        let initialize = try await response(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#)
        let result = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "coreography")

        let unknownVersion = try await response(server, #"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        XCTAssertEqual((unknownVersion["result"] as? [String: Any])?["protocolVersion"] as? String, MCPServer.protocolVersion)

        let notification = await server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(notification)

        let list = try await response(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }), [
            "get_system_summary", "get_top_processes", "get_metric_history",
            "get_process_details", "get_sleep_history", "get_data_sources"
        ])
        XCTAssertTrue(tools.allSatisfy { ($0["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true })
    }

    func testPagingStaysOnOneSnapshotAndToolErrorsAreResults() async throws {
        let counter = SnapshotCounter()
        let server = try makeServer(counter: counter)
        let first = try await toolCall(server, id: 1, name: "get_top_processes", arguments: #"{"metric":"cpu","limit":1}"#)
        let page = try decodeText(first)
        XCTAssertEqual((page["rows"] as? [[String: Any]])?.first?["app"] as? String, "Big")
        let cursor = try XCTUnwrap(page["nextCursor"] as? String)

        let second = try await toolCall(server, id: 2, name: "get_top_processes", arguments: #"{"metric":"cpu","limit":1,"cursor":"\#(cursor)"}"#)
        XCTAssertEqual((try decodeText(second)["rows"] as? [[String: Any]])?.first?["app"] as? String, "Small")
        let taken = await counter.count
        XCTAssertEqual(taken, 1, "the cursor reused its snapshot")

        let badLimit = try await toolCall(server, id: 3, name: "get_top_processes", arguments: #"{"limit":"ten"}"#)
        XCTAssertEqual(badLimit["isError"] as? Bool, true)
        let expired = try await toolCall(server, id: 4, name: "get_system_summary", arguments: #"{"snapshot_id":"\#(UUID().uuidString)"}"#)
        XCTAssertEqual(expired["isError"] as? Bool, true)
        let sleep = try await toolCall(server, id: 5, name: "get_sleep_history", arguments: "{}")
        XCTAssertEqual(sleep["isError"] as? Bool, true)
    }

    func testProtocolErrorsAndTheCallBudget() async throws {
        let server = try makeServer()
        let parse = try await response(server, "{not json")
        XCTAssertEqual((parse["error"] as? [String: Any])?["code"] as? Int, -32700)
        let method = try await response(server, #"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#)
        XCTAssertEqual((method["error"] as? [String: Any])?["code"] as? Int, -32601)
        let tool = try await response(server, #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"run_shell"}}"#)
        XCTAssertEqual((tool["error"] as? [String: Any])?["code"] as? Int, -32602)

        // Every tools/call counts. The clock stands still: a fresh session's eleventh call is refused.
        let budgeted = try makeServer()
        var results: [[String: Any]] = []
        for id in 0..<11 {
            results.append(try await toolCall(budgeted, id: 100 + id, name: "get_data_sources", arguments: "{}"))
        }
        XCTAssertEqual(results.filter { $0["isError"] as? Bool == true }.count, 1)
        XCTAssertTrue((results.last?["content"] as? [[String: Any]])?.first?["text"] as? String == "Rate limit: at most 10 tool calls per second")
    }

    /// A call spends the shared budget once; delivery only rechecks the grant,
    /// and an exhausted budget reads as a rate limit, not a revocation.
    func testACallSpendsTheSharedBudgetOnceAndThrottlingIsNotRevocation() async throws {
        let checks = Checks()
        let server = try makeServer(authorize: { await checks.record($0) })
        _ = try await toolCall(server, id: 1, name: "get_data_sources", arguments: "{}")
        let recorded = await checks.all
        XCTAssertEqual(recorded, [.call, .delivery])

        // A session over its own limit is refused before it touches the shared budget.
        let busy = try makeServer(authorize: { await checks.record($0) })
        for id in 0..<11 { _ = try await toolCall(busy, id: 10 + id, name: "get_data_sources", arguments: "{}") }
        let shared = await checks.all.filter { $0 == .call }.count
        XCTAssertEqual(shared, 1 + 10, "the eleventh call never reached the shared budget")

        await checks.throttle()
        let throttled = try await toolCall(server, id: 2, name: "get_data_sources", arguments: "{}")
        XCTAssertEqual(throttled["isError"] as? Bool, true)
        let text = (throttled["content"] as? [[String: Any]])?.first?["text"] as? String
        XCTAssertEqual(text, "Rate limit: Coreography serves at most 20 tool calls per second across its clients")
    }

    // MARK: Fixtures

    private func makeServer(
        counter: SnapshotCounter = SnapshotCounter(),
        authorize: @escaping @Sendable (MCPCheck) async -> MCPAuthorization = { _ in .allowed }
    ) throws -> MCPServer {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try processes(at: 0), logicalCPUCount: 2)
        ledger.record(try processes(at: 2), logicalCPUCount: 2)
        let snapshot = DiagnosticSnapshot(
            takenAt: epoch.addingTimeInterval(2), host: [], network: [], gpu: [], power: [], sensors: [],
            processes: try processes(at: 2), ledger: ledger
        )
        let instant = epoch
        return MCPServer(version: "test", now: { instant }, authorize: authorize) { await counter.take(snapshot) }
    }

    private func processes(at second: TimeInterval) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: epoch.addingTimeInterval(second))
        let rows = try [("Big", 40.0), ("Small", 5.0)].enumerated().map { offset, app in
            ProcessReading(
                id: try ProcessIdentity(pid: Int32(10 + offset), startSeconds: 1, startMicroseconds: 0), parentPID: 1,
                uid: 501, name: app.0, stamp: stamp, cpuPercentOfMachine: try .measured(app.1),
                memoryFootprintBytes: try .measured(1), diskReadBytesPerSecond: try .measured(0),
                diskWriteBytesPerSecond: try .measured(0), executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(2), enumerationTruncated: false,
            processes: rows, issues: [], continuity: .continuous
        )
    }

    private func response(_ server: MCPServer, _ line: String) async throws -> [String: Any] {
        let reply = await server.handle(line)
        let text = try XCTUnwrap(reply)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func toolCall(_ server: MCPServer, id: Int, name: String, arguments: String) async throws -> [String: Any] {
        let reply = try await response(
            server, #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
        )
        return try XCTUnwrap(reply["result"] as? [String: Any])
    }

    private func decodeText(_ result: [String: Any]) throws -> [String: Any] {
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}

private actor SnapshotCounter {
    private(set) var count = 0

    func take(_ snapshot: DiagnosticSnapshot) -> DiagnosticSnapshot {
        count += 1
        return snapshot
    }
}

private actor Checks {
    private(set) var all: [MCPCheck] = []
    private var throttled = false

    func throttle() { throttled = true }

    func record(_ check: MCPCheck) -> MCPAuthorization {
        all.append(check)
        return throttled && check == .call ? .throttled(callsPerSecond: 20) : .allowed
    }
}
