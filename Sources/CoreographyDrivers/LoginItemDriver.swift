import Foundation
#if os(macOS)
import ServiceManagement
#endif

public enum LoginItemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    /// Registered, waiting for the person in System Settings > Login Items.
    case requiresApproval
    /// macOS cannot find this app to start it.
    case notFound
    /// A status newer than this build knows.
    case unknown
}

public enum LoginItemError: Error, Equatable, Sendable {
    case unsupportedPlatform
}

public protocol LoginItemRegistering: Sendable {
    func status() -> LoginItemStatus
    func register() throws
    func unregister() async throws
    func openSettings()
}

/// Registers the app itself with `SMAppService` so macOS starts it at login.
public struct LoginItemDriver: LoginItemRegistering {
    public init() {}

    public func status() -> LoginItemStatus {
        #if os(macOS)
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .unknown
        }
        #else
        .notFound
        #endif
    }

    public func register() throws {
        #if os(macOS)
        try SMAppService.mainApp.register()
        #else
        throw LoginItemError.unsupportedPlatform
        #endif
    }

    public func unregister() async throws {
        #if os(macOS)
        try await SMAppService.mainApp.unregister()
        #else
        throw LoginItemError.unsupportedPlatform
        #endif
    }

    public func openSettings() {
        #if os(macOS)
        SMAppService.openSystemSettingsLoginItems()
        #endif
    }
}
