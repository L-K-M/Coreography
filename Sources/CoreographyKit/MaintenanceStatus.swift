import Foundation
import CoreographyDrivers

/// What `tmutil status` reported about Time Machine.
public enum TimeMachineState: Equatable, Sendable {
    case idle
    case backingUp(BackupProgress)
    case unavailable(String)
}

/// Fields tmutil leaves out, or reports as -1, are nil rather than zero.
public struct BackupProgress: Equatable, Sendable {
    /// tmutil's own phase name, such as "Copying" or "FindingChanges".
    public let phase: String?
    /// 0...1.
    public let fraction: Double?
    public let remainingSeconds: Int?
}

/// What `mdutil -s /` reported. It never says whether indexing is
/// happening now or when it ends, only whether the disk is indexed.
public enum SpotlightIndexing: Equatable, Sendable {
    case enabled
    case disabled
    case unavailable(String)
}

public struct MaintenanceStatus: Equatable, Sendable {
    public let readAt: Date
    public let timeMachine: TimeMachineState
    public let spotlight: SpotlightIndexing
}

/// Reads Time Machine and Spotlight status on request, never while sampling.
public struct MaintenanceStatusProvider: Sendable {
    private let driver: any MaintenanceStatusReading

    public init() { self.init(driver: MaintenanceStatusDriver()) }

    init(driver: any MaintenanceStatusReading) { self.driver = driver }

    public func load(now: Date = Date()) async -> MaintenanceStatus {
        async let timeMachine = timeMachineState()
        async let spotlight = spotlightIndexing()
        return MaintenanceStatus(readAt: now, timeMachine: await timeMachine, spotlight: await spotlight)
    }

    private func timeMachineState() async -> TimeMachineState {
        do {
            let raw = try await driver.timeMachineStatus()
            if let failure = Self.failure(raw, tool: "tmutil") { return .unavailable(failure) }
            return TimeMachineStatusParser.parse(raw.text)
        } catch MaintenanceStatusError.unavailable(let reason) {
            return .unavailable(reason)
        } catch {
            return .unavailable("\(error)")
        }
    }

    private func spotlightIndexing() async -> SpotlightIndexing {
        do {
            let raw = try await driver.spotlightStatus()
            if let failure = Self.failure(raw, tool: "mdutil") { return .unavailable(failure) }
            return SpotlightStatusParser.parse(raw.text)
        } catch MaintenanceStatusError.unavailable(let reason) {
            return .unavailable(reason)
        } catch {
            return .unavailable("\(error)")
        }
    }

    /// A cut-off or failed answer is not evidence of idleness.
    private static func failure(_ raw: RawToolStatus, tool: String) -> String? {
        if raw.timedOut { return "\(tool) hit its time limit" }
        if raw.exitStatus != 0 { return "\(tool) exited with status \(raw.exitStatus)" }
        return nil
    }
}

/// Parses `tmutil status`, an old-style property list after a title line:
///
/// ```text
/// Backup session status:
/// {
///     BackupPhase = Copying;
///     Percent = "0.4231";
///     Progress = { Percent = "0.4231"; TimeRemaining = 312; };
///     Running = 1;
/// }
/// ```
enum TimeMachineStatusParser {
    private static let unknownNumber = -1.0

    static func parse(_ text: String) -> TimeMachineState {
        guard let open = text.firstIndex(of: "{"),
              let plist = try? PropertyListSerialization.propertyList(from: Data(text[open...].utf8), format: nil),
              let status = plist as? [String: Any] else {
            return .unavailable("tmutil printed an unrecognised status")
        }
        guard let running = number(status["Running"]) else {
            return .unavailable("tmutil did not say whether a backup is running")
        }
        guard running != 0 else { return .idle }

        let progress = status["Progress"] as? [String: Any]
        let fraction = number(progress?["Percent"]) ?? number(status["Percent"])
        let remaining = number(progress?["TimeRemaining"])
        return .backingUp(BackupProgress(
            phase: status["BackupPhase"] as? String,
            fraction: fraction.flatMap { (0...1).contains($0) ? $0 : nil },
            remainingSeconds: remaining.flatMap { $0 >= 0 ? Int($0) : nil }
        ))
    }

    /// Old-style plists hold every scalar as a string; -1 means unknown.
    private static func number(_ value: Any?) -> Double? {
        let parsed: Double?
        switch value {
        case let text as String: parsed = Double(text)
        case let number as NSNumber: parsed = number.doubleValue
        default: parsed = nil
        }
        guard let parsed, parsed.isFinite, parsed != unknownNumber else { return nil }
        return parsed
    }
}

/// Parses `mdutil -s /`:
///
/// ```text
/// /:
///     Indexing enabled.
/// ```
enum SpotlightStatusParser {
    static func parse(_ text: String) -> SpotlightIndexing {
        let lowered = text.lowercased()
        if lowered.contains("indexing enabled") { return .enabled }
        if lowered.contains("indexing disabled") || lowered.contains("indexing and searching disabled") { return .disabled }
        return .unavailable("mdutil printed an unrecognised status")
    }
}
