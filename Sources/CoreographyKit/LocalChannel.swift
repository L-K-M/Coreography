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
        listener = try LocalSocketListener(path: path)
    }

    public func accept() async throws -> LocalChannel { LocalChannel(try await listener.accept()) }

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
