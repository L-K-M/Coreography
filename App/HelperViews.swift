import AppKit
import SwiftUI
import CoreographyServices

/// Settings > Privileged helper: opt-in, removable, its state always shown.
struct HelperSection: View {
    let access: HelperAccess

    var body: some View {
        Section("Privileged helper") {
            if let state = access.state {
                Text(Self.summary(state))
                actions(for: state)
            } else {
                Text("Checking…")
            }
            if let problem = access.problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            Text("The helper runs as root to read other users' processes. Everything else works without it, and it never lifts privacy permissions or System Integrity Protection.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await access.refresh() }
        // Approving happens in System Settings; read the state again on return,
        // unless an install or removal is running and will refresh when done.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !access.isBusy else { return }
            Task { await access.refresh() }
        }
    }

    @ViewBuilder
    private func actions(for state: HelperInstallState) -> some View {
        switch state {
        case .needsSignedBuild, .missingFromApp:
            EmptyView()
        case .notInstalled:
            Button("Install Helper…") { Task { await access.install() } }
                .disabled(access.isBusy)
        case .awaitingApproval:
            HStack {
                Button("Open Login Items…") { Task { await access.openApprovalSettings() } }
                removeButton
            }
        case .ready, .outdated, .notResponding:
            removeButton
        }
    }

    private var removeButton: some View {
        Button("Remove Helper", role: .destructive) { Task { await access.remove() } }
            .disabled(access.isBusy)
    }

    private static func summary(_ state: HelperInstallState) -> LocalizedStringKey {
        switch state {
        case .needsSignedBuild: "This build is not signed with a Developer ID, so macOS will not run the helper."
        case .missingFromApp: "The helper is missing from this copy of Coreography. Reinstall the app."
        case .notInstalled: "Not installed."
        case .awaitingApproval: "Waiting for your approval in System Settings > General > Login Items."
        case .ready: "Installed and answering."
        case .outdated(let version): "The installed helper speaks version \(version). Remove it, then install it again."
        case .notResponding(let reason): "Installed, but not answering. \(reason)"
        }
    }
}
