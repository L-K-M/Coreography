import Foundation
import CoreographyDrivers

/// Whether macOS starts Coreography when the person logs in.
public enum LoginStart: Equatable, Sendable {
    case off
    case on
    /// Waiting for the person in System Settings > Login Items.
    case awaitingApproval
    /// macOS cannot start this copy of the app.
    case unavailable
}

public struct LoginItemFailure: Error, Equatable, Sendable {
    public let message: String
}

/// Coreography's own login item. Turning it on or off twice does nothing
/// the second time, as macOS refuses to remove what it never registered.
public struct LoginItem: Sendable {
    private let registration: any LoginItemRegistering

    public init() { self.init(registration: LoginItemDriver()) }

    init(registration: any LoginItemRegistering) { self.registration = registration }

    public func state() -> LoginStart {
        switch registration.status() {
        case .notRegistered: .off
        case .enabled: .on
        case .requiresApproval: .awaitingApproval
        case .notFound, .unknown: .unavailable
        }
    }

    public func enable() throws(LoginItemFailure) {
        guard !isRegistered else { return }
        do {
            try registration.register()
        } catch {
            throw LoginItemFailure(message: "macOS would not start Coreography at login: \(error.localizedDescription)")
        }
    }

    public func disable() async throws(LoginItemFailure) {
        guard isRegistered else { return }
        do {
            try await registration.unregister()
        } catch {
            throw LoginItemFailure(message: "macOS would not stop starting Coreography at login: \(error.localizedDescription)")
        }
    }

    public func openSettings() { registration.openSettings() }

    private var isRegistered: Bool { [.on, .awaitingApproval].contains(state()) }
}
