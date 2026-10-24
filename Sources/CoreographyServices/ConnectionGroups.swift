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
    /// Free text matches the app, process, address, resolved name or port;
    /// all words must match.
    static func apps(
        in snapshot: CapturedConnections, processes: CapturedProcesses?, matching filter: String,
        serverNames: [String: String] = [:]
    ) -> [AppConnections] {
        let names = processes.map(ProcessGroups.appNames) ?? [:]
        let words = filter.split(whereSeparator: \.isWhitespace).map(String.init)
        var byApp: [String: [CapturedConnection]] = [:]
        for connection in snapshot.connections {
            let app = names[connection.process] ?? connection.processName
            guard words.allSatisfy({ matches(connection, app: app, word: $0, serverNames: serverNames) }) else { continue }
            byApp[app, default: []].append(connection)
        }

        return byApp.map { app, connections in
            let listening = connections.filter(\.isListening).sorted { $0.local.port < $1.local.port }
            // Plan: grouped app, then domain, then server. Unresolved
            // addresses group under themselves, beside resolved peers.
            let connected = connections.filter { !$0.isListening && $0.remote != nil }.sorted {
                (serverSort($0, names: serverNames)) < (serverSort($1, names: serverNames))
            }
            return AppConnections(
                app: app, listening: listening, connected: connected,
                other: connections.count - listening.count - connected.count
            )
        }
        .sorted { ($0.listening.count + $0.connected.count, $1.app) > ($1.listening.count + $1.connected.count, $0.app) }
    }

    private static func serverSort(_ connection: CapturedConnection, names: [String: String]) -> (String, String, UInt16) {
        let server = connection.remote.flatMap { names[$0.address] } ?? connection.remote?.address ?? ""
        return (DomainName.domain(of: server), server, connection.remote?.port ?? 0)
    }

    private static func matches(
        _ connection: CapturedConnection, app: String, word: String, serverNames: [String: String]
    ) -> Bool {
        let fields = [
            app, connection.processName, String(connection.process.pid),
            connection.local.address, String(connection.local.port),
            connection.remote?.address ?? "", connection.remote.map { String($0.port) } ?? "",
            connection.remote.flatMap { serverNames[$0.address] } ?? ""
        ]
        return fields.contains { $0.localizedCaseInsensitiveContains(word) }
    }
}

/// An approximate grouping key: the last two labels, or three under a
/// country-code second level like `co.uk`. Raw addresses answer themselves.
/// shortcut: not public-suffix data; use that when exact registration boundaries matter.
enum DomainName {
    /// Second-level names countries commonly nest domains under.
    private static let secondLevel: Set<String> = [
        "ac", "co", "com", "edu", "gov", "me", "mil", "ne", "net", "or", "org", "sch"
    ]

    static func domain(of host: String) -> String {
        guard !host.contains(":") else { return host }
        let labels = host.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .split(separator: ".")
        guard labels.count >= 2 else { return host.lowercased() }
        // An address literal is its own group; it names no domain.
        guard labels.contains(where: { !$0.allSatisfy(\.isNumber) }) else { return host }
        var keep = 2
        if labels.last!.count == 2, labels.count >= 3, secondLevel.contains(String(labels[labels.count - 2])) {
            keep = 3
        }
        return labels.suffix(keep).joined(separator: ".")
    }
}
