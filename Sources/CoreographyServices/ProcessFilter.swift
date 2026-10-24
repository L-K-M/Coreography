import Foundation
import CoreographyKit

/// A parsed process filter (plan P22). Whitespace separates terms; every
/// term must match. Examples: `safari`, `cpu:>10`, `mem:>1GB`, `disk:>5MB`,
/// `pid:42`, `user:root`, `user:me`, `user:alice`, `#apps`, `#mine`, `#third-party`, `#new`,
/// `#listening`, `#preventing-sleep`, `#rosetta`, `#not-responding`, `port:443`, `file:~/Downloads`.
/// Terms that cannot be evaluated are reported, never silently dropped.
public typealias CapturedAssertions = AssertionSnapshot
public typealias CapturedAssertion = SleepAssertion
public typealias CapturedAssertionEffect = AssertionEffect
public typealias CapturedOpenFiles = OpenFileSnapshot

/// An assertion with the name of the process holding it, when observed.
public struct AssertionHolder: Identifiable, Sendable {
    public var id: String { assertion.id }
    public let assertion: CapturedAssertion
    public let processName: String?
}

/// What the filter knows about processes beyond their samples; each part
/// is nil until its data has been read, and then its terms match nothing.
struct ProcessFacts: Sendable {
    var sockets: SocketFacts?
    /// PIDs holding the Mac or its display awake.
    var sleepPreventers: Set<Int32>?
    /// Open file paths by process.
    var openFiles: [ProcessIdentity: [String]]?
    /// Per-process network rates of the same moment.
    var traffic: CapturedTraffic?
    /// Processes whose event connection has stopped answering.
    var notResponding: Set<ProcessIdentity>?
    /// `cpu:` bounds are typed in the table's scale; this turns a whole-machine share into it.
    var cpuFactor = 1.0
    /// Account names by UID, for the by-user view.
    var accountNames: [UInt32: String] = [:]
    /// Signers by executable path, for the signer column.
    var signers: [String: CapturedSigner] = [:]
}

/// What connection data says about each process, for `#listening` and `port:`.
struct SocketFacts: Sendable {
    let listening: Set<ProcessIdentity>
    /// Every local and remote port of each process's sockets.
    let ports: [ProcessIdentity: Set<UInt16>]
    /// The local ports each process listens on, for the ports column.
    let listeningPorts: [ProcessIdentity: Set<UInt16>]

    init(_ snapshot: CapturedConnections) {
        listening = snapshot.listeningProcesses
        var ports: [ProcessIdentity: Set<UInt16>] = [:]
        var listeningPorts: [ProcessIdentity: Set<UInt16>] = [:]
        for connection in snapshot.connections {
            if connection.local.port != 0 { ports[connection.process, default: []].insert(connection.local.port) }
            if let remote = connection.remote { ports[connection.process, default: []].insert(remote.port) }
            if connection.isListening, connection.local.port != 0 {
                listeningPorts[connection.process, default: []].insert(connection.local.port)
            }
        }
        self.ports = ports
        self.listeningPorts = listeningPorts
    }
}

public struct ProcessFilter: Equatable, Sendable {
    enum Comparison: Equatable, Sendable {
        case greater(Double), greaterOrEqual(Double), less(Double), lessOrEqual(Double), equal(Double)

        func holds(_ value: Double) -> Bool {
            switch self {
            case .greater(let bound): value > bound
            case .greaterOrEqual(let bound): value >= bound
            case .less(let bound): value < bound
            case .lessOrEqual(let bound): value <= bound
            case .equal(let bound): value == bound
            }
        }
    }

    enum Token: String, Sendable {
        case apps, mine, root, thirdParty = "third-party", new, listening, preventingSleep = "preventing-sleep"
        /// Intel code translated on Apple silicon.
        case rosetta
        /// Its UI has ignored the WindowServer across consecutive samples.
        case notResponding = "not-responding"
    }

    enum Term: Equatable, Sendable {
        case text(String)
        case cpu(Comparison)
        case memory(Comparison)
        case disk(Comparison)
        case pid(Int32)
        case user(UInt32)
        /// An account name, matched once the UID's name has been looked up.
        case userName(String)
        case token(Token)
        /// Reverse lookup: processes with a socket on this local or remote port.
        case port(UInt16)
        /// Reverse lookup: processes with an open file whose path contains this.
        case file(String)
    }

    /// Tokens the plan names whose data sources do not exist yet.
    private static let pendingTokens: [String: String] = [
        "exited": "exited processes are listed below the table"
    ]
    private static let byteUnits: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1)]
    // Locations Apple ships system software under; anything else is third-party.
    private static let systemPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"]
    /// Under a system prefix but installed by the person or a package manager.
    private static let localPrefix = "/usr/local/"

    let terms: [Term]
    /// Human-readable notes about terms that were not applied.
    public let issues: [String]

    public static func parse(_ text: String, currentUser: UInt32 = UInt32(getuid())) -> ProcessFilter {
        var terms: [Term] = []
        var issues: [String] = []
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            if word.hasPrefix("#") {
                let name = String(word.dropFirst()).lowercased()
                if let token = Token(rawValue: name) {
                    terms.append(.token(token))
                } else if let reason = pendingTokens[name] {
                    issues.append("Ignored \(word): \(reason)")
                } else {
                    issues.append("Unknown token \(word)")
                }
                continue
            }
            guard let colon = word.firstIndex(of: ":") else {
                terms.append(.text(word))
                continue
            }
            let key = word[..<colon].lowercased()
            let value = String(word[word.index(after: colon)...])
            switch key {
            case "cpu":
                if let comparison = comparison(value, unit: { Double($0.replacingOccurrences(of: "%", with: "")) }) {
                    terms.append(.cpu(comparison))
                } else { issues.append("Unreadable \(word); try cpu:>10") }
            case "mem", "memory":
                if let comparison = comparison(value, unit: bytes) { terms.append(.memory(comparison)) }
                else { issues.append("Unreadable \(word); try mem:>1GB") }
            case "disk":
                if let comparison = comparison(value, unit: { bytes($0.replacingOccurrences(of: "/s", with: "")) }) {
                    terms.append(.disk(comparison))
                } else { issues.append("Unreadable \(word); try disk:>5MB") }
            case "pid":
                if let pid = Int32(value) { terms.append(.pid(pid)) } else { issues.append("Unreadable \(word)") }
            case "file", "path":
                // A path or a file name; ~ means the home folder.
                let expanded = expandingHome(value)
                if expanded.isEmpty { issues.append("Unreadable \(word); try file:~/Downloads") } else { terms.append(.file(expanded)) }
            case "port":
                if let port = UInt16(value), port > 0 { terms.append(.port(port)) } else { issues.append("Unreadable \(word); try port:443") }
            case "user", "uid":
                switch value.lowercased() {
                case "root": terms.append(.user(0))
                case "me", "mine": terms.append(.user(currentUser))
                default:
                    if let uid = UInt32(value) {
                        terms.append(.user(uid))
                    } else if value.isEmpty {
                        issues.append("Unreadable \(word); try user:root, user:me, a UID or an account name")
                    } else if value.allSatisfy({ $0.isASCII && $0.isNumber }) {
                        // Digits past UInt32 are a mistyped UID, not an account name that matches nothing.
                        issues.append("Unreadable \(word); a UID is at most \(UInt32.max)")
                    } else {
                        terms.append(.userName(value))
                    }
                }
            default:
                terms.append(.text(word))
            }
        }
        return ProcessFilter(terms: terms, issues: issues)
    }

    /// `~/Downloads` is the home folder's Downloads; `~name` stays as typed,
    /// since it names another account's home, not this one's plus a suffix.
    static func expandingHome(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return NSHomeDirectory() + path.dropFirst()
    }

    var isEmpty: Bool { terms.isEmpty }
    /// Matching needs connection data, which is read only on demand.
    var usesAssertions: Bool { terms.contains(.token(.preventingSleep)) }

    /// Matching needs account names, looked up off the main thread.
    var usesAccountNames: Bool { terms.contains { if case .userName = $0 { true } else { false } } }

    /// Matching needs the responsiveness probe, read with each process sample.
    var usesResponsiveness: Bool { terms.contains(.token(.notResponding)) }

    /// Matching needs open-file data, read only on demand.
    var usesFiles: Bool { terms.contains { if case .file = $0 { true } else { false } } }

    var usesSockets: Bool {
        terms.contains { term in
            switch term {
            case .token(.listening), .port: true
            default: false
            }
        }
    }
    /// Only free text: a matching app name shows the whole group.
    var isTextOnly: Bool { terms.allSatisfy { if case .text = $0 { true } else { false } } }

    func matchesName(_ name: String) -> Bool {
        terms.allSatisfy { term in
            guard case .text(let text) = term else { return true }
            return name.localizedCaseInsensitiveContains(text)
        }
    }

    /// Unknown readings never match a numeric predicate: they are not zero.
    /// Text also matches the member's app, so `safari cpu:>10` keeps Safari's helpers.
    /// - Parameter facts: connection and assertion data, read on demand.
    func matches(
        _ process: ObservedProcess, isNew: Bool, appName: String? = nil, facts: ProcessFacts = ProcessFacts(),
        currentUser: UInt32 = UInt32(getuid())
    ) -> Bool {
        terms.allSatisfy { term in
            switch term {
            case .text(let text):
                return process.name.localizedCaseInsensitiveContains(text)
                    || appName?.localizedCaseInsensitiveContains(text) == true
                    || String(process.id.pid).contains(text) || String(process.uid).contains(text)
            case .cpu(let comparison):
                return process.cpuPercentOfMachine.numericValue.map { comparison.holds($0 * facts.cpuFactor) } ?? false
            case .memory(let comparison):
                return process.memoryFootprintBytes.numericValue.map(comparison.holds) ?? false
            case .disk(let comparison):
                guard let read = process.diskReadBytesPerSecond.numericValue,
                      let write = process.diskWriteBytesPerSecond.numericValue else { return false }
                return comparison.holds(read + write)
            case .pid(let pid):
                return process.id.pid == pid
            case .user(let uid):
                return process.uid == uid
            case .userName(let name):
                return facts.accountNames[process.uid]?.caseInsensitiveCompare(name) == .orderedSame
            case .token(.apps):
                return ProcessGroups.appBundle(of: process) != nil
            case .token(.mine):
                return process.uid == currentUser
            case .token(.root):
                return process.uid == 0
            case .token(.thirdParty):
                guard let path = process.executablePath else { return false }
                return path.hasPrefix(Self.localPrefix) || !Self.systemPrefixes.contains { path.hasPrefix($0) }
            case .token(.new):
                return isNew
            case .token(.listening):
                return facts.sockets?.listening.contains(process.id) ?? false
            case .token(.preventingSleep):
                return facts.sleepPreventers?.contains(process.id.pid) ?? false
            case .token(.rosetta):
                return process.architecture == .intelTranslated
            case .token(.notResponding):
                return facts.notResponding?.contains(process.id) ?? false
            case .port(let port):
                return facts.sockets?.ports[process.id]?.contains(port) ?? false
            case .file(let path):
                return facts.openFiles?[process.id]?.contains { $0.localizedCaseInsensitiveContains(path) } ?? false
            }
        }
    }

    private static func comparison(_ text: String, unit: (String) -> Double?) -> Comparison? {
        let operators: [(String, (Double) -> Comparison)] = [
            (">=", Comparison.greaterOrEqual), ("<=", Comparison.lessOrEqual),
            (">", Comparison.greater), ("<", Comparison.less), ("=", Comparison.equal)
        ]
        // "nan", "inf" and "1e400" parse as numbers no reading can be compared with.
        func bound(_ text: String) -> Double? { unit(text).flatMap { $0.isFinite ? $0 : nil } }
        for (symbol, make) in operators where text.hasPrefix(symbol) {
            return bound(String(text.dropFirst(symbol.count))).map(make)
        }
        // A bare number means "at least", the common question.
        return bound(text).map(Comparison.greaterOrEqual)
    }

    private static func bytes(_ text: String) -> Double? {
        let upper = text.uppercased()
        for (suffix, scale) in byteUnits where upper.hasSuffix(suffix) {
            return Double(upper.dropLast(suffix.count)).map { $0 * scale }
        }
        return Double(upper)
    }
}
