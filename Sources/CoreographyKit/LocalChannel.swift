import Foundation
import CoreographyDrivers

/// The connecting process as the kernel reports it.
public struct ChannelPeer: Equatable, Sendable {
    public let uid: UInt32
    public let pid: Int32
}

/// A line-oriented local connection between Coreography and its own CLI.
public final class LocalChannel: @unchecked Sendable {
    private let connection: LocalSocketConnection

    fileprivate init(_ connection: LocalSocketConnection) { self.connection = connection }

    public var peer: ChannelPeer? { connection.peer.map { ChannelPeer(uid: $0.uid, pid: $0.pid) } }

    /// nil once the other side has closed.
    public func readLine() async throws -> String? { try await connection.readLine() }

    public func write(_ line: String) throws { try connection.write(line) }

    public func close() { connection.close() }
}

public enum LocalChannelError: Error, Equatable, CustomStringConvertible, Sendable {
    /// The listener was closed; waiting for clients ends.
    case closed
    /// Another live listener, such as a second copy of the app, holds the endpoint.
    case inUse

    public var description: String {
        switch self {
        case .closed: "the listener was closed"
        case .inUse: "another copy of Coreography already listens there"
        }
    }
}

/// Listens on a socket inside a directory only this user can open.
public final class LocalChannelListener: @unchecked Sendable {
    private static let directoryPermissions = 0o700
    private let listener: LocalSocketListener

    public init(path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: Self.directoryPermissions]
        )
        try FileManager.default.setAttributes([.posixPermissions: Self.directoryPermissions], ofItemAtPath: directory.path)
        do {
            listener = try LocalSocketListener(path: path)
        } catch LocalSocketError.inUse {
            throw LocalChannelError.inUse
        }
    }

    public func accept() async throws -> LocalChannel {
        do {
            return LocalChannel(try await listener.accept())
        } catch LocalSocketError.closed {
            throw LocalChannelError.closed
        }
    }

    public func close() { listener.close() }
}

public enum LocalChannelClient {
    public static func connect(path: String) throws -> LocalChannel {
        LocalChannel(try LocalSocketClient.connect(path: path))
    }
}

/// Where the app listens for its MCP bridge.
public enum MCPEndpoint {
    public static var defaultPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coreography/mcp.sock").path
    }
}
