import Foundation

/// The privileged helper's whole vocabulary (plan: a deliberately tiny XPC
/// interface). A request is a typed value; nothing in it names a command,
/// a path or an argument list, so the helper has nothing to execute.
///
/// ```text
/// app ──HelperRequest (JSON)──> XPC, each side checks the other's signature ──> helper (root)
///     <──HelperReply (JSON)───
/// ```
public enum HelperRequest: Codable, Equatable, Sendable {
    /// Asks for the helper's protocol version, so an outdated helper is noticed.
    case hello
}

public enum HelperReply: Codable, Equatable, Sendable {
    case hello(protocolVersion: Int)
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
    public static let protocolVersion = 1
    /// Larger messages are refused before they are decoded.
    static let maximumMessageBytes = 64 * 1024

    public static func encode(_ value: some Encodable) -> Data {
        // Encoding these plain enums cannot fail; an empty message is refused as malformed.
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws(HelperWireError) -> Value {
        guard data.count <= maximumMessageBytes else { throw .tooLarge }
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
    public init() {}

    public func reply(to message: Data) -> Data {
        let request: HelperRequest
        do {
            request = try HelperWire.decode(HelperRequest.self, from: message)
        } catch .tooLarge {
            return HelperWire.encode(HelperReply.refused("The request is larger than \(HelperWire.maximumMessageBytes) bytes."))
        } catch {
            return HelperWire.encode(HelperReply.refused("The request is not one the helper understands."))
        }

        switch request {
        case .hello: return HelperWire.encode(HelperReply.hello(protocolVersion: HelperWire.protocolVersion))
        }
    }
}
