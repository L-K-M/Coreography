import Foundation
import CoreographyKit

public typealias CapturedConnections = ConnectionSnapshot
public typealias CapturedConnection = ConnectionReading
public typealias CapturedTCPState = TCPState
public typealias CapturedTransport = ConnectionTransport
public typealias CapturedEndpoint = ConnectionEndpoint

/// Which detail pane sits under the lanes (plan: Processes, Connections,
/// Startup, Sensors and Recordings tabs; the rest follow).
public enum DetailPane: String, CaseIterable, Identifiable, Sendable {
    case processes, connections, startup, sensors, sessions

    public var id: Self { self }
}

/// One app's sockets for the Connections tab (plan: grouped by app, then
/// server). Listening sockets come first, then connected ones by peer.
public struct AppConnections: Identifiable, Sendable {
    public var id: String { app }
    public let app: String
    public let listening: [CapturedConnection]
    public let connected: [CapturedConnection]
    /// Neither listening nor connected (e.g. bound but idle, or closing); counted, not listed.
    public let other: Int
}

enum ConnectionGroups {
    /// Free text matches the app, process, address or port; all words must match.
    static func apps(
        in snapshot: CapturedConnections, processes: CapturedProcesses?, matching filter: String
    ) -> [AppConnections] {
        let names = processes.map(ProcessGroups.appNames) ?? [:]
        let words = filter.split(whereSeparator: \.isWhitespace).map(String.init)
        var byApp: [String: [CapturedConnection]] = [:]
        for connection in snapshot.connections {
            let app = names[connection.process] ?? connection.processName
            guard words.allSatisfy({ matches(connection, app: app, word: $0) }) else { continue }
            byApp[app, default: []].append(connection)
        }

        return byApp.map { app, connections in
            let listening = connections.filter(\.isListening).sorted { $0.local.port < $1.local.port }
            let connected = connections.filter { !$0.isListening && $0.remote != nil }.sorted {
                ($0.remote?.address ?? "", $0.remote?.port ?? 0) < ($1.remote?.address ?? "", $1.remote?.port ?? 0)
            }
            return AppConnections(
                app: app, listening: listening, connected: connected,
                other: connections.count - listening.count - connected.count
            )
        }
        .sorted { ($0.listening.count + $0.connected.count, $1.app) > ($1.listening.count + $1.connected.count, $0.app) }
    }

    private static func matches(_ connection: CapturedConnection, app: String, word: String) -> Bool {
        let fields = [
            app, connection.processName, String(connection.process.pid),
            connection.local.address, String(connection.local.port),
            connection.remote?.address ?? "", connection.remote.map { String($0.port) } ?? ""
        ]
        return fields.contains { $0.localizedCaseInsensitiveContains(word) }
    }
}
