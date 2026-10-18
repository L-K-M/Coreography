import SwiftUI
import CoreographyServices

@main
@MainActor
private struct CoreographyApp: App {
    @State private var dashboard: DashboardModel
    @State private var hud: HUDController

    /// One sampler for every surface, running from launch, so the menu bar
    /// extra stays live while the window is closed.
    init() {
        let model = DashboardModel(notifier: AlertNotifications(), history: HistoryRecorder.makeDefault())
        model.start()
        _dashboard = State(initialValue: model)
        _hud = State(initialValue: HUDController(model: model))
    }

    var body: some Scene {
        Window("Coreography", id: "dashboard") {
            DashboardView(model: dashboard)
        }
        .defaultSize(width: 1120, height: 900)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(hud.isShown ? "Hide HUD" : "Show HUD") { hud.toggle() }
                    .keyboardShortcut("h", modifiers: [.command, .option])
            }
        }

        MenuBarExtra {
            MenuBarView(model: dashboard, hud: hud)
        } label: {
            MenuBarLabel(model: dashboard)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: dashboard)
        }
    }
}
