import SwiftUI
import CoreographyServices

@main
@MainActor
private struct CoreographyApp: App {
    @NSApplicationDelegateAdaptor(AutomationAppDelegate.self) private var appDelegate
    @State private var dashboard: DashboardModel
    @State private var hud: HUDController
    private let automation: AutomationRouter

    /// One sampler for every surface, running from launch, so the menu bar
    /// extra stays live while the window is closed.
    init() {
        let model = DashboardModel(notifier: AlertNotifications(), history: HistoryRecorder.makeDefault())
        model.start()
        let hud = HUDController(model: model)
        _dashboard = State(initialValue: model)
        _hud = State(initialValue: hud)
        automation = AutomationRouter(model: model, hud: hud)
        automation.install()
    }

    var body: some Scene {
        Window("Coreography", id: "dashboard") {
            DashboardView(model: dashboard, hud: hud)
        }
        .defaultSize(width: 1120, height: 900)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(hud.isShown ? "Hide HUD" : "Show HUD") { hud.toggle() }
                    .keyboardShortcut("h", modifiers: [.command, .option])
                Button("Command Palette…") {
                    automation.showDashboard()
                    dashboard.paletteShown = true
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView(model: dashboard, hud: hud)
        } label: {
            MenuBarLabel(model: dashboard, automation: automation)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: dashboard)
        }
    }
}
