import Foundation
import Observation
import CoreographyKit

/// An approved MCP client: the app Coreography found behind it, never the
/// name it sent (plan: MCP access, one-time approval per client pairing).
public struct MCPGrant: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let identity: ClientIdentity
    public let approvedAt: Date
    public var lastUsedAt: Date?
}

/// A client waiting for the person to allow or deny it.
public struct MCPApprovalRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let identity: ClientIdentity
    public let requestedAt: Date
}

/// One connected client session, for Settings.
public struct MCPSessionInfo: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let grantID: UUID
    public let clientName: String
    public let connectedAt: Date
}

/// What the app tells the bridge before any MCP traffic flows.
enum MCPBridgeStatus: String, Codable {
    case ready, denied, busy, disabled
}

/// Local MCP access through the running app (plan: off by default,
/// peer-checked local IPC, scoped revocable grants, shared budgets).
///
/// ```text
/// coreo mcp --stdio ──Unix socket (0600)──> listener ──> peer uid = ours?
///                                                     ├─> client identity from the process tree
///                                                     ├─> grant? else ask the person (120 s)
///                                                     └─> MCPServer per session, grant checked per call
/// ```
@MainActor
@Observable
public final class MCPAccess {
    /// More sessions than this are refused, not queued.
    static let maximumSessions = 4
    /// Calls per rolling second across all sessions; each session also has its own limit.
    static let globalCallsPerSecond = 20
    static let approvalTimeout: Duration = .seconds(120)
    private static let enabledKey = "mcpAccessEnabled"
    static let grantsKey = "mcpGrants"

    public private(set) var isEnabled: Bool
    public private(set) var grants: [MCPGrant]
    public private(set) var sessions: [MCPSessionInfo] = []
    public private(set) var pendingApproval: MCPApprovalRequest?
    /// Why the listener is not running while access is on.
    public private(set) var problem: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let socketPath: String
    @ObservationIgnored private let version: String
    @ObservationIgnored private let snapshot: @MainActor @Sendable () -> DiagnosticSnapshot
    @ObservationIgnored private let resolver: ClientIdentityResolver
    @ObservationIgnored private let currentUser: UInt32
    @ObservationIgnored private var listener: LocalChannelListener?
    @ObservationIgnored private var acceptLoop: Task<Void, Never>?
    @ObservationIgnored private var connections: [UUID: LocalChannel] = [:]
    @ObservationIgnored private var approvals: [UUID: CheckedContinuation<Bool, Never>] = [:]
    @ObservationIgnored private var queuedApprovals: [MCPApprovalRequest] = []
    @ObservationIgnored private var recentCalls: [Date] = []
    @ObservationIgnored private var lastUseSaved: Date?
    private static let lastUseSaveInterval: TimeInterval = 60

    public convenience init(version: String, snapshot: @escaping @MainActor @Sendable () -> DiagnosticSnapshot) {
        self.init(
            version: version, snapshot: snapshot, socketPath: MCPEndpoint.defaultPath, defaults: .standard,
            resolver: ClientIdentityResolver(), currentUser: UInt32(getuid())
        )
    }

    init(
        version: String, snapshot: @escaping @MainActor @Sendable () -> DiagnosticSnapshot, socketPath: String,
        defaults: UserDefaults, resolver: ClientIdentityResolver, currentUser: UInt32
    ) {
        self.version = version
        self.snapshot = snapshot
        self.socketPath = socketPath
        self.defaults = defaults
        self.resolver = resolver
        self.currentUser = currentUser
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        grants = (defaults.data(forKey: Self.grantsKey)).flatMap { try? JSONDecoder().decode([MCPGrant].self, from: $0) } ?? []
        if isEnabled { startListening() }
    }

    /// Turning access off closes every session and refuses further requests.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        enabled ? startListening() : stopListening()
    }

    /// Revoking a client ends its open sessions at once.
    public func revoke(_ grantID: UUID) {
        grants.removeAll { $0.id == grantID }
        saveGrants()
        for session in sessions where session.grantID == grantID { close(session.id) }
    }

    public func answer(_ requestID: UUID, allow: Bool) {
        guard let continuation = approvals.removeValue(forKey: requestID) else { return }
        continuation.resume(returning: allow)
        advanceApprovals(after: requestID)
    }

    /// Clients waiting for an answer, shown or queued.
    var approvalsWaiting: Int { approvals.count }

    /// Stop listening when the app quits; the socket file goes with it.
    public func shutdown() { stopListening() }

    // MARK: Listening

    private func startListening() {
        do {
            let listener = try LocalChannelListener(path: socketPath)
            self.listener = listener
            problem = nil
            acceptLoop = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        self?.admit(try await listener.accept())
                    } catch {
                        // Closing ends the loop quietly; anything else would leave access looking on but deaf.
                        if !Task.isCancelled, (error as? LocalChannelError) != .closed {
                            self?.problem = "MCP access stopped listening: \(error). Turn it off and on again."
                        }
                        return
                    }
                }
            }
        } catch {
            problem = "MCP access could not listen: \(error)"
        }
    }

    private func stopListening() {
        saveGrants()
        acceptLoop?.cancel()
        acceptLoop = nil
        listener?.close()
        listener = nil
        for id in Array(connections.keys) { close(id) }
        for (id, continuation) in approvals {
            continuation.resume(returning: false)
            approvals[id] = nil
        }
        queuedApprovals.removeAll()
        pendingApproval = nil
    }

    // MARK: Sessions

    private func admit(_ channel: LocalChannel) {
        Task { [weak self] in
            guard let self else { return channel.close() }
            // The kernel's record of the peer, not anything it sent.
            guard let peer = channel.peer, peer.uid == currentUser else { return reject(channel, .denied) }
            guard isEnabled else { return reject(channel, .disabled) }
            guard sessions.count < Self.maximumSessions else { return reject(channel, .busy) }
            guard let identity = resolver.identity(ofPeer: peer.pid) else { return reject(channel, .denied) }

            let grant: MCPGrant
            if let existing = grants.first(where: { $0.identity.key == identity.key }) {
                grant = existing
            } else {
                guard await askApproval(identity) else { return reject(channel, .denied) }
                guard isEnabled else { return reject(channel, .disabled) }
                // Answers to clients that waited together: one grant, and the cap still holds.
                guard sessions.count < Self.maximumSessions else { return reject(channel, .busy) }
                if let approved = grants.first(where: { $0.identity.key == identity.key }) {
                    grant = approved
                } else {
                    grant = MCPGrant(id: UUID(), identity: identity, approvedAt: Date(), lastUsedAt: nil)
                    grants.append(grant)
                    saveGrants()
                }
            }
            serve(channel, grant: grant)
        }
    }

    private func serve(_ channel: LocalChannel, grant: MCPGrant) {
        let id = UUID()
        connections[id] = channel
        sessions.append(MCPSessionInfo(id: id, grantID: grant.id, clientName: grant.identity.displayName, connectedAt: Date()))
        touch(grant.id)
        let snapshot = snapshot
        let server = MCPServer(
            version: version,
            authorize: { [weak self] check in await self?.authorizes(grant.id, session: id, check) ?? .revoked },
            snapshot: { await MainActor.run { snapshot() } }
        )
        Task { [weak self] in
            guard (try? channel.write(MCPBridge.statusLine(.ready))) != nil else {
                self?.close(id)
                return
            }
            while let line = try? await channel.readLine() {
                guard !line.isEmpty else { continue }
                guard let response = await server.handle(line) else { continue }
                guard (try? channel.write(response)) != nil else { break }
            }
            self?.close(id)
        }
    }

    /// The grant still stands and the session is open; a call also needs
    /// room in the budget all sessions share, which delivery does not spend.
    private func authorizes(_ grantID: UUID, session: UUID, _ check: MCPCheck) -> MCPAuthorization {
        guard isEnabled, connections[session] != nil, grants.contains(where: { $0.id == grantID }) else { return .revoked }
        guard check == .call else { return .allowed }
        let now = Date()
        recentCalls.removeAll { now.timeIntervalSince($0) >= 1 }
        guard recentCalls.count < Self.globalCallsPerSecond else { return .throttled(callsPerSecond: Self.globalCallsPerSecond) }
        recentCalls.append(now)
        touch(grantID)
        return .allowed
    }

    private func close(_ session: UUID) {
        connections.removeValue(forKey: session)?.close()
        sessions.removeAll { $0.id == session }
    }

    private func reject(_ channel: LocalChannel, _ status: MCPBridgeStatus) {
        try? channel.write(MCPBridge.statusLine(status))
        channel.close()
    }

    // MARK: Approval

    /// One request is shown at a time; later ones wait their turn, and
    /// each is denied if the person does not answer in time.
    private func askApproval(_ identity: ClientIdentity) async -> Bool {
        let request = MCPApprovalRequest(id: UUID(), identity: identity, requestedAt: Date())
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.approvalTimeout)
            self?.answer(request.id, allow: false)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation in
            approvals[request.id] = continuation
            if pendingApproval == nil { pendingApproval = request } else { queuedApprovals.append(request) }
        }
    }

    private func advanceApprovals(after requestID: UUID) {
        queuedApprovals.removeAll { $0.id == requestID }
        guard pendingApproval?.id == requestID else { return }
        pendingApproval = queuedApprovals.isEmpty ? nil : queuedApprovals.removeFirst()
    }

    /// Last use is saved at most once a minute, not with every call.
    private func touch(_ grantID: UUID) {
        guard let index = grants.firstIndex(where: { $0.id == grantID }) else { return }
        let now = Date()
        grants[index].lastUsedAt = now
        guard now.timeIntervalSince(lastUseSaved ?? .distantPast) >= Self.lastUseSaveInterval else { return }
        lastUseSaved = now
        saveGrants()
    }

    private func saveGrants() {
        defaults.set(try? JSONEncoder().encode(grants), forKey: Self.grantsKey)
    }
}

/// The bridge's first line, before any MCP message.
enum MCPBridge {
    static let statusKey = "coreographyBridge"

    static func statusLine(_ status: MCPBridgeStatus) -> String {
        "{\"\(statusKey)\":\"\(status.rawValue)\"}"
    }

    static func status(of line: String) -> MCPBridgeStatus? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String] else { return nil }
        return object[statusKey].flatMap(MCPBridgeStatus.init(rawValue:))
    }
}

/// The CLI half of the bridge: it pipes an assistant's stdio to the
/// app's session and decides nothing itself.
public enum MCPBridgeClient {
    public enum Outcome: Equatable, Sendable {
        case finished
        /// The app is not running, or access is off.
        case unavailable(String)
        case refused(String)
    }

    public static func run(
        path: String = MCPEndpoint.defaultPath,
        input: @escaping @Sendable () -> String?, output: @escaping @Sendable (String) -> Void
    ) async -> Outcome {
        let channel: LocalChannel
        do {
            channel = try LocalChannelClient.connect(path: path)
        } catch {
            return .unavailable("Coreography is not running, or MCP access is off in its Settings")
        }
        // The app answers once it has checked the client, which may wait for approval.
        guard let first = try? await channel.readLine(), let status = MCPBridge.status(of: first) else {
            channel.close()
            return .unavailable("Coreography closed the connection")
        }
        switch status {
        case .ready: break
        case .denied:
            channel.close()
            return .refused("Coreography did not approve this client; allow it when asked, or check Settings > MCP access")
        case .busy:
            channel.close()
            return .refused("Coreography already serves its maximum number of MCP sessions")
        case .disabled:
            channel.close()
            return .refused("MCP access is off in Coreography's Settings")
        }

        // stdin blocks, so it reads on its own thread; its end closes the session.
        let forward = Task.detached {
            while let line = input() {
                guard (try? channel.write(line)) != nil else { break }
            }
            channel.close()
        }
        while let line = try? await channel.readLine() { output(line) }
        forward.cancel()
        return .finished
    }
}
