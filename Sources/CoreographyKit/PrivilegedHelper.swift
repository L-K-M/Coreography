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
    /// How long to stay quiet after the helper was found unavailable, so a
    /// declined helper costs one status check a minute, not one per sample.
    private static let unavailableBackoff: Duration = .seconds(60)

    private let registration: any HelperRegistering
    private let transport: any HelperTransport
    private let isTeamSigned: Bool
    /// Only the app may connect; the helper refuses the CLI's identifier anyway.
    private let isApp: Bool
    private let now: @Sendable () -> ContinuousClock.Instant
    private var quietUntil: ContinuousClock.Instant?
    private var enabledUntil: ContinuousClock.Instant?

    /// One instance for Settings and the sampler, so an install or removal
    /// is seen by both at once.
    public static let shared = PrivilegedHelper()

    private init() {
        let signing = CodeSignatureReader.signing(path: Bundle.main.executablePath ?? "")
        self.init(
            registration: HelperRegistrationDriver(), transport: HelperXPCDriver(teamID: signing.teamID),
            teamID: signing.teamID, identifier: signing.identifier
        )
    }

    init(
        registration: any HelperRegistering, transport: any HelperTransport, teamID: String?,
        identifier: String? = HelperWire.appIdentifier, now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.now = now
        self.registration = registration
        self.transport = transport
        isTeamSigned = HelperWire.peerRequirement(identifier: HelperWire.appIdentifier, teamID: teamID) != nil
        isApp = identifier == HelperWire.appIdentifier
    }

    /// Registration first; an enabled helper must also answer a hello in the expected version.
    public func state() async -> HelperState {
        guard isTeamSigned else { return .needsSignedBuild }
        switch registration.status() {
        case .notFound: return .missingFromApp
        case .notRegistered: return .notInstalled
        case .requiresApproval: return .awaitingApproval
        case .unknown: return .notResponding("macOS reported a registration state this version does not know.")
        case .enabled: break
        }

        switch await send(.hello) {
        case .reply(.hello(let version)) where version == HelperWire.protocolVersion:
            // Seen answering: the sampler need not wait out an earlier quiet minute.
            quietUntil = nil
            return .ready
        case .reply(.hello(let version)): return .outdated(protocolVersion: version)
        case .reply(.refused(let reason)): return .notResponding(reason)
        case .reply(.processCounters): return .notResponding("Its answer did not match the request.")
        case .failed(let reason): return .notResponding(reason)
        }
    }

    /// Counters for processes the app cannot read itself; nil while the
    /// helper is not installed, approved and answering.
    func counters(for pids: [Int32]) async -> [IdentifiedProcessCounters]? {
        guard isTeamSigned, isApp, !pids.isEmpty else { return nil }
        if let quietUntil, now() < quietUntil { return nil }

        // The registration is read again at most once a minute.
        if enabledUntil.map({ now() >= $0 }) ?? true {
            guard registration.status() == .enabled else { return unavailable() }
            enabledUntil = now() + Self.unavailableBackoff
        }

        switch await send(.processCounters(pids: Array(pids.prefix(HelperWire.maximumPIDs)))) {
        case .reply(.processCounters(let counters)): return counters
        // Answering, just not for these processes: no reason to go quiet.
        case .reply(.refused): return []
        case .reply(.hello), .failed: return unavailable()
        }
    }

    private func unavailable() -> [IdentifiedProcessCounters]? {
        quietUntil = now() + Self.unavailableBackoff
        enabledUntil = nil
        return nil
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
        case .cancelled: "The request was cancelled."
        }
    }
}
