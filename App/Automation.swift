import AppKit
import SwiftUI
import CoreographyServices

/// Routes `coreography://` links and Shortcuts to the one running model
/// (plan: automation). App Intents run in the app's own process.
@MainActor
final class AutomationRouter {
    /// How long a Shortcut waits for the first samples after launch.
    private static let readyTimeout: Duration = .seconds(5)
    private static let readyPoll: Duration = .milliseconds(100)

    private(set) static var shared: AutomationRouter?
    /// Links that arrived before the app finished building its model.
    private static var pending: [URL] = []

    let model: DashboardModel
    private let hud: HUDController
    /// Only views can open windows; an always-present view supplies this.
    var openDashboard: (() -> Void)?

    init(model: DashboardModel, hud: HUDController) {
        self.model = model
        self.hud = hud
    }

    /// Become the router for links and intents, and handle early links.
    func install() {
        Self.shared = self
        let early = Self.pending
        Self.pending = []
        early.forEach(open)
    }

    static func receive(_ url: URL) {
        guard let shared else { return pending.append(url) }
        shared.open(url)
    }

    func open(_ url: URL) {
        Task {
            let command = await model.open(url)
            if command == .toggleHUD { return hud.toggle() }
            // A refusal is shown in the window, so it opens too.
            showDashboard()
        }
    }

    func showDashboard() {
        NSApp.activate()
        openDashboard?()
    }

    /// The model once it has samples; a Shortcut may have just launched the app.
    static func readyModel() async throws -> DashboardModel {
        guard let model = shared?.model else { throw AutomationIntentError("Coreography is still starting") }
        let deadline = ContinuousClock.now.advanced(by: readyTimeout)
        while model.latest == nil, ContinuousClock.now < deadline { try await Task.sleep(for: readyPoll) }
        guard model.latest != nil else { throw AutomationIntentError(model.collectionError ?? "No readings yet") }
        return model
    }
}

/// Receives links whether or not the window is open.
@MainActor
final class AutomationAppDelegate: NSObject, NSApplicationDelegate {
    /// Work that must finish before the process ends, such as closing the MCP socket.
    static var onTerminate: (() -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(AutomationRouter.receive)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.onTerminate?()
    }
}

struct AutomationIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    init(_ message: String) { self.message = message }

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}
