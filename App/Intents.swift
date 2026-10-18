import AppIntents
import CoreographyServices

// Shortcuts and Spotlight actions (plan: App Intents). Each reads or
// drives the running app's model; none signals, quits or exports.

struct GetSystemSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get System Summary"
    static let description = IntentDescription("CPU, memory, GPU, power, thermal and Time Machine state from Coreography.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = try await AutomationRouter.readyModel()
        let text = AutomationText.summary(DiagnosticTools.summary(model.diagnosticSnapshot()))
        return .result(value: text, dialog: "\(text)")
    }
}

enum AppActivityMetric: String, AppEnum {
    case cpu, disk

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Resource"
    static let caseDisplayRepresentations: [AppActivityMetric: DisplayRepresentation] = [.cpu: "CPU", .disk: "Disk"]
}

struct GetTopAppsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Top Apps"
    static let description = IntentDescription("Apps ranked by CPU time or disk bytes over the last minute.")
    private static let window: TimeInterval = 60

    @Parameter(title: "Resource", default: .cpu)
    var metric: AppActivityMetric

    @Parameter(title: "Count", default: 5)
    var count: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        guard (1...DiagnosticTools.maximumRows).contains(count) else {
            throw AutomationIntentError("Count must be 1-\(DiagnosticTools.maximumRows)")
        }
        let model = try await AutomationRouter.readyModel()
        let snapshot = model.diagnosticSnapshot()
        let page = try DiagnosticTools.topApps(
            snapshot, metric: metric == .cpu ? .cpu : .disk,
            range: snapshot.takenAt.addingTimeInterval(-Self.window)...snapshot.takenAt, limit: count
        )
        return .result(value: AutomationText.topApps(page))
    }
}

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording a Session"
    static let description = IntentDescription("Records a named session at full resolution until it is stopped.")

    @Parameter(title: "Name", default: "")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try await AutomationRouter.readyModel()
        if let failure = await model.perform(.startRecording(name: name)) { throw AutomationIntentError(failure) }
        return .result()
    }
}

struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stops the session being recorded and saves its report.")

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = AutomationRouter.shared?.model else { throw AutomationIntentError("Coreography is still starting") }
        if let failure = await model.perform(.stopRecording) { throw AutomationIntentError(failure) }
        return .result()
    }
}

struct FindPortHolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Who Uses a Port"
    static let description = IntentDescription("Your processes with a socket on this local or remote port.")

    @Parameter(title: "Port")
    var port: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        guard let number = UInt16(exactly: port), number > 0 else { throw AutomationIntentError("Port must be 1-65535") }
        let model = try await AutomationRouter.readyModel()
        let lookup = await model.holders(ofPort: number)
        return .result(value: lookup.holders.map(\.line) + lookup.limitations)
    }
}

struct FindFileHolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Who Has a File Open"
    static let description = IntentDescription("Your processes with an open file whose path contains this text.")

    @Parameter(title: "Path or Name")
    var path: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let text = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AutomationIntentError("Enter a path or part of a file name") }
        let model = try await AutomationRouter.readyModel()
        let lookup = await model.holders(ofFile: text)
        return .result(value: lookup.holders.map(\.line) + lookup.limitations)
    }
}

struct CoreographyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetSystemSummaryIntent(), phrases: ["Get \(.applicationName) summary", "How is my Mac in \(.applicationName)"],
            shortTitle: "System Summary", systemImageName: "gauge.with.dots.needle.33percent"
        )
        AppShortcut(
            intent: GetTopAppsIntent(), phrases: ["Top apps in \(.applicationName)"],
            shortTitle: "Top Apps", systemImageName: "list.number"
        )
        AppShortcut(
            intent: StartRecordingIntent(), phrases: ["Start recording in \(.applicationName)"],
            shortTitle: "Start Recording", systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopRecordingIntent(), phrases: ["Stop recording in \(.applicationName)"],
            shortTitle: "Stop Recording", systemImageName: "stop.circle"
        )
    }
}
