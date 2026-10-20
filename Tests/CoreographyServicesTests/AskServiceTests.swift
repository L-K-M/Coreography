import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class AskServiceTests: XCTestCase {
    func testToolLoopEchoesTheTurnAndAnswersFromOneSnapshot() async throws {
        let transport = ScriptedTransport([
            reply(stop: "tool_use", content: [
                ["type": "thinking", "thinking": "", "signature": "sig"],
                ["type": "tool_use", "id": "toolu_1", "name": "get_top_processes", "input": ["metric": "cpu", "limit": 1]],
                ["type": "tool_use", "id": "toolu_2", "name": "get_sleep_history", "input": [:]]
            ]),
            reply(stop: "end_turn", content: [["type": "text", "text": "Big uses the most CPU (frame evidence)."]])
        ])
        let service = AskService(provider: AssistantProvider(credentials: MemoryCredentials("sk-test"), transport: transport))
        let snapshot = try makeSnapshot()
        let answer = try await service.ask("Why is my Mac slow?", snapshot: snapshot)

        XCTAssertEqual(answer.text, "Big uses the most CPU (frame evidence).")
        XCTAssertEqual(answer.snapshotID, snapshot.id)
        XCTAssertEqual(answer.toolCalls.map(\.name), ["get_top_processes", "get_sleep_history"])
        XCTAssertEqual(answer.toolCalls.map(\.failed), [false, true])
        XCTAssertTrue(answer.toolCalls[0].evidence.contains(.app("Big")), "the ranked app links back into the window")
        XCTAssertEqual(answer.toolCalls[1].evidence, [], "a failed call is no evidence")

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let first = requests[0]
        XCTAssertEqual(first.key, "sk-test")
        XCTAssertEqual(first.betas, ["server-side-fallback-2026-07-01"])
        XCTAssertEqual(first.json["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(first.json["fallbacks"] as? String, "default")
        XCTAssertNil(first.json["thinking"], "adaptive thinking is the model default")
        XCTAssertEqual((first.json["tools"] as? [[String: Any]])?.count, 6)
        XCTAssertNotNil((first.json["tools"] as? [[String: Any]])?.first?["input_schema"])

        // The second request echoes the assistant turn unchanged, then all results in one user message.
        let messages = try XCTUnwrap(requests[1].json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertEqual((messages[1]["content"] as? [[String: Any]])?.first?["signature"] as? String, "sig")
        let results = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(results.map { $0["tool_use_id"] as? String }, ["toolu_1", "toolu_2"])
        XCTAssertEqual(results.map { $0["is_error"] as? Bool }, [nil, true])
        let top = try XCTUnwrap(results[0]["content"] as? String)
        XCTAssertTrue(top.contains("\"Big\""))
    }

    func testFailuresNeverRunToolsOrInventAnswers() async throws {
        let snapshot = try makeSnapshot()
        let noKey = AskService(provider: AssistantProvider(credentials: MemoryCredentials(nil), transport: ScriptedTransport([])))
        await assertThrows(AskError.noKey) { try await noKey.ask("?", snapshot: snapshot) }

        let cases: [(ProviderResponse, AskError)] = [
            (ProviderResponse(status: 401, body: Data(), retryAfter: nil), .invalidKey),
            (ProviderResponse(status: 429, body: Data(), retryAfter: "7"), .rateLimited(retryAfter: "7")),
            (ProviderResponse(status: 529, body: Data(), retryAfter: nil), .overloaded),
            (ProviderResponse(status: 400, body: Data(#"{"error":{"message":"bad"}}"#.utf8), retryAfter: nil), .badRequest("bad")),
            (reply(stop: "refusal", content: []), .refused),
            (reply(stop: "max_tokens", content: [["type": "tool_use", "id": "t", "name": "get_data_sources", "input": [:]]]), .truncated)
        ]
        for (response, expected) in cases {
            let service = AskService(provider: AssistantProvider(credentials: MemoryCredentials("k"), transport: ScriptedTransport([response])))
            await assertThrows(expected) { try await service.ask("?", snapshot: snapshot) }
        }

        let looping = Array(repeating: reply(stop: "tool_use", content: [
            ["type": "tool_use", "id": "t", "name": "get_data_sources", "input": [:]]
        ]), count: AskService.maxRounds)
        let service = AskService(provider: AssistantProvider(credentials: MemoryCredentials("k"), transport: ScriptedTransport(looping)))
        await assertThrows(AskError.tooManyRounds) { try await service.ask("?", snapshot: snapshot) }
    }

    func testKeysAreTrimmedAndBlankKeysRefused() async throws {
        let store = MemoryCredentials(nil)
        let service = AskService(provider: AssistantProvider(credentials: store, transport: ScriptedTransport([])))
        let before = await service.hasKey()
        XCTAssertFalse(before)
        try await service.saveKey("  sk-live\n")
        XCTAssertEqual(try store.read(), "sk-live")
        await assertThrows(AskError.noKey) { try await service.saveKey("   ") }
        try await service.removeKey()
        let after = await service.hasKey()
        XCTAssertFalse(after)
    }

    // MARK: Fixtures

    private func makeSnapshot() throws -> DiagnosticSnapshot {
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        func processes(_ second: TimeInterval) throws -> CapturedProcesses {
            let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: epoch.addingTimeInterval(second))
            let process = ProcessReading(
                id: try ProcessIdentity(pid: 10, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501,
                name: "Big", stamp: stamp, cpuPercentOfMachine: try .measured(40),
                memoryFootprintBytes: try .measured(1), diskReadBytesPerSecond: try .measured(0),
                diskWriteBytesPerSecond: try .measured(0), executablePath: nil, responsiblePID: nil
            )
            return ProcessSnapshot(
                stamp: stamp, collectorPID: 1, enumeration: try .measured(1), enumerationTruncated: false,
                processes: [process], issues: [], continuity: .continuous
            )
        }
        var ledger = AppLedger(capacity: 4)
        ledger.record(try processes(0), logicalCPUCount: 2)
        ledger.record(try processes(2), logicalCPUCount: 2)
        return DiagnosticSnapshot(
            takenAt: epoch.addingTimeInterval(2), host: [], network: [], gpu: [], power: [], sensors: [],
            processes: try processes(2), ledger: ledger
        )
    }

    private func assertThrows<T>(
        _ expected: AskError, file: StaticString = #filePath, line: UInt = #line, _ body: () async throws -> T
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AskError, expected, file: file, line: line)
        }
    }
}

private func reply(stop: String, content: [[String: Any]]) -> ProviderResponse {
    let body = try! JSONSerialization.data(withJSONObject: ["stop_reason": stop, "content": content, "role": "assistant"])
    return ProviderResponse(status: 200, body: body, retryAfter: nil)
}

private actor ScriptedTransport: ModelTransport {
    struct Request: @unchecked Sendable {
        let json: [String: Any]
        let key: String
        let betas: [String]
    }

    private var responses: [ProviderResponse]
    private(set) var requests: [Request] = []

    init(_ responses: [ProviderResponse]) { self.responses = responses }

    func post(_ body: Data, apiKey: String, betas: [String]) async throws -> ProviderResponse {
        let json = (try JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        requests.append(Request(json: json, key: apiKey, betas: betas))
        precondition(!responses.isEmpty, "Unexpected request")
        return responses.removeFirst()
    }
}

private final class MemoryCredentials: CredentialStoring, @unchecked Sendable {
    private var secret: String?
    init(_ secret: String?) { self.secret = secret }
    func read() throws -> String? { secret }
    func save(_ secret: String) throws { self.secret = secret }
    func delete() throws { secret = nil }
}
