import Foundation

/// The privileged helper's whole vocabulary (plan: a deliberately tiny XPC
/// interface). A request is a typed value; nothing in it names a command,
/// a path or an argument list, so the helper has nothing to execute.
///
/// ```text
/// app ──HelperRequest (JSON)──> XPC, each side checks the other's signature ──> helper (root)
///     <──HelperReply (JSON)───
/// ```
/// A message on the wire; larger ones are refused before they are decoded.
public protocol HelperMessage: Codable, Sendable {
    static var maximumBytes: Int { get }
}

public enum HelperRequest: HelperMessage, Equatable {
    public static let maximumBytes = 64 * 1024

    /// Asks for the helper's protocol version, so an outdated helper is noticed.
    case hello
    /// Counters of processes the app may not read itself, such as other
    /// users'. Only numbers come back: no names, paths or arguments.
    case processCounters(pids: [Int32])
}

public enum HelperReply: HelperMessage, Equatable {
    /// Room for every process at a few hundred bytes each.
    public static let maximumBytes = 8 * 1024 * 1024

    case hello(protocolVersion: Int)
    /// One entry per process the helper could read; exited ones are left out.
    case processCounters([IdentifiedProcessCounters])
    /// The helper read the message but will not act on it.
    case refused(String)
}

public enum HelperWireError: Error, Equatable, Sendable {
    case tooLarge
    case malformed
}

/// Names and limits both sides of the helper connection share.
public enum HelperWire {
    public static let machServiceName = "ch.lkmc.Coreography.helper"
    /// The launchd property list in Contents/Library/LaunchDaemons.
    public static let daemonPlistName = "ch.lkmc.Coreography.helper.plist"
    public static let appIdentifier = "ch.lkmc.Coreography"
    public static let helperIdentifier = "ch.lkmc.Coreography.helper"
    public static let protocolVersion = 2
    /// More PIDs per request are refused; a Mac rarely runs this many processes.
    public static let maximumPIDs = 4096

    public static func encode(_ value: some Encodable) -> Data {
        // Encoding these plain enums cannot fail; an empty message is refused as malformed.
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    public static func decode<Value: HelperMessage>(_ type: Value.Type, from data: Data) throws(HelperWireError) -> Value {
        guard data.count <= Value.maximumBytes else { throw .tooLarge }
        guard let value = try? JSONDecoder().decode(type, from: data) else { throw .malformed }
        return value
    }

    /// The code requirement one side sets on the other: an Apple-issued
    /// certificate of the same team, and the expected identifier. Nil for
    /// a build without a team, such as an ad-hoc one: its identifier alone
    /// could be claimed by anyone, so no connection is made.
    ///
    /// Example: `anchor apple generic and identifier "ch.lkmc.Coreography"
    /// and certificate leaf[subject.OU] = "AB12CD34EF"`.
    public static func peerRequirement(identifier: String, teamID: String?) -> String? {
        // Team IDs are ten upper-case letters or digits and identifiers are
        // reverse-DNS names; nothing else may reach the requirement text.
        guard let teamID, teamID.wholeMatch(of: /[A-Z0-9]{10}/) != nil,
              identifier.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9.\-]*/) != nil else { return nil }
        return #"anchor apple generic and identifier "\#(identifier)" and certificate leaf[subject.OU] = "\#(teamID)""#
    }
}

/// The helper's side of one exchange: decode, act, encode. Every failure
/// becomes a refusal the app can show; nothing is executed on its behalf.
public struct HelperRequestHandler: Sendable {
    private let readCounters: @Sendable (Int32) -> IdentifiedProcessCounters?

    public init() { self.init(readCounters: ProcessStatisticsDriver.identifiedCounters) }

    init(readCounters: @escaping @Sendable (Int32) -> IdentifiedProcessCounters?) { self.readCounters = readCounters }

    public func reply(to message: Data) -> Data {
        let request: HelperRequest
        do {
            request = try HelperWire.decode(HelperRequest.self, from: message)
        } catch .tooLarge {
            return HelperWire.encode(HelperReply.refused("The request is larger than \(HelperRequest.maximumBytes) bytes."))
        } catch {
            return HelperWire.encode(HelperReply.refused("The request is not one the helper understands."))
        }

        switch request {
        case .hello:
            return HelperWire.encode(HelperReply.hello(protocolVersion: HelperWire.protocolVersion))
        case .processCounters(let pids):
            guard pids.count <= HelperWire.maximumPIDs else {
                return HelperWire.encode(HelperReply.refused("At most \(HelperWire.maximumPIDs) processes per request."))
            }
            // PID 0 is the kernel and negative values name process groups, never one process.
            guard pids.allSatisfy({ $0 > 0 }) else {
                return HelperWire.encode(HelperReply.refused("A process ID must be positive."))
            }
            return HelperWire.encode(HelperReply.processCounters(Set(pids).sorted().compactMap(readCounters)))
        }
    }
}
