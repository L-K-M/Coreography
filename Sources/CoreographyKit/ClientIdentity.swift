import Foundation
import CoreographyDrivers

/// The app behind a local client, as Coreography itself determined it
/// from the process tree: never from a name the client sent (plan: MCP
/// access; client-provided names are display metadata, never authentication).
public struct ClientIdentity: Codable, Hashable, Sendable {
    /// What approval binds to: "team:<team>/<identifier>" for team-signed
    /// apps, which survives updates and moves; otherwise "path:<executable>".
    public let key: String
    public let displayName: String
    /// Shown when asking for approval: the signer or the path.
    public let detail: String

    public init(key: String, displayName: String, detail: String) {
        self.key = key
        self.displayName = displayName
        self.detail = detail
    }
}

/// Walks up from a connecting process to the app that launched it.
///
/// ```text
/// Claude.app ─> node ─> coreo mcp --stdio ─socket─> Coreography
///   ^ first ancestor inside an .app bundle: its outermost bundle is the client
/// ```
public struct ClientIdentityResolver: Sendable {
    /// A process tree deeper than this is not a launch chain.
    private static let maximumDepth = 16
    private static let launchdPID: Int32 = 1
    private static let bundleSuffix = ".app"
    private let reader: any PeerProcessReading

    public init() { self.init(reader: PeerProcessDriver()) }

    init(reader: any PeerProcessReading) { self.reader = reader }

    /// The peer's launching app, or nil when its tree cannot be read.
    public func identity(ofPeer pid: Int32) -> ClientIdentity? {
        guard let peer = reader.process(pid) else { return nil }
        var current = peer.parentPID
        var topmost: RawPeerProcess?
        for _ in 0..<Self.maximumDepth {
            guard current > Self.launchdPID, let process = reader.process(current) else { break }
            if let path = process.path, let bundle = Self.outermostBundle(path) {
                return appIdentity(bundle: bundle)
            }
            topmost = process
            current = process.parentPID
        }
        // No app ancestor: a launch agent, ssh or another daemon tree.
        guard let path = (topmost ?? peer).path else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return ClientIdentity(key: "path:\(path)", displayName: name, detail: path)
    }

    private func appIdentity(bundle: String) -> ClientIdentity {
        let name = String(URL(fileURLWithPath: bundle).lastPathComponent.dropLast(Self.bundleSuffix.count))
        let signing = reader.signing(path: bundle)
        if let team = signing.teamID, let identifier = signing.identifier {
            return ClientIdentity(key: "team:\(team)/\(identifier)", displayName: name, detail: "\(identifier), team \(team)")
        }
        if signing.signature == .apple, let identifier = signing.identifier {
            return ClientIdentity(key: "apple:\(identifier)", displayName: name, detail: "\(identifier), signed by Apple")
        }
        return ClientIdentity(key: "path:\(bundle)", displayName: name, detail: "\(bundle), not signed by a developer team")
    }

    /// `/Applications/Foo.app/Contents/Helpers/Bar.app/…/bar` gives `/Applications/Foo.app`.
    static func outermostBundle(_ path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.count > bundleSuffix.count && $0.hasSuffix(bundleSuffix) }) else {
            return nil
        }
        return components[...index].joined(separator: "/")
    }
}
