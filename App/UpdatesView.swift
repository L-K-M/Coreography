import SwiftUI
import CoreographyServices

/// Settings > Updates: notify only. Coreography links to a newer release;
/// downloading and installing it stay with you.
struct UpdatesSection: View {
    let updates: UpdateChecker

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates daily", isOn: Binding(
                get: { updates.isAutomatic },
                set: { updates.setAutomatic($0) }
            ))
            HStack {
                status
                Spacer()
                Button("Check Now") { Task { await updates.checkNow() } }
                    .disabled(updates.status == .checking)
            }
            if case .available(let release) = updates.status {
                Link("View Coreography \(release.version.description) on GitHub", destination: release.page)
            }
            if let lastChecked = updates.lastChecked {
                Text("Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Coreography asks GitHub for the newest release. It never downloads or installs anything itself.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var status: Text {
        switch updates.status {
        case .notChecked: Text("Not checked yet.")
        case .checking: Text("Checking…")
        case .upToDate: Text("Coreography \(updates.currentVersion) is up to date.")
        case .available(let release): Text("Coreography \(release.version.description) is available. You have \(updates.currentVersion).")
        case .noRelease: Text("No release is published yet.")
        case .failed(let problem): Text("Could not check. \(problem)")
        case .unversioned: Text("This build has no release version to compare.")
        }
    }
}
