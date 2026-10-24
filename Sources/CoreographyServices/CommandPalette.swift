import Foundation
import CoreographyKit

/// Every window action by name (plan: command palette, Command-Shift-P).
/// The model runs its own actions; the app runs the ones that need a
/// window, a confirmation or the pasteboard.
public enum PaletteAction: Hashable, Sendable {
    case toggleInspector
    case toggleHold
    case startRecording
    case stopRecording
    case range(TimeRange)
    case pane(DetailPane)
    case grouping(ProcessGrouping)
    case sort(ProcessSort)
    case filter(String)
    case clearFilter
    case saveFilter
    case clearScope
    case clearSelection
    case resetSensorStats
    case refreshStartup
    case sampleSelected
    case spindumpSelected
    /// The app confirms every one except Resume first.
    case processAction(ProcessAction)
    case copySelected
    case toggleHUD
    case openSettings
    case toggleSampling
    case returnToNow
    /// The app asks for the name.
    case addMarker
}

public struct PaletteEntry: Identifiable, Equatable, Sendable {
    public let title: String
    public let action: PaletteAction
    /// Why it cannot run now; such entries stay listed, disabled.
    public let unavailableReason: String?

    public var id: String { title }
}

public enum CommandPalette {
    /// How well a title matches, best first.
    private enum Rank: Int, Comparable {
        case titlePrefix, wordPrefix, substring, subsequence

        static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Entries matching every typed word, best first; ties keep catalogue
    /// order. Example: "sort mem" finds "Sort by Memory"; "rng hr" finds
    /// "Range: 1 Hour" by subsequence.
    public static func matches(_ query: String, in entries: [PaletteEntry]) -> [PaletteEntry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries }
        let ranked = entries.enumerated().compactMap { offset, entry -> (Rank, Int, PaletteEntry)? in
            let title = entry.title.lowercased()
            var worst = Rank.titlePrefix
            for word in words {
                guard let rank = rank(word, in: title) else { return nil }
                worst = max(worst, rank)
            }
            return (worst, offset, entry)
        }
        return ranked.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }

    private static func rank(_ word: String, in title: String) -> Rank? {
        if title.hasPrefix(word) { return .titlePrefix }
        let titleWords = title.split { !$0.isLetter && !$0.isNumber }
        if titleWords.contains(where: { $0.hasPrefix(word) }) { return .wordPrefix }
        if title.contains(word) { return .substring }
        var remaining = word[...]
        for character in title where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return .subsequence }
        }
        return nil
    }

    /// Filter tokens the palette offers as presets.
    static let filterPresets: [(title: String, filter: String)] = [
        ("Filter: Apps", "#apps"), ("Filter: My Processes", "#mine"), ("Filter: Third-Party", "#third-party"),
        ("Filter: New", "#new"), ("Filter: Listening", "#listening"), ("Filter: Preventing Sleep", "#preventing-sleep")
    ]

    static func rangeTitle(_ range: TimeRange) -> String {
        switch range {
        case .minute: "Range: 1 Minute"
        case .tenMinutes: "Range: 10 Minutes"
        case .hour: "Range: 1 Hour"
        case .sixHours: "Range: 6 Hours"
        case .day: "Range: 24 Hours"
        case .week: "Range: 7 Days"
        case .month: "Range: 30 Days"
        }
    }

    static func paneTitle(_ pane: DetailPane) -> String {
        switch pane {
        case .processes: "Show Processes"
        case .connections: "Show Connections"
        case .startup: "Show Startup Items"
        case .sensors: "Show Sensors"
        case .sessions: "Show Sessions"
        }
    }

    static func sortTitle(_ sort: ProcessSort) -> String {
        switch sort {
        case .cpu: "Sort by CPU"
        case .memory: "Sort by Memory"
        case .diskRead: "Sort by Disk Read"
        case .diskWrite: "Sort by Disk Write"
        case .network: "Sort by Network"
        case .gpu: "Sort by GPU Time"
        case .power: "Sort by CPU Power"
        case .name: "Sort by Name"
        case .cpuTime: "Sort by CPU Time"
        case .started: "Sort by Start, Newest First"
        case .threads: "Sort by Threads"
        case .instructions: "Sort by Instructions"
        }
    }

    static func processTitle(_ action: ProcessAction, _ name: String) -> String {
        switch action {
        case .quit: "Quit \(name)…"
        case .forceQuit: "Force Quit \(name)…"
        case .suspend: "Suspend \(name)…"
        case .resume: "Resume \(name)"
        case .hangUp: "Send Hang-Up to \(name)…"
        case .interrupt: "Interrupt \(name)…"
        case .user1: "Send SIGUSR1 to \(name)…"
        case .user2: "Send SIGUSR2 to \(name)…"
        case .info: "Send SIGINFO to \(name)…"
        case .lowerPriority: "Lower Priority of \(name)…"
        case .raisePriority: "Raise Priority of \(name)…"
        }
    }
}
