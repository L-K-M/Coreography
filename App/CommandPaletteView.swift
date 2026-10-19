import AppKit
import SwiftUI
import CoreographyServices

/// Command-Shift-P: every action by name (plan: command palette). Typing
/// narrows the list, the arrow keys move, Return runs the highlighted or
/// first available entry and Escape closes. Unavailable entries stay
/// listed with their reason.
struct CommandPaletteView: View {
    let model: DashboardModel
    let hud: HUDController
    /// Process actions confirm in the window, as from the menus.
    let confirm: (ProcessActionRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var highlighted: PaletteEntry.ID?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let results = CommandPalette.matches(query, in: model.paletteEntries)
        VStack(spacing: 0) {
            TextField("Type a command", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($fieldFocused)
                .onSubmit { run(results.first { $0.id == highlighted } ?? results.first { $0.unavailableReason == nil }) }
                .onKeyPress(.downArrow) { move(1, in: results) }
                .onKeyPress(.upArrow) { move(-1, in: results) }

            Divider()

            List(results, selection: $highlighted) { entry in
                HStack {
                    Text(entry.title)
                    Spacer()
                    if let reason = entry.unavailableReason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(entry.unavailableReason == nil ? .primary : .secondary)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { run(entry) }
                .accessibilityHint(entry.unavailableReason ?? "")
            }
            .listStyle(.plain)
        }
        .frame(width: 520, height: 380)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { highlighted = nil }
        .onExitCommand { dismiss() }
    }

    private func move(_ step: Int, in results: [PaletteEntry]) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        let current = results.firstIndex { $0.id == highlighted } ?? (step > 0 ? -1 : results.count)
        highlighted = results[min(max(current + step, 0), results.count - 1)].id
        return .handled
    }

    private func run(_ entry: PaletteEntry?) {
        guard let entry, entry.unavailableReason == nil else { return }
        dismiss()
        switch entry.action {
        case .toggleHUD:
            hud.toggle()
        case .openSettings:
            openSettings()
        case .addMarker:
            model.markerPromptShown = true
        case .copySelected:
            guard let process = model.selectedProcess else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.copyText(for: process), forType: .string)
        case .processAction(let action) where action != .resume:
            guard let process = model.selectedProcess else { return }
            confirm(model.actionRequest(for: process, action: action))
        default:
            Task { await model.run(entry.action) }
        }
    }
}
