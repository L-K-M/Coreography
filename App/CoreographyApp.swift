import SwiftUI
import UniformTypeIdentifiers
import CoreographyServices

@main
@MainActor
private struct CoreographyApp: App {
    @NSApplicationDelegateAdaptor(AutomationAppDelegate.self) private var appDelegate
    @State private var dashboard: DashboardModel
    @State private var hud: HUDController
    private let automation: AutomationRouter
    private let dockTile: DockTileController
    private let mcpAccess: MCPAccess
    private let mcpApproval: MCPApprovalPresenter
    private let helperAccess = HelperAccess()

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
        dockTile = DockTileController(model: model)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let access = MCPAccess(version: version) { model.diagnosticSnapshot() }
        mcpAccess = access
        mcpApproval = MCPApprovalPresenter(access: access, automation: automation)
        AutomationAppDelegate.onTerminate = { access.shutdown() }
        AutomationAppDelegate.beforeTerminate = { await model.stopForQuit() }
    }

    var body: some Scene {
        Window("Coreography", id: "dashboard") {
            DashboardView(model: dashboard, hud: hud)
                .modifier(MCPApprovalAlert(access: mcpAccess))
        }
        .defaultSize(width: 1120, height: 900)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(hud.isShown ? "Hide HUD" : "Show HUD") { hud.toggle() }
                    .keyboardShortcut("h", modifiers: [.command, .control])
                Button("Change HUD Detail") { hud.cycleDensity() }
                    .keyboardShortcut("j", modifiers: [.command, .control])
                // A panel of its own, so it works while the window is closed too.
                Button("Open Recording…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.coreographyRecording]
                    panel.allowsMultipleSelection = false
                    // The app is not sandboxed, so a picked file is readable as is.
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    automation.openRecording(url)
                }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Return to Now") {
                    automation.showDashboard()
                    dashboard.returnToNow()
                }
                .keyboardShortcut("0", modifiers: .command)
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
            SettingsView(model: dashboard, mcpAccess: mcpAccess, hud: hud, helperAccess: helperAccess)
        }
    }
}
