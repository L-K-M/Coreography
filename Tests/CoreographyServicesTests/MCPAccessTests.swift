import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class MCPAccessTests: XCTestCase {
    private var directory: URL!
    private var socketPath: String { directory.appendingPathComponent("mcp.sock").path }
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUpWithError() throws {
        // Short: socket paths are limited to about 100 bytes.
        directory = URL(fileURLWithPath: "/tmp/coreo-\(UUID().uuidString.prefix(8))")
        suite = "MCPAccessTests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    func testResolverNamesTheLaunchingAppFromTheProcessTree() {
        let tree = Tree([
            50: RawPeerProcess(pid: 50, parentPID: 40, uid: 501, path: "/Applications/Coreography.app/Contents/Helpers/coreo"),
            40: RawPeerProcess(pid: 40, parentPID: 30, uid: 501, path: "/usr/local/bin/node"),
            30: RawPeerProcess(pid: 30, parentPID: 1, uid: 501, path: "/Applications/Claude.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper")
        ], signing: ["/Applications/Claude.app": CodeSigning(signature: .otherSigner, identifier: "com.anthropic.claude", teamID: "Q6L2SF6YDW")])
        XCTAssertEqual(
            ClientIdentityResolver(reader: tree).identity(ofPeer: 50),
            ClientIdentity(key: "team:Q6L2SF6YDW/com.anthropic.claude", displayName: "Claude", detail: "com.anthropic.claude, team Q6L2SF6YDW")
        )

        let shell = Tree([
            50: RawPeerProcess(pid: 50, parentPID: 40, uid: 501, path: "/usr/local/bin/coreo"),
            40: RawPeerProcess(pid: 40, parentPID: 1, uid: 501, path: "/usr/sbin/sshd")
        ])
        XCTAssertEqual(ClientIdentityResolver(reader: shell).identity(ofPeer: 50)?.key, "path:/usr/sbin/sshd", "no app: the top of the tree")

        let unsigned = Tree([
            50: RawPeerProcess(pid: 50, parentPID: 30, uid: 501, path: "/x/coreo"),
            30: RawPeerProcess(pid: 30, parentPID: 1, uid: 501, path: "/Users/me/Tools/Agent.app/Contents/MacOS/Agent")
        ])
        XCTAssertEqual(ClientIdentityResolver(reader: unsigned).identity(ofPeer: 50)?.key, "path:/Users/me/Tools/Agent.app",
                       "an unsigned app is bound to its location")
        XCTAssertNil(ClientIdentityResolver(reader: Tree([:])).identity(ofPeer: 50))
    }

    @MainActor
    func testAccessIsOffByDefaultAndThePersonApprovesEachClientOnce() async throws {
        let access = makeAccess()
        XCTAssertFalse(access.isEnabled)
        XCTAssertThrowsError(try LocalChannelClient.connect(path: socketPath), "nothing listens while access is off")

        access.setEnabled(true)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let socket = try FileManager.default.attributesOfItem(atPath: socketPath)
        XCTAssertEqual((socket[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let first = try LocalChannelClient.connect(path: socketPath)
        let request = try await eventually { access.pendingApproval }
        XCTAssertEqual(request.identity.displayName, "Assistant")
        access.answer(request.id, allow: true)
        let ready = try await first.readLine()
        XCTAssertEqual(ready.flatMap(MCPBridge.status), .ready)
        try first.write(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        let initialized = try await first.readLine()
        XCTAssertTrue(initialized?.contains("coreography") ?? false)
        XCTAssertEqual(access.grants.map(\.identity.key), ["team:TEAM/com.example.assistant"])
        XCTAssertEqual(access.sessions.count, 1)

        // The same app connects again without asking.
        let second = try LocalChannelClient.connect(path: socketPath)
        let again = try await second.readLine()
        XCTAssertEqual(again.flatMap(MCPBridge.status), .ready)
        XCTAssertNil(access.pendingApproval)

        // Revoking ends the client's sessions; a call in flight gets nothing.
        access.revoke(try XCTUnwrap(access.grants.first).id)
        try? second.write(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_system_summary"}}"#)
        let afterRevoke = try? await second.readLine()
        XCTAssertNil(afterRevoke ?? nil, "a revoked session is closed")
        XCTAssertTrue(access.sessions.isEmpty)
        first.close()
        access.shutdown()
    }

    @MainActor
    func testDeniedClientsDisablingAndOtherUsersAreRefused() async throws {
        let access = makeAccess()
        access.setEnabled(true)
        let client = try LocalChannelClient.connect(path: socketPath)
        let request = try await eventually { access.pendingApproval }
        access.answer(request.id, allow: false)
        let denied = try await client.readLine()
        XCTAssertEqual(denied.flatMap(MCPBridge.status), .denied)
        XCTAssertTrue(access.grants.isEmpty)

        access.setEnabled(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath), "disabling removes the socket")
        XCTAssertFalse(MCPAccess(
            version: "test", snapshot: { Self.emptySnapshot() }, socketPath: socketPath, defaults: defaults,
            resolver: ClientIdentityResolver(reader: Self.assistantTree), currentUser: UInt32(getuid())
        ).isEnabled, "the switch is saved")

        let stranger = MCPAccess(
            version: "test", snapshot: { Self.emptySnapshot() }, socketPath: socketPath, defaults: defaults,
            resolver: ClientIdentityResolver(reader: Self.assistantTree), currentUser: UInt32(getuid()) &+ 1
        )
        stranger.setEnabled(true)
        let foreign = try LocalChannelClient.connect(path: socketPath)
        let refused = try await foreign.readLine()
        XCTAssertEqual(refused.flatMap(MCPBridge.status), .denied, "a peer of another user is refused before anything else")
        XCTAssertNil(stranger.pendingApproval)
        stranger.shutdown()
    }

    @MainActor
    func testTheBridgeClientReportsRefusalsAndPipesASession() async throws {
        let unavailable = await MCPBridgeClient.run(path: socketPath, input: { nil }, output: { _ in })
        XCTAssertEqual(unavailable, .unavailable("Coreography is not running, or MCP access is off in its Settings"))

        let access = makeAccess()
        access.setEnabled(true)
        let lines = Lines([#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#])
        let output = Output()
        let session = Task.detached { [socketPath] in
            await MCPBridgeClient.run(path: socketPath, input: { lines.next() }, output: { output.append($0) })
        }
        let request = try await eventually { access.pendingApproval }
        access.answer(request.id, allow: true)
        let outcome = await session.value
        XCTAssertEqual(outcome, .finished)
        XCTAssertEqual(output.lines, [#"{"id":1,"jsonrpc":"2.0","result":{}}"#])
        access.shutdown()
    }

    // MARK: Fixtures

    @MainActor
    private func makeAccess() -> MCPAccess {
        MCPAccess(
            version: "test", snapshot: { Self.emptySnapshot() }, socketPath: socketPath, defaults: defaults,
            resolver: ClientIdentityResolver(reader: Self.assistantTree), currentUser: UInt32(getuid())
        )
    }

    /// Every peer looks launched by one signed assistant app.
    private static let assistantTree = AnyPeer(
        path: "/Applications/Assistant.app/Contents/MacOS/Assistant",
        signing: CodeSigning(signature: .otherSigner, identifier: "com.example.assistant", teamID: "TEAM")
    )

    @MainActor
    private static func emptySnapshot() -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            takenAt: Date(), host: [], network: [], gpu: [], power: [], sensors: [], processes: nil, ledger: AppLedger(capacity: 1)
        )
    }

    @MainActor
    private func eventually<Value>(_ read: () -> Value?) async throws -> Value {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let value = read() { return value }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(read())
    }
}

private struct Tree: PeerProcessReading {
    let processes: [Int32: RawPeerProcess]
    var signatures: [String: CodeSigning] = [:]

    init(_ processes: [Int32: RawPeerProcess], signing: [String: CodeSigning] = [:]) {
        self.processes = processes
        signatures = signing
    }

    func process(_ pid: Int32) -> RawPeerProcess? { processes[pid] }

    func signing(path: String) -> CodeSigning {
        signatures[path] ?? CodeSigning(signature: .unknown, identifier: nil, teamID: nil)
    }
}

/// Any PID's parent is one app process.
private struct AnyPeer: PeerProcessReading {
    private static let appPID: Int32 = 2
    let path: String
    let signing: CodeSigning

    func process(_ pid: Int32) -> RawPeerProcess? {
        pid == Self.appPID
            ? RawPeerProcess(pid: pid, parentPID: 1, uid: 501, path: path)
            : RawPeerProcess(pid: pid, parentPID: Self.appPID, uid: 501, path: "/usr/local/bin/coreo")
    }

    func signing(path: String) -> CodeSigning { signing }
}

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String]

    init(_ lines: [String]) { self.lines = lines }

    /// Blocks briefly like stdin, then ends.
    func next() -> String? {
        Thread.sleep(forTimeInterval: 0.2)
        return lock.withLock { lines.isEmpty ? nil : lines.removeFirst() }
    }
}

private final class Output: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [String] = []

    func append(_ line: String) { lock.withLock { collected.append(line) } }

    var lines: [String] { lock.withLock { collected } }
}
