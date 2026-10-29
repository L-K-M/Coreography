import AppKit
import CoreographyServices

/// Shows or hides the Dock icon for the background mode: hidden while
/// no window is open, shown while one is, so an open window can still
/// be reached with Command-Tab and has its menus.
///
/// ```text
/// presence     windows open   Dock icon
/// window       any            shown
/// background   none           hidden (menu bar only)
/// background   one or more    shown until the last one closes
/// ```
///
/// Windows are read from AppKit rather than from SwiftUI's appear and
/// disappear, which a Settings window kept alive may never report.
@MainActor
final class DockPresence {
    /// Time for a requested window to appear before the icon hides again.
    private static let revealGrace: Duration = .seconds(1)

    private let mode: BackgroundMode
    private var observers: [NSObjectProtocol] = []
    /// While a requested window is on its way, closing the menu bar
    /// extra's panel must not hide the icon it needs.
    private var revealing = false

    init(mode: BackgroundMode) {
        self.mode = mode
        let center = NotificationCenter.default
        let changes: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification
        ]
        observers = changes.map { name in
            // A closing window is still listed until the next turn of the run loop.
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor [weak self] in self?.apply() }
            }
        }
    }

    /// Also called when the presence changes in Settings.
    func apply() {
        let hidden = mode.presence == .background && !hasOpenWindow && !revealing
        set(hidden ? .accessory : .regular)
    }

    /// Shows the Dock icon before opening a window from the menu bar: an
    /// accessory app's new window cannot come to the front. If none
    /// appears, the icon hides again.
    func reveal(_ open: () -> Void) {
        revealing = true
        set(.regular)
        open()
        Task { [weak self] in
            try? await Task.sleep(for: Self.revealGrace)
            self?.revealing = false
            self?.apply()
        }
    }

    /// The dashboard or Settings; the HUD and the menu bar extra are panels.
    private var hasOpenWindow: Bool {
        NSApplication.shared.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled) && !(window is NSPanel)
        }
    }

    private func set(_ policy: NSApplication.ActivationPolicy) {
        let app = NSApplication.shared
        guard app.activationPolicy() != policy else { return }
        app.setActivationPolicy(policy)
        // A window that just brought the Dock icon back comes to the front with it.
        if policy == .regular { app.activate() }
    }
}
