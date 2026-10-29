import Foundation
import Observation
import CoreographyKit

public typealias CapturedLoginStart = LoginStart

/// How Coreography shows itself.
public enum AppPresence: String, Sendable {
    /// The window opens at launch and the Dock icon stays.
    case window
    /// Starts at login with only the menu bar extra; the window, and the
    /// Dock icon with it, appears only when the person opens it. Sampling,
    /// alerts, history and the briefing widget keep running.
    case background
}

/// The saved presence and the login item that goes with it.
@MainActor
@Observable
public final class BackgroundMode {
    public nonisolated static let settingKey = "appPresence"

    public private(set) var presence: AppPresence
    /// What macOS will do at the next login; the person may change it in
    /// System Settings, so Settings refreshes it.
    public private(set) var loginStart: CapturedLoginStart
    /// Why the last change to the login item failed, when it did.
    public private(set) var problem: String?

    @ObservationIgnored private let loginItem: LoginItem
    @ObservationIgnored private let defaults: UserDefaults

    public convenience init() { self.init(loginItem: LoginItem(), defaults: .standard) }

    init(loginItem: LoginItem, defaults: UserDefaults) {
        self.loginItem = loginItem
        self.defaults = defaults
        presence = defaults.string(forKey: Self.settingKey).flatMap(AppPresence.init(rawValue:)) ?? .window
        loginStart = loginItem.state()
    }

    /// Running in the background starts at login; the window mode stops
    /// that. The presence is kept even when macOS refuses the login item,
    /// so the menu bar mode still works for this session.
    public func set(_ presence: AppPresence) async {
        self.presence = presence
        defaults.set(presence.rawValue, forKey: Self.settingKey)
        problem = nil
        do {
            switch presence {
            case .background: try loginItem.enable()
            case .window: try await loginItem.disable()
            }
        } catch {
            problem = error.message
        }
        refresh()
    }

    public func refresh() { loginStart = loginItem.state() }

    public func openLoginItems() { loginItem.openSettings() }
}
