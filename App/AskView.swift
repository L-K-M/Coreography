import SwiftUI
import CoreographyServices

/// What leaves the Mac, stated wherever a question can be asked (plan: show
/// the provider and the data-sharing scope).
private let sharingNotice = String(localized: """
    Questions and requested readings (resource use, app names, sleep history and assertion types, never executable paths or process arguments) \
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
    @State private var key = ""
    @State private var message: String?

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
                Button("Delete history", role: .destructive) {
                    Task {
                        message = await model.deleteHistory() ?? String(localized: "History deleted.")
                        await model.refreshHistorySize()
                    }
                }
                .disabled(!model.recordsHistory)
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
