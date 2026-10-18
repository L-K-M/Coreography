import SwiftUI
import CoreographyServices

@main
@MainActor
private struct CoreographyApp: App {
    @State private var dashboard: DashboardModel

    /// One sampler for every surface, running from launch, so the menu bar
    /// extra stays live while the window is closed.
    init() {
        let model = DashboardModel()
        model.start()
        _dashboard = State(initialValue: model)
    }

    var body: some Scene {
        Window("Coreography", id: "dashboard") {
            DashboardView(model: dashboard)
        }
        .defaultSize(width: 1120, height: 900)

        MenuBarExtra {
            MenuBarView(model: dashboard)
        } label: {
            MenuBarLabel(model: dashboard)
        }
        .menuBarExtraStyle(.window)
    }
}
