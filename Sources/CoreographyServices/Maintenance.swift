import Foundation
import CoreographyKit

public typealias CapturedMaintenance = MaintenanceStatus

/// Maintenance work a recognised system process does, where macOS
/// reports its state (plan: Time Machine progress from `tmutil status`,
/// Spotlight's indexed state from `mdutil -s`). Photo analysis, iCloud
/// sync and software updates have no status source, so only their role
/// notes are shown.
enum MaintenanceWork: Sendable {
    case timeMachine
    case spotlight

    /// Only a process the role catalogue already verified by path.
    static func of(_ process: ObservedProcess) -> MaintenanceWork? {
        guard ProcessExplanations.note(for: process) != nil else { return nil }
        switch process.name {
        case "backupd": return .timeMachine
        case "mds", "mds_stores", "mdworker_shared": return .spotlight
        default: return nil
        }
    }
}

/// A maintenance state for the inspector, with when it was read.
public struct MaintenanceNote: Equatable, Sendable {
    public let text: String
    public let readAt: Date
}

enum MaintenanceNotes {
    private static let secondsPerMinute = 60.0
    private static let minutesPerHour = 60.0

    static func note(_ work: MaintenanceWork, _ status: CapturedMaintenance) -> MaintenanceNote {
        let text = switch work {
        case .timeMachine: timeMachine(status.timeMachine)
        case .spotlight: spotlight(status.spotlight)
        }
        return MaintenanceNote(text: text, readAt: status.readAt)
    }

    /// Only a reported running backup earns "finishes on its own".
    /// Example: "Time Machine is backing up: copying, 42% done, about 5 min left. It finishes on its own."
    static func timeMachine(_ state: TimeMachineState) -> String {
        switch state {
        case .idle:
            return "No Time Machine backup is running."
        case .unavailable(let reason):
            return "Time Machine's status could not be read: \(reason)."
        case .backingUp(let progress):
            var parts: [String] = []
            if let phase = progress.phase { parts.append(phaseText(phase)) }
            if let fraction = progress.fraction { parts.append("\(Int((fraction * 100).rounded(.down)))% done") }
            if let seconds = progress.remainingSeconds { parts.append(remainingText(seconds)) }
            let detail = parts.isEmpty ? "" : ": " + parts.joined(separator: ", ")
            return "Time Machine is backing up\(detail). It finishes on its own."
        }
    }

    /// mdutil reports whether the disk is indexed, never progress, so no end is promised.
    static func spotlight(_ indexing: SpotlightIndexing) -> String {
        switch indexing {
        case .enabled: "Spotlight indexing is on for the startup disk. macOS does not report indexing progress."
        case .disabled: "Spotlight indexing is off for the startup disk."
        case .unavailable(let reason): "Spotlight's status could not be read: \(reason)."
        }
    }

    /// "FindingChanges" reads as "finding changes"; an acronym stays one
    /// word, so "HealthCheckCopyHFSMeta" reads as "health check copy HFS meta".
    static func phaseText(_ phase: String) -> String {
        let characters = Array(phase)
        var words: [String] = []
        var word = ""
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            // A new word starts at a capital after a lowercase letter, or at
            // the last capital of an acronym that a lowercase letter follows.
            let startsWord = character.isUppercase && (
                previous?.isLowercase == true || (previous?.isUppercase == true && next?.isLowercase == true)
            )
            if startsWord, !word.isEmpty {
                words.append(word)
                word = ""
            }
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        return words.map { $0.allSatisfy(\.isUppercase) && $0.count > 1 ? $0 : $0.lowercased() }.joined(separator: " ")
    }

    /// "about 5 min left"; an hour or more in half hours: "about 1.5 h left".
    private static func remainingText(_ seconds: Int) -> String {
        guard Double(seconds) >= secondsPerMinute else { return "under a minute left" }
        let minutes = (Double(seconds) / secondsPerMinute).rounded()
        guard minutes >= minutesPerHour else { return "about \(Int(minutes)) min left" }
        let hours = (minutes / minutesPerHour * 2).rounded() / 2
        return "about \(hours.formatted(.number.precision(.fractionLength(0...1)))) h left"
    }
}

/// Maintenance state for diagnostic clients. Spotlight's indexed state
/// is not activity, and an idle Time Machine says nothing about Spotlight.
public struct MaintenanceReport: Codable, Equatable, Sendable {
    public enum TimeMachine: String, Codable, Sendable { case idle, backingUp, unavailable }
    public enum Spotlight: String, Codable, Sendable { case enabled, disabled, unavailable }

    public let readAt: Date
    public let timeMachine: TimeMachine
    public let backupPhase: String?
    /// 0...1; absent when tmutil did not report it.
    public let backupFraction: Double?
    public let backupRemainingSeconds: Int?
    public let spotlightIndexing: Spotlight
    public let unavailableReasons: [String]

    init(_ status: CapturedMaintenance) {
        readAt = status.readAt
        var reasons: [String] = []
        switch status.timeMachine {
        case .idle:
            timeMachine = .idle
            backupPhase = nil
            backupFraction = nil
            backupRemainingSeconds = nil
        case .backingUp(let progress):
            timeMachine = .backingUp
            backupPhase = progress.phase
            backupFraction = progress.fraction
            backupRemainingSeconds = progress.remainingSeconds
        case .unavailable(let reason):
            timeMachine = .unavailable
            backupPhase = nil
            backupFraction = nil
            backupRemainingSeconds = nil
            reasons.append("Time Machine: \(reason)")
        }
        switch status.spotlight {
        case .enabled: spotlightIndexing = .enabled
        case .disabled: spotlightIndexing = .disabled
        case .unavailable(let reason):
            spotlightIndexing = .unavailable
            reasons.append("Spotlight: \(reason)")
        }
        unavailableReasons = reasons
    }
}
