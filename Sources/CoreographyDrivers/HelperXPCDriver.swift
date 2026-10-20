import Foundation
#if os(macOS)
import ServiceManagement
#endif

public enum HelperTransportError: Error, Equatable, Sendable {
    case unsupportedPlatform
    /// This build has no team to pin the helper's signature to.
    case unsignedBuild
    case unreachable(String)
    case timedOut
    case cancelled
}

/// One encoded request out, one encoded reply back.
public protocol HelperTransport: Sendable {
    func exchange(_ message: Data) async throws -> Data
}

#if os(macOS)
/// The Objective-C face of the wire: one method carrying encoded values,
/// so the interface never grows a call per feature.
@objc public protocol HelperXPCProtocol {
    func exchange(_ message: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}
#endif

/// The app's side: one privileged-service XPC connection per exchange.
/// The app asks rarely, and a fresh connection carries no state between
/// requests. The helper's signature is checked through its audit token
/// on every message.
public struct HelperXPCDriver: HelperTransport {
    private static let timeout: TimeInterval = 10
    private let requirement: String?

    public init(teamID: String?) {
        requirement = HelperWire.peerRequirement(identifier: HelperWire.helperIdentifier, teamID: teamID)
    }

    public func exchange(_ message: Data) async throws -> Data {
        #if os(macOS)
        guard let requirement else { throw HelperTransportError.unsignedBuild }
        let connection = NSXPCConnection(machServiceName: HelperWire.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        defer { connection.invalidate() }

        let reply = ReplyOnce()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reply.wait(continuation)
                // Cancelled before waiting: onCancel found nothing to resume.
                guard !Task.isCancelled else { return reply.fail(.cancelled) }

                connection.resume()
                let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                    reply.fail(.unreachable(error.localizedDescription))
                } as? HelperXPCProtocol
                guard let proxy else { return reply.fail(.unreachable("The connection offered no helper interface.")) }

                proxy.exchange(message) { reply.succeed($0) }
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) { reply.fail(.timedOut) }
            }
        } onCancel: {
            reply.fail(.cancelled)
        }
        #else
        throw HelperTransportError.unsupportedPlatform
        #endif
    }
}

/// Resumes the caller once: the reply, the error handler and the timeout race.
private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?

    func wait(_ continuation: CheckedContinuation<Data, any Error>) { lock.withLock { self.continuation = continuation } }

    func succeed(_ data: Data) { take()?.resume(returning: data) }

    func fail(_ error: HelperTransportError) { take()?.resume(throwing: error) }

    private func take() -> CheckedContinuation<Data, any Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

#if os(macOS)
/// The helper's side: a connection is accepted only from code meeting the
/// app's requirement, checked before any message is read.
public final class HelperXPCListener: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener(machServiceName: HelperWire.machServiceName)
    private let requirement: String
    private let handler: HelperRequestHandler

    public init(requirement: String, handler: HelperRequestHandler) {
        self.requirement = requirement
        self.handler = handler
    }

    /// Serves requests until launchd stops the helper.
    public func run() -> Never {
        listener.delegate = self
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.resume()
        dispatchMain()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.exportedObject = HelperExport(handler: handler)
        connection.resume()
        return true
    }
}

private final class HelperExport: NSObject, HelperXPCProtocol {
    private let handler: HelperRequestHandler

    init(handler: HelperRequestHandler) { self.handler = handler }

    func exchange(_ message: Data, withReply reply: @escaping @Sendable (Data) -> Void) { reply(handler.reply(to: message)) }
}
#endif

public enum HelperRegistrationStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    /// Registered, waiting for the person in System Settings > Login Items.
    case requiresApproval
    /// The daemon's property list is not in this app bundle.
    case notFound
    /// A status newer than this build knows.
    case unknown
}

public protocol HelperRegistering: Sendable {
    func status() -> HelperRegistrationStatus
    func register() throws
    func unregister() async throws
    func openApprovalSettings()
}

/// Registers the bundled launch daemon with `SMAppService`; launchd starts
/// it on demand when the app connects.
public struct HelperRegistrationDriver: HelperRegistering {
    public init() {}

    public func status() -> HelperRegistrationStatus {
        #if os(macOS)
        switch SMAppService.daemon(plistName: HelperWire.daemonPlistName).status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
        #else
        .notFound
        #endif
    }

    public func register() throws {
        #if os(macOS)
        try SMAppService.daemon(plistName: HelperWire.daemonPlistName).register()
        #else
        throw HelperTransportError.unsupportedPlatform
        #endif
    }

    public func unregister() async throws {
        #if os(macOS)
        try await SMAppService.daemon(plistName: HelperWire.daemonPlistName).unregister()
        #else
        throw HelperTransportError.unsupportedPlatform
        #endif
    }

    public func openApprovalSettings() {
        #if os(macOS)
        SMAppService.openSystemSettingsLoginItems()
        #endif
    }
}
