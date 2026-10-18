import SwiftUI
import CoreographyServices

/// What leaves the Mac, stated wherever a question can be asked (plan: show
/// the provider and the data-sharing scope).
private let sharingNotice = String(localized: """
    Questions and requested readings (resource use, app and process names, PIDs, sleep history and sleep-preventing assertion types, never executable paths or process arguments) \
    go directly to Anthropic. Calls happen only when you ask.
    """)

/// Ask Coreography: optional, collapsed by default, answered from the same
/// read-only diagnostic tools as MCP.
struct AskPanel: View {
    @Bindable var model: DashboardModel
    @State private var question = ""

    var body: some View {
        DisclosureGroup("Ask Coreography") {
            VStack(alignment: .leading, spacing: 8) {
                if model.hasProviderKey {
                    HStack {
                        TextField("Why is my Mac slow?", text: $question)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.ask(question) }
                        if case .asking = model.askState {
                            Button("Cancel") { model.cancelAsk() }
                        } else {
                            Button("Ask") { model.ask(question) }
                                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    answer
                } else {
                    Text("Add an Anthropic API key in Settings to ask questions in plain language.")
                    SettingsLink { Text("Open Settings…") }
                }
                Text(sharingNotice).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .task { await model.refreshProviderKey() }
    }

    @ViewBuilder
    private var answer: some View {
        switch model.askState {
        case .idle:
            EmptyView()
        case .asking:
            ProgressView("Asking…").controlSize(.small)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        case .answered(let answer):
            Text(answer.text).textSelection(.enabled)
            if !answer.toolCalls.isEmpty {
                Text("Evidence read: " + answer.toolCalls.map { $0.name + $0.arguments + ($0.failed ? " (failed)" : "") }
                    .joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Snapshot \(answer.snapshotID.uuidString.prefix(8)); later readings are not included.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Settings: the provider key lives only in the Keychain.
struct SettingsView: View {
    @Bindable var model: DashboardModel
    let mcpAccess: MCPAccess
    @Bindable var hud: HUDController
    @State private var key = ""
    @State private var message: String?
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section("History") {
                Picker("Keep", selection: $model.historyRetention) {
                    ForEach(HistoryRetention.allCases) { preset in
                        Text(RetentionText.label(preset)).tag(preset)
                    }
                }
                .disabled(!model.recordsHistory)
                Text(RetentionText.size(model.historyBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.recordsHistory
                     ? "History stays on this Mac, excluded from backups. Local snapshots and administrators can still read it."
                     : "History is not being recorded" + (model.historyProblem.map { ": \($0)" } ?? "."))
                    .font(.caption)
                if let problem = model.historyProblem, model.recordsHistory {
                    Text("Last write failed: \(problem)").font(.caption).foregroundStyle(.red)
                }
                // Deleting cannot be undone, so one click only asks.
                Button("Delete history…", role: .destructive) { confirmingDelete = true }
                    .disabled(!model.recordsHistory)
                    .confirmationDialog("Delete all recorded history?", isPresented: $confirmingDelete) {
                        Button("Delete history", role: .destructive) {
                            Task {
                                message = await model.deleteHistory() ?? String(localized: "History deleted.")
                                await model.refreshHistorySize()
                            }
                        }
                    } message: {
                        Text("Every stored sample, app total and day summary is removed from this Mac. This cannot be undone.")
                    }
            }
            MCPAccessSection(access: mcpAccess)
            Section("Alerts") {
                ForEach(model.alertRules) { rule in
                    Picker(rule.title, selection: Binding(
                        get: { model.alertShortcuts[rule.id] ?? "" },
                        set: { model.setShortcut($0, for: rule.id) }
                    )) {
                        Text("No Shortcut").tag("")
                        // A saved Shortcut stays listed even if it has since been renamed or deleted.
                        let names = Array(Set((model.availableShortcuts ?? []) + [model.alertShortcuts[rule.id]].compactMap { $0 })).sorted()
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                    }
                }
                Text(model.availableShortcuts == nil
                     ? "Shortcuts could not be listed; rules still tint their lane and notify."
                     : "A rule runs its Shortcut when it is raised, at most once every 15 minutes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Processes") {
                Picker("CPU per process", selection: $model.processCPUScale) {
                    Text("Share of the whole machine").tag(ProcessCPUScale.machine)
                    Text("One core = 100 %").tag(ProcessCPUScale.oneCore)
                }
                Text("Lanes always show the whole machine; the table, inspector and cpu: filters follow this choice.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Lanes") {
                ForEach(model.laneLayout.order) { lane in
                    Toggle(LaneText.title(lane), isOn: Binding(
                        get: { !model.laneLayout.hidden.contains(lane) },
                        set: { model.laneLayout.set(lane, $0 ? .shown : .hidden) }
                    ))
                    .disabled(model.laneLayout.visible == [lane])
                }
                Button("Restore default lanes") { model.laneLayout = .standard }
                    .disabled(model.laneLayout == .standard)
                Text("Each lane's menu moves, resizes or hides it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                ForEach(0..<MenuBarLayout.maximumItems, id: \.self) { slot in
                    MenuBarSlot(model: model, slot: slot)
                }
                Text("Up to three readings, each a value, a one-minute graph or both.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("HUD") {
                Picker("Shows", selection: $hud.settings.density) {
                    Text("One value").tag(HUDDensity.single)
                    Text("One line").tag(HUDDensity.line)
                    Text("Block").tag(HUDDensity.block)
                    Text("Everything").tag(HUDDensity.detailed)
                }
                Picker("Corner", selection: $hud.settings.corner) {
                    Text("Top left").tag(HUDCorner.topLeft)
                    Text("Top right").tag(HUDCorner.topRight)
                    Text("Bottom left").tag(HUDCorner.bottomLeft)
                    Text("Bottom right").tag(HUDCorner.bottomRight)
                }
                Slider(value: $hud.settings.opacity, in: HUDSettings.opacityRange) { Text("Opacity") }
                Slider(value: $hud.settings.textScale, in: HUDSettings.textScaleRange) { Text("Text size") }
                Toggle("Dark backing behind text", isOn: $hud.settings.scrim)
                Toggle("Let clicks pass through", isOn: $hud.settings.clickThrough)
                Text("Turn click-through off to drag the HUD; it remembers where you put it on each display. Option-Command-H shows it, Option-Command-J changes what it shows. Frame rate needs macOS 27.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dock") {
                Picker("Dock icon", selection: $model.dockIcon) {
                    Text("App icon").tag(DockIconStyle.appIcon)
                    Text("CPU graph").tag(DockIconStyle.cpu)
                    Text("Memory graph").tag(DockIconStyle.memory)
                }
                Text("A graph redraws the Dock icon once a second.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Data sources") {
                ForEach(model.dataSources, id: \.metric) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(source.metric): \(source.availability.rawValue)")
                        if let detail = source.reason ?? source.source.map({ [$0.provider, $0.driver, $0.channel].compactMap { $0 }.joined(separator: " · ") }) {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Ask Coreography") {
                SecureField("Anthropic API key", text: $key)
                HStack {
                    Button("Save key") {
                        Task {
                            message = await model.saveProviderKey(key) ?? String(localized: "Key saved in the Keychain.")
                            key = ""
                        }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove key", role: .destructive) {
                        Task { message = await model.removeProviderKey() ?? String(localized: "Key removed.") }
                    }
                    .disabled(!model.hasProviderKey)
                }
                Text(model.hasProviderKey ? "A key is stored. Model: Claude Opus 5.5." : "No key is stored.")
                    .font(.caption)
                if let message { Text(message).font(.caption) }
                Text(sharingNotice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .task {
            await model.refreshShortcuts()
            await model.refreshProviderKey()
            await model.refreshHistorySize()
        }
    }
}

private enum RetentionText {
    static func label(_ preset: HistoryRetention) -> String {
        let cost = ByteCountFormatter.string(fromByteCount: preset.estimatedBytes, countStyle: .file)
        return String(localized: "\(preset.detailedHours) h detailed, \(preset.summaryDays) days summarised, \(preset.monthDays) days by minute (about \(cost))")
    }

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return String(localized: "Stored size unknown") }
        let used = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let cap = ByteCountFormatter.string(fromByteCount: HistoryRetention.sizeCap, countStyle: .file)
        return String(localized: "Now \(used) on disk; never more than \(cap)")
    }
}

/// One menu bar slot: a reading (the first slot always has one) and its style.
private struct MenuBarSlot: View {
    @Bindable var model: DashboardModel
    let slot: Int

    var body: some View {
        HStack {
            Picker("Item \(slot + 1)", selection: metric) {
                if slot > 0 { Text("None").tag(MenuBarMetric?.none) }
                ForEach(MenuBarMetric.allCases) { metric in Text(MenuBarText.name(metric)).tag(MenuBarMetric?.some(metric)) }
            }
            if slot < model.menuBarItems.count {
                Picker("Style", selection: style) {
                    Text("Value").tag(MenuBarStyle.value)
                    Text("Graph").tag(MenuBarStyle.graph)
                    Text("Both").tag(MenuBarStyle.both)
                }
                .labelsHidden()
                .frame(width: 100)
            }
        }
    }

    private var metric: Binding<MenuBarMetric?> {
        Binding(
            get: { slot < model.menuBarItems.count ? model.menuBarItems[slot].metric : nil },
            set: { chosen in
                var items = model.menuBarItems
                if let chosen {
                    let item = MenuBarItem(metric: chosen, style: slot < items.count ? items[slot].style : .value)
                    items.removeAll { $0.metric == chosen }
                    if slot < items.count { items[slot] = item } else { items.append(item) }
                } else if slot < items.count {
                    items.remove(at: slot)
                }
                model.menuBarItems = items
            }
        )
    }

    private var style: Binding<MenuBarStyle> {
        Binding(
            get: { slot < model.menuBarItems.count ? model.menuBarItems[slot].style : .value },
            set: { style in
                guard slot < model.menuBarItems.count else { return }
                model.menuBarItems[slot].style = style
            }
        )
    }
}

private enum MenuBarText {
    static func name(_ metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "Memory")
        case .gpu: String(localized: "GPU")
        case .download: String(localized: "Download")
        case .upload: String(localized: "Upload")
        case .temperature: String(localized: "Temperature")
        }
    }
}
