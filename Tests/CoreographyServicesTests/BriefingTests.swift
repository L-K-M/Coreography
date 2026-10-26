import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class BriefingTests: XCTestCase {
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Evidence

    func testEvidenceWaitsForAFullWindowThenCoversFiveMinutes() async throws {
        let short = try await Self.snapshot(seconds: 200)
        XCTAssertNil(BriefingEvidence.digest(short), "after launch the readings cover less than five minutes")

        let full = try await Self.snapshot(seconds: 400)
        let digest = try XCTUnwrap(BriefingEvidence.digest(full))
        XCTAssertEqual(digest.window.upperBound, full.takenAt)
        XCTAssertEqual(digest.window.lowerBound, full.takenAt.addingTimeInterval(-300))
        for section in ["## get_system_summary", "## get_top_processes cpu", "## get_top_processes network",
                        "## get_top_processes disk", "## get_metric_history cpu", "## get_metric_history memoryUsed"] {
            XCTAssertTrue(digest.text.contains(section), section)
        }
        XCTAssertTrue(digest.text.contains("\"Busy\""), "the busiest app is in the readings")
        XCTAssertFalse(digest.text.contains("/Applications/"), "tool results carry no paths")
    }

    // MARK: Requests

    func testRequestsAreSingleTurnAndUseFallbacksOnlyWhereOffered() throws {
        let haiku = try json(BriefingRequest.body(provider: .anthropic, model: "claude-haiku-5-5", digest: "R").body)
        XCTAssertEqual(haiku["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(haiku["system"] as? String, BriefingRequest.systemPrompt)
        XCTAssertEqual((haiku["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual((haiku["messages"] as? [[String: Any]])?.map { $0["role"] as? String }, ["user"])
        XCTAssertNil(haiku["fallbacks"], "Haiku has no server-side fallback")
        XCTAssertNil(haiku["tools"], "one request, no tool loop")
        XCTAssertNil(haiku["temperature"])
        XCTAssertEqual(try BriefingRequest.body(provider: .anthropic, model: "claude-haiku-5-5", digest: "R").betas, [])

        let sonnet = try BriefingRequest.body(provider: .anthropic, model: "claude-sonnet-5-5", digest: "R")
        XCTAssertEqual(try json(sonnet.body)["fallbacks"] as? String, "default")
        XCTAssertEqual(sonnet.betas, BriefingRequest.fallbackBetas)

        let compatible = try json(BriefingRequest.body(provider: .compatible, model: "deepseek-chat", digest: "R").body)
        let messages = try XCTUnwrap(compatible["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(messages[1]["content"] as? String, "R")
        XCTAssertNil(compatible["output_config"], "Anthropic-only fields stay out of compatible requests")
        XCTAssertNil(compatible["system"])
    }

    func testRepliesAreReadByTypeAndFailuresAreNamed() throws {
        let anthropic = try BriefingRequest.text(from: data([
            "stop_reason": "end_turn",
            "content": [["type": "thinking", "thinking": "", "signature": "s"], ["type": "text", "text": "  Quiet,\n\nmostly Safari. "]]
        ]), provider: .anthropic)
        XCTAssertEqual(anthropic, "Quiet, mostly Safari.", "thinking blocks are skipped and spacing is collapsed")

        let compatible = try BriefingRequest.text(from: data([
            "choices": [["finish_reason": "stop", "message": ["role": "assistant", "content": "Busy compiling."]]]
        ]), provider: .compatible)
        XCTAssertEqual(compatible, "Busy compiling.")

        let failures: [([String: Any], BriefingProvider, BriefingError)] = [
            (["stop_reason": "refusal", "content": []], .anthropic, .refused),
            (["stop_reason": "max_tokens", "content": [["type": "text", "text": "Half"]]], .anthropic, .truncated),
            (["stop_reason": "end_turn", "content": [["type": "text", "text": " "]]], .anthropic, .malformedResponse),
            (["choices": [["finish_reason": "length", "message": ["content": "Half"]]]], .compatible, .truncated),
            (["choices": [["finish_reason": "content_filter", "message": ["content": ""]]]], .compatible, .refused),
            (["choices": []], .compatible, .malformedResponse)
        ]
        for (reply, provider, expected) in failures {
            XCTAssertThrowsError(try BriefingRequest.text(from: data(reply), provider: provider)) {
                XCTAssertEqual($0 as? BriefingError, expected)
            }
        }
    }

    func testSettingsAcceptOnlyOfferedModelsAndSafeEndpoints() {
        var settings = BriefingSettings()
        XCTAssertFalse(settings.isEnabled, "briefings send readings on a schedule, so they start off")
        XCTAssertEqual(settings.model, "claude-haiku-5-5")
        settings.anthropicModel = "claude-opus-5-5"
        XCTAssertNil(settings.model, "Opus is not offered for briefings")

        settings.provider = .compatible
        settings.compatibleModel = "  "
        XCTAssertNil(settings.model)
        settings.compatibleModel = " deepseek-chat "
        XCTAssertEqual(settings.model, "deepseek-chat")

        XCTAssertEqual(BriefingSettings.baseURL(" https://api.deepseek.com "), URL(string: "https://api.deepseek.com"))
        XCTAssertNotNil(BriefingSettings.baseURL("http://localhost:11434/v1"), "a local model server may use plain HTTP")
        XCTAssertNil(BriefingSettings.baseURL("http://api.example.com"), "a key never crosses the network in clear text")
        XCTAssertNil(BriefingSettings.baseURL("api.deepseek.com"))
        XCTAssertNil(BriefingSettings.baseURL(""))
    }

    // MARK: Widget card

    func testCardShowsFreshBriefingsAndOtherwiseSaysWhyNot() {
        let end = Self.epoch
        let text = Briefing(outcome: .text("Quiet."), model: "claude-haiku-5-5", windowStart: end.addingTimeInterval(-300), windowEnd: end)
        XCTAssertEqual(BriefingCard.card(.success(text), now: end.addingTimeInterval(60)),
                       .briefing(text: "Quiet.", model: "claude-haiku-5-5", windowEnd: end))
        XCTAssertEqual(BriefingCard.card(.success(text), now: end.addingTimeInterval(BriefingCard.staleAfter)),
                       .offline(reason: .stale(since: end)), "the app stopped writing, so the text is no longer current")
        XCTAssertEqual(BriefingCard.card(.success(nil), now: end), .offline(reason: .off))
        XCTAssertEqual(BriefingCard.card(.failure(.unreadable("denied")), now: end), .offline(reason: .unreadable("denied")))

        let failed = Briefing(outcome: .failed("No key"), model: "m", windowStart: end, windowEnd: end)
        XCTAssertEqual(BriefingCard.card(.success(failed), now: end), .offline(reason: .failed("No key")))
    }

    // MARK: Controller

    @MainActor
    func testControllerWritesOneBriefingForTheWidgetAndClearsItWhenTurnedOff() async throws {
        let transport = ScriptedTransport([ProviderResponse(status: 200, body: data([
            "stop_reason": "end_turn", "content": [["type": "text", "text": "Busy has kept the CPU working."]]
        ]), retryAfter: nil)])
        let store = BriefingStore(directory: directory)
        let snapshot = try await Self.snapshot(seconds: 400)
        let reloads = Counter()
        let anthropic = provider(transport, key: "sk-test")
        let controller = BriefingController(
            snapshot: { snapshot }, store: store, defaults: try defaults(), now: { Self.epoch },
            reloadWidget: { reloads.value += 1 }, compatibleKeys: provider(transport, key: nil)
        ) { _ in anthropic }

        await controller.writeNow()
        XCTAssertEqual(controller.status, .off, "nothing is sent while briefings are off")
        let unsent = await transport.requests
        XCTAssertTrue(unsent.isEmpty)

        var settings = controller.settings
        settings.isEnabled = true
        controller.update(settings)
        await controller.writeNow()

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.key, "sk-test")
        XCTAssertEqual(requests.first?.json["model"] as? String, "claude-haiku-5-5")
        guard case .success(let written?) = store.read() else { return XCTFail("the widget's file was not written") }
        XCTAssertEqual(written.outcome, .text("Busy has kept the CPU working."))
        XCTAssertEqual(written.windowEnd, snapshot.takenAt)
        XCTAssertEqual(controller.status, .written(written))
        XCTAssertEqual(reloads.value, 1, "the widget is asked to redraw after each write")

        settings.isEnabled = false
        controller.update(settings)
        XCTAssertEqual(store.read(), .success(nil), "turning briefings off removes the last one")
        XCTAssertEqual(controller.status, .off)
        XCTAssertEqual(reloads.value, 2)
    }

    @MainActor
    func testFailuresAreWrittenForTheWidgetInsteadOfAnOldBriefing() async throws {
        let store = BriefingStore(directory: directory)
        let snapshot = try await Self.snapshot(seconds: 400)
        let noKey = ScriptedTransport([])
        let keyless = provider(noKey, key: nil)
        let controller = BriefingController(
            snapshot: { snapshot }, store: store, defaults: try defaults(), now: { Self.epoch },
            reloadWidget: {}, compatibleKeys: keyless
        ) { settings in
            settings.provider == .compatible ? nil : keyless
        }
        var settings = controller.settings
        settings.isEnabled = true
        controller.update(settings)
        await controller.writeNow()
        guard case .success(let missingKey?) = store.read() else { return XCTFail("no file") }
        XCTAssertEqual(missingKey.outcome, .failed(BriefingError.noKey.message))

        settings.provider = .compatible
        settings.compatibleModel = "deepseek-chat"
        settings.compatibleBaseURL = "http://example.com"
        controller.update(settings)
        await controller.writeNow()
        guard case .success(let incomplete?) = store.read() else { return XCTFail("no file") }
        XCTAssertEqual(incomplete.outcome, .failed(BriefingError.incompleteSettings.message))
        XCTAssertEqual(incomplete.model, "deepseek-chat")
        let requests = await noKey.requests
        XCTAssertTrue(requests.isEmpty, "nothing is sent without a key or to an unsafe endpoint")
    }

    @MainActor
    func testAReplyForSwitchedSettingsIsDiscardedAndTheStatusRecovers() async throws {
        let store = BriefingStore(directory: directory)
        let snapshot = try await Self.snapshot(seconds: 400)
        let box = ControllerBox()
        let transport = HookTransport(reply: ProviderResponse(status: 200, body: data([
            "stop_reason": "end_turn", "content": [["type": "text", "text": "Written for Haiku."]]
        ]), retryAfter: nil)) { await box.switchModel() }
        let anthropic = AssistantProvider(credentials: MemoryCredentials("k"), transport: transport)
        let controller = BriefingController(
            snapshot: { snapshot }, store: store, defaults: try defaults(), now: { Self.epoch },
            reloadWidget: {}, compatibleKeys: anthropic
        ) { _ in anthropic }
        box.controller = controller
        var settings = controller.settings
        settings.isEnabled = true
        controller.update(settings)

        await controller.writeNow()
        XCTAssertEqual(controller.status, .collecting, "a discarded reply must not leave the status writing")
        XCTAssertEqual(store.read(), .success(nil), "a reply for the previous model is not shown")
    }

    @MainActor
    func testCompatibleKeysAreKeptApartFromTheAnthropicKey() async throws {
        let keys = MemoryCredentials(nil)
        let controller = BriefingController(
            snapshot: { fatalError("no snapshot is needed") }, store: BriefingStore(directory: directory),
            defaults: try defaults(), now: { Self.epoch }, reloadWidget: {},
            compatibleKeys: AssistantProvider(credentials: keys, transport: ScriptedTransport([]))
        ) { _ in nil }
        let saved = await controller.saveCompatibleKey("  sk-deepseek \n")
        XCTAssertNil(saved)
        XCTAssertEqual(try keys.read(), "sk-deepseek")
        XCTAssertTrue(controller.hasCompatibleKey)
        let blank = await controller.saveCompatibleKey("   ")
        XCTAssertEqual(blank, BriefingError.noKey.message)
        _ = await controller.removeCompatibleKey()
        XCTAssertFalse(controller.hasCompatibleKey)
    }

    // MARK: Fixtures

    private func provider(_ transport: ScriptedTransport, key: String?) -> AssistantProvider {
        AssistantProvider(credentials: MemoryCredentials(key), transport: transport)
    }

    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "BriefingTests-\(UUID().uuidString)"))
    }

    private static func snapshot(seconds: Int) async throws -> DiagnosticSnapshot {
        let monitor = try SystemMonitor(driver: SteadyHostDriver(epoch: Self.epoch), historyCapacity: LiveHistory.capacity)
        var ledger = AppLedger(capacity: 1000)
        for second in 0...seconds {
            _ = try await monitor.sample()
            ledger.record(try processes(at: second), logicalCPUCount: 4)
        }
        let host = await monitor.history()
        return DiagnosticSnapshot(
            takenAt: host.last?.stamp.wallTime ?? Self.epoch, host: host, network: [], gpu: [], power: [], sensors: [],
            processes: try processes(at: seconds), ledger: ledger
        )
    }

    private static func processes(at second: Int) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Self.epoch.addingTimeInterval(Double(second)))
        let busy = ProcessReading(
            id: try ProcessIdentity(pid: 100, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501, name: "Busy",
            stamp: stamp, cpuPercentOfMachine: try .measured(40), memoryFootprintBytes: try .measured(1),
            diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
            executablePath: "/Applications/Busy.app/Contents/MacOS/Busy", responsiblePID: nil
        )
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(1), enumerationTruncated: false,
            processes: [busy], issues: [], continuity: .continuous
        )
    }

    private func json(_ body: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func data(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}

/// Switches the model while a request is in flight.
@MainActor
private final class ControllerBox {
    var controller: BriefingController?

    func switchModel() {
        guard let controller else { return }
        var settings = controller.settings
        settings.anthropicModel = BriefingSettings.anthropicModels[1]
        controller.update(settings)
    }
}

private actor HookTransport: ModelTransport {
    private let reply: ProviderResponse
    private let during: @Sendable () async -> Void

    init(reply: ProviderResponse, during: @escaping @Sendable () async -> Void) {
        self.reply = reply
        self.during = during
    }

    func post(_ body: Data, apiKey: String, betas: [String]) async throws -> ProviderResponse {
        await during()
        return reply
    }
}

@MainActor
private final class Counter {
    var value = 0
}

/// One sample a second at a steady 40% CPU.
private actor SteadyHostDriver: HostSampleReading {
    private let clock = UUID()
    private let epoch: Date
    private var step: UInt64 = 0

    init(epoch: Date) { self.epoch = epoch }

    func read() async -> RawHostSnapshot {
        defer { step += 1 }
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: step * 1_000_000_000, wallTime: epoch.addingTimeInterval(Double(step)),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30),
            cpu: .success(ProcessorTicks(user: 40 * step, system: 0, idle: 60 * step, nice: 0)),
            memory: .success(MemoryPages(
                active: 100, inactive: 0, speculative: 0, wired: 10, compressed: 5, compressorContents: 10,
                purgeable: 0, fileBacked: 0, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 1 << 20, usedBytes: 0)),
            memoryPressure: .success(.normal), thermalPressure: .success(.nominal)
        )
    }
}

private actor ScriptedTransport: ModelTransport {
    struct Request: @unchecked Sendable {
        let json: [String: Any]
        let key: String
    }

    private var responses: [ProviderResponse]
    private(set) var requests: [Request] = []

    init(_ responses: [ProviderResponse]) { self.responses = responses }

    func post(_ body: Data, apiKey: String, betas: [String]) async throws -> ProviderResponse {
        let json = (try JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        requests.append(Request(json: json, key: apiKey))
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
