import AppKit
import SwiftUI
import Observation
import CoreographyServices

/// Settings > MCP access: the one switch, approved clients and their sessions.
struct MCPAccessSection: View {
    let access: MCPAccess

    var body: some View {
        Section("MCP access") {
            Toggle("Allow MCP clients to read diagnostics", isOn: Binding(
                get: { access.isEnabled }, set: { access.setEnabled($0) }
            ))
            Text("Clients run coreo mcp --stdio. Each app is asked once; it can then read resource use, app and process names and history, never paths, arguments or process control.")
                .font(.caption).foregroundStyle(.secondary)
            if let problem = access.problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            if access.grants.isEmpty {
                Text("No clients approved.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(access.grants) { grant in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(grant.identity.displayName)
                        Text(MCPText.grantDetail(grant, sessions: access.sessions.filter { $0.grantID == grant.id }.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke", role: .destructive) { access.revoke(grant.id) }
                }
            }
        }
    }
}

/// Asks the person about a new client, in the window, with what it will see.
struct MCPApprovalAlert: ViewModifier {
    let access: MCPAccess

    func body(content: Content) -> some View {
        let request = access.pendingApproval
        content.alert(
            request.map { "Allow \($0.identity.displayName) to read Coreography diagnostics?" } ?? "",
            isPresented: Binding(get: { request != nil }, set: { _ in }),
            presenting: request
        ) { request in
            Button("Allow") { access.answer(request.id, allow: true) }
            Button("Don't Allow", role: .cancel) { access.answer(request.id, allow: false) }
        } message: { request in
            Text("\(request.identity.detail)\n\nIt can read resource use, app and process names and history through MCP. It cannot see paths or arguments, quit processes or change settings. Revoke it in Settings > MCP access.")
        }
    }
}

/// Brings the window forward when a client waits for approval.
@MainActor
final class MCPApprovalPresenter {
    private let access: MCPAccess
    private let automation: AutomationRouter

    init(access: MCPAccess, automation: AutomationRouter) {
        self.access = access
        self.automation = automation
        observe()
    }

    private func observe() {
        withObservationTracking {
            if access.pendingApproval != nil {
                automation.showDashboard()
                NSApplication.shared.requestUserAttention(.criticalRequest)
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }
}

private enum MCPText {
    static func grantDetail(_ grant: MCPGrant, sessions: Int) -> String {
        let approved = grant.approvedAt.formatted(date: .abbreviated, time: .shortened)
        let used = grant.lastUsedAt.map { String(localized: ", last used \($0.formatted(date: .abbreviated, time: .shortened))") } ?? ""
        let connected = sessions > 0 ? String(localized: ", \(sessions) connected") : ""
        return String(localized: "\(grant.identity.detail) · approved \(approved)\(used)\(connected)")
    }
}
