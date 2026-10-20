import Foundation
import CoreographyKit

public typealias CapturedProcessDetail = ProcessDetail
public typealias CapturedSigner = ProcessSigner
public typealias CapturedSystemFacts = SystemFacts

/// What quitting a known system process does.
public enum QuitEffect: Sendable {
    /// macOS normally restarts it; current work can be interrupted.
    case restarts
    /// It stops something you would notice until it restarts.
    case interrupts(String)
    /// Your session ends.
    case logsOut
    /// The system will not allow it.
    case notAllowed
}

/// A plain-language note for a well-known system process (plan P23).
/// It describes the role, not the current job or a promise that quitting
/// is safe right now.
public struct ProcessExplanation: Sendable {
    public let summary: String
    public let quitting: QuitEffect

    /// A general consequence, not a guarantee about current work.
    public var quittingNote: String {
        switch quitting {
        case .restarts: "macOS normally restarts it; current work may be interrupted."
        case .interrupts(let what): "Quitting interrupts it: \(what)"
        case .logsOut: "Quitting it logs you out."
        case .notAllowed: "macOS does not allow quitting it."
        }
    }
}

/// The selected process at one live sample (plan: pinned processes keep
/// full per-process detail). Missing readings stay nil, never zero.
public struct ProcessHistoryPoint: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let cpuPercent: Double?
    public let footprintBytes: Double?
    public let diskBytesPerSecond: Double?
    public let networkBytesPerSecond: Double?
    /// Points in different segments are separated by a sampling gap.
    public let segment: Int
}

/// One step up the parent chain; a parent outside the snapshot has no name.
public struct ParentLink: Identifiable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String?
}

/// Everything the inspector shows for one selected process.
public struct ProcessInspection: Sendable {
    public let process: ObservedProcess
    public let appName: String
    /// From the parent up, ending at launchd or the first unobserved parent.
    public let parentChain: [ParentLink]
    /// The launchd job whose program this is, when the Startup inventory knows it.
    public let launchdLabel: String?
    public let explanation: ProcessExplanation?
    /// Read on selection; nil while loading.
    public let detail: CapturedProcessDetail?
    /// Its sockets; nil while loading or when they could not be read.
    public let sockets: [CapturedConnection]?
    /// Time Machine or Spotlight state for their processes; nil for others or before the first read.
    public let maintenance: MaintenanceNote?
}

enum ProcessExplanations {
    private static let notes: [String: ProcessExplanation] = [
        "kernel_task": .init(summary: "The macOS kernel. High CPU here often means it is holding other work back to cool the Mac.", quitting: .notAllowed),
        "launchd": .init(summary: "Starts and supervises every other process.", quitting: .notAllowed),
        "WindowServer": .init(summary: "Draws every window and the menu bar on screen.", quitting: .logsOut),
        "loginwindow": .init(summary: "Holds your login session.", quitting: .logsOut),
        "mds": .init(summary: "Spotlight's index server; busy after installs and large copies.", quitting: .restarts),
        "mds_stores": .init(summary: "Spotlight's index storage; busy while files are being indexed.", quitting: .restarts),
        "mdworker_shared": .init(summary: "Spotlight reading files to index them.", quitting: .restarts),
        "backupd": .init(summary: "Runs Time Machine backups.", quitting: .interrupts("An active backup stops.")),
        "cloudd": .init(summary: "Syncs iCloud data for apps.", quitting: .restarts),
        "bird": .init(summary: "Syncs iCloud Drive files.", quitting: .restarts),
        "photoanalysisd": .init(summary: "Analyses the Photos library, usually while the Mac is idle.", quitting: .restarts),
        "softwareupdated": .init(summary: "Checking for and preparing macOS updates.", quitting: .restarts),
        "trustd": .init(summary: "Checking certificates for secure connections.", quitting: .restarts),
        "syspolicyd": .init(summary: "Gatekeeper checking apps before they open.", quitting: .restarts),
        "XprotectService": .init(summary: "XProtect scanning for known malware.", quitting: .restarts),
        "coreaudiod": .init(summary: "Plays and records all sound.", quitting: .interrupts("Sound stops for a moment.")),
        "Dock": .init(summary: "The Dock, Launchpad and Mission Control.", quitting: .restarts),
        "Finder": .init(summary: "The Finder and the desktop.", quitting: .restarts),
        "SystemUIServer": .init(summary: "Menu bar items owned by the system.", quitting: .restarts),
        "ControlCenter": .init(summary: "Control Center and its menu bar items.", quitting: .restarts),
        "dasd": .init(summary: "Schedules background work for when the Mac is idle or on power.", quitting: .restarts),
        "powerd": .init(summary: "Power management: sleep, wake and battery.", quitting: .notAllowed),
        "configd": .init(summary: "Network and system configuration.", quitting: .notAllowed),
        "cfprefsd": .init(summary: "Reads and writes app settings.", quitting: .restarts),
        "nsurlsessiond": .init(summary: "Background downloads and uploads for apps.", quitting: .restarts)
    ]

    /// Excludes writable third-party locations such as /usr/local.
    private static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/bin/", "/Library/Apple/System/"]

    /// A missing path cannot establish that a familiar name belongs to macOS,
    /// and a signature read as anyone's but Apple's rules it out; an unread
    /// one leaves the path to decide.
    static func note(for process: ObservedProcess, signer: CapturedSigner? = nil) -> ProcessExplanation? {
        guard let note = notes[process.name] else { return nil }
        switch signer {
        case .developer, .unsigned: return nil
        case .apple, .unknown, nil: break
        }
        // The kernel has no executable path; PID 0 cannot belong to a user process.
        if process.id.pid == 0, process.name == "kernel_task" { return note }
        guard let path = process.executablePath else { return nil }
        return systemPrefixes.contains { path.hasPrefix($0) } ? note : nil
    }
}

enum ProcessInspections {
    /// launchd is PID 1; a chain never needs more steps than this.
    private static let maximumDepth = 64

    static func make(
        _ process: ObservedProcess, in snapshot: CapturedProcesses, startup: CapturedStartupInventory?,
        detail: CapturedProcessDetail?, sockets: [CapturedConnection]?, maintenance: CapturedMaintenance? = nil
    ) -> ProcessInspection {
        let byPID = Dictionary(snapshot.processes.map { ($0.id.pid, $0) }) { first, _ in first }
        var chain: [ParentLink] = []
        var parent = Int32(bitPattern: process.parentPID)
        while parent > 0, chain.count < maximumDepth {
            let observed = byPID[parent]
            chain.append(ParentLink(pid: parent, name: observed?.name))
            guard let observed, parent != 1 else { break }
            parent = Int32(bitPattern: observed.parentPID)
        }

        let label = process.executablePath.flatMap { path in startup?.items.first { $0.program == path }?.label }
        let detail = detail?.process == process.id ? detail : nil
        return ProcessInspection(
            process: process, appName: ProcessGroups.appNames(snapshot)[process.id] ?? process.name,
            parentChain: chain, launchdLabel: label,
            explanation: ProcessExplanations.note(for: process, signer: detail?.signing?.signer),
            detail: detail, sockets: sockets,
            maintenance: maintenance.flatMap { status in MaintenanceWork.of(process).map { MaintenanceNotes.note($0, status) } }
        )
    }
}
