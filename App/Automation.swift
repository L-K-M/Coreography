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
        if url.isFileURL {
            guard url.pathExtension.lowercased() == Recording.fileExtension else {
                showDashboard()
                return model.reportRecordingFailure("Coreography opens only its recordings; \(url.lastPathComponent) is not one")
            }
            return openRecording(url)
        }
        Task {
            let command = await model.open(url)
            if command == .toggleHUD { return hud.toggle() }
            // A refusal is shown in the window, so it opens too.
            showDashboard()
        }
    }

    /// A `.coreotrace` handed to the app (Finder, the Dock or Open Recording…).
    func openRecording(_ url: URL) {
        Task {
            let data = await Task.detached { () -> Data? in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= Recording.maximumBytes else { return nil }
                return try? Data(contentsOf: url)
            }.value
            showDashboard()
            guard let data else {
                model.reportRecordingFailure("The recording could not be read")
                return
            }
            await model.openRecording(data, fileName: url.deletingPathExtension().lastPathComponent)
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
    /// Asynchronous work quitting waits for, such as writing buffered history.
    static var beforeTerminate: (@MainActor @Sendable () async -> Void)?
    /// A stuck disk must not stop the app from quitting.
    private static let terminationGrace: Duration = .seconds(3)
    private static var terminationAnswered = false
    private static var terminationStarted = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A second Quit while the work runs waits with the first instead of cutting it off.
        if Self.terminationStarted, !Self.terminationAnswered { return .terminateLater }
        guard let work = Self.beforeTerminate else { return .terminateNow }
        Self.terminationStarted = true
        Self.beforeTerminate = nil
        // Whichever finishes first, the work or the grace period, lets the app quit.
        Task { @MainActor in
            await work()
            Self.answerTermination()
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.terminationGrace)
            Self.answerTermination()
        }
        return .terminateLater
    }

    private static func answerTermination() {
        guard !terminationAnswered else { return }
        terminationAnswered = true
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }

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
