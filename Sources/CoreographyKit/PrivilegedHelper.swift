import Foundation
import CoreographyDrivers

/// Where the optional privileged helper stands (plan: the approval state
/// is always visible).
public enum HelperState: Equatable, Sendable {
    /// Without a Developer ID team, macOS will not run the helper and no
    /// connection to it could be trusted.
    case needsSignedBuild
    /// The daemon definition is missing from this copy of the app.
    case missingFromApp
    case notInstalled
    case awaitingApproval
    case ready
    /// It answered with another protocol version than this app speaks.
    case outdated(protocolVersion: Int)
    case notResponding(String)
}

public enum HelperFailure: Error, Equatable, Sendable {
    case needsSignedBuild
    case system(String)
}

/// The optional root helper: registration through launchd and the typed
/// requests it answers. Declining it costs only restricted readings.
public actor PrivilegedHelper {
    private let registration: any HelperRegistering
    private let transport: any HelperTransport
    private let isTeamSigned: Bool

    public init() {
        let teamID = CodeSignatureReader.signing(path: Bundle.main.executablePath ?? "").teamID
        self.init(registration: HelperRegistrationDriver(), transport: HelperXPCDriver(teamID: teamID), teamID: teamID)
    }

    init(registration: any HelperRegistering, transport: any HelperTransport, teamID: String?) {
        self.registration = registration
        self.transport = transport
        isTeamSigned = HelperWire.peerRequirement(identifier: HelperWire.appIdentifier, teamID: teamID) != nil
    }

    /// Registration first; an enabled helper must also answer a hello in the expected version.
    public func state() async -> HelperState {
        guard isTeamSigned else { return .needsSignedBuild }
        switch registration.status() {
        case .notFound: return .missingFromApp
        case .notRegistered: return .notInstalled
        case .requiresApproval: return .awaitingApproval
        case .enabled: break
        }

        switch await send(.hello) {
        case .reply(.hello(let version)) where version == HelperWire.protocolVersion: return .ready
        case .reply(.hello(let version)): return .outdated(protocolVersion: version)
        case .reply(.refused(let reason)): return .notResponding(reason)
        case .failed(let reason): return .notResponding(reason)
        }
    }

    /// Registers the daemon; macOS then asks the person to approve it in Login Items.
    public func install() throws(HelperFailure) {
        guard isTeamSigned else { throw .needsSignedBuild }
        do { try registration.register() } catch { throw .system(error.localizedDescription) }
    }

    public func remove() async throws(HelperFailure) {
        do { try await registration.unregister() } catch { throw .system(error.localizedDescription) }
    }

    public func openApprovalSettings() { registration.openApprovalSettings() }

    private enum Exchange {
        case reply(HelperReply)
        case failed(String)
    }

    private func send(_ request: HelperRequest) async -> Exchange {
        do {
            let message = try await transport.exchange(HelperWire.encode(request))
            return .reply(try HelperWire.decode(HelperReply.self, from: message))
        } catch let error as HelperTransportError {
            return .failed(Self.describe(error))
        } catch is HelperWireError {
            return .failed("Its answer could not be read.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func describe(_ error: HelperTransportError) -> String {
        switch error {
        case .unsupportedPlatform: "The helper requires macOS."
        case .unsignedBuild: "This build has no Developer ID team to check the helper against."
        case .unreachable(let detail): detail
        case .timedOut: "It did not answer in time."
        }
    }
}
