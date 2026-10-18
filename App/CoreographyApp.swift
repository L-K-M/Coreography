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
    @State private var openingRecording = false

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
    }

    var body: some Scene {
        Window("Coreography", id: "dashboard") {
            DashboardView(model: dashboard, hud: hud)
                .modifier(MCPApprovalAlert(access: mcpAccess))
                .fileImporter(isPresented: $openingRecording, allowedContentTypes: [.coreographyRecording]) { result in
                    // The app is not sandboxed, so a picked file is readable as is.
                    if case .success(let url) = result { automation.openRecording(url) }
                }
        }
        .defaultSize(width: 1120, height: 900)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(hud.isShown ? "Hide HUD" : "Show HUD") { hud.toggle() }
                    .keyboardShortcut("h", modifiers: [.command, .option])
                Button("Change HUD Detail") { hud.cycleDensity() }
                    .keyboardShortcut("j", modifiers: [.command, .option])
                Button("Open Recording…") { openingRecording = true }
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
            SettingsView(model: dashboard, mcpAccess: mcpAccess, hud: hud)
        }
    }
}
