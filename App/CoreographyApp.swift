import SwiftUI
import CoreographyServices

@main
@MainActor
private struct CoreographyApp: App {
    @State private var dashboard = DashboardModel()

    var body: some Scene {
        Window("Coreography", id: "dashboard") {
            DashboardView(model: dashboard)
        }
        .defaultSize(width: 1120, height: 760)
    }
}
