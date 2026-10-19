import Foundation
import CoreographyKit

public typealias QuitMode = ProcessQuitMode
public typealias CapturedSampleReport = ProcessSampleReport

/// Where a requested call-stack sample stands.
public enum SampleState: Sendable {
    case idle
    case running(name: String, seconds: Int)
    case finished(CapturedSampleReport)
    case failed(name: String, reason: String)
}

/// Everything the process menus can do (plan: Quit, Force Quit, Suspend
/// and Resume, Send Signal, Renice).
public enum ProcessAction: Hashable, Sendable {
    case quit, forceQuit, suspend, resume, hangUp, interrupt, lowerPriority

    /// "Force quit", "Suspend", …: the verb for dialogs and markers.
    public var verb: String {
        switch self {
        case .quit: "Quit"
        case .forceQuit: "Force quit"
        case .suspend: "Suspend"
        case .resume: "Resume"
        case .hangUp: "Send hang-up to"
        case .interrupt: "Interrupt"
        case .lowerPriority: "Lower the priority of"
        }
    }
}

/// A confirmed-before-sent request for one process (plan: actions re-check
/// identity and state their consequences).
public struct ProcessActionRequest: Identifiable, Sendable {
    public var id: String { "\(target.pid)-\(target.startSeconds)-\(target.startMicroseconds)-\(action)" }
    public let target: ProcessIdentity
    public let name: String
    public let action: ProcessAction
    public let consequences: [String]
    /// Ending this process ends the login session.
    public let endsSession: Bool
    /// Why the action is not offered for this process, when it is not.
    public let refusal: String?

    public var mode: QuitMode? {
        switch action {
        case .quit: .graceful
        case .forceQuit: .forced
        default: nil
        }
    }
}

/// Who placed a marker: the person's own actions stand apart from what
/// the system did.
public enum MarkerKind: Sendable {
    case action, alert, system
}

/// A timeline marker (plan: actions, alerts and system events drop markers).
public struct TimelineMarker: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let label: String
    public let kind: MarkerKind

    init(id: UUID = UUID(), time: Date, label: String, kind: MarkerKind) {
        self.id = id
        self.time = time
        self.label = label
        self.kind = kind
    }
}

enum ProcessActions {
    // Ending these processes ends the login session.
    private static let sessionProcesses: Set<String> = ["loginwindow", "WindowServer"]

    static func request(for process: ObservedProcess, mode: QuitMode, in snapshot: CapturedProcesses?) -> ProcessActionRequest {
        request(for: process, action: mode == .forced ? .forceQuit : .quit, in: snapshot)
    }

    static func request(for process: ObservedProcess, action: ProcessAction, in snapshot: CapturedProcesses?) -> ProcessActionRequest {
        let children = snapshot?.processes.filter { $0.parentPID == UInt32(bitPattern: process.id.pid) }.count
        let endsSession = sessionProcesses.contains(process.name)
        var consequences: [String] = []
        var refusal: String?
        switch action {
        case .quit, .forceQuit:
            if endsSession { consequences.append("This logs you out; unsaved work in every app is lost.") }
            consequences.append(action == .forceQuit
                ? "The process ends immediately without a chance to save."
                : "A regular app is asked to quit and can save or ask first; other processes receive SIGTERM.")
            switch children {
            case nil: consequences.append("Child processes, if any, may also exit.")
            case let count? where count > 0: consequences.append("\(count) child process\(count == 1 ? "" : "es") may also exit.")
            default: break
            }
        case .suspend:
            // A suspended window server or collector cannot be resumed from this window.
            if endsSession { refusal = "Suspending it would freeze the screen with no way back." }
            if process.id.pid == snapshot?.collectorPID { refusal = "Coreography cannot suspend itself." }
            consequences.append("It stops running until resumed; an app stops responding meanwhile.")
        case .resume:
            consequences.append("It continues where it stopped.")
        case .hangUp:
            consequences.append("Many daemons reload their settings; other processes may exit.")
        case .interrupt:
            consequences.append("As Control-C: most command-line tools stop.")
        case .lowerPriority:
            consequences.append("It gets less CPU when others want it; only an administrator can raise it back.")
        }
        return ProcessActionRequest(
            target: process.id, name: process.name, action: action, consequences: consequences,
            endsSession: endsSession && (action == .quit || action == .forceQuit), refusal: refusal
        )
    }

    /// One process as text, for Copy (plan: Copy as text or JSON).
    static func text(for process: ObservedProcess) -> String {
        [
            process.name,
            "PID \(process.id.pid), started \(Date(timeIntervalSince1970: TimeInterval(process.id.startSeconds)).ISO8601Format())",
            "UID \(process.uid), parent PID \(process.parentPID)",
            process.executablePath ?? "",
            "CPU \(process.cpuPercentOfMachine.numericValue.map { String(format: "%.1f%%", $0) } ?? "unknown")",
            "Footprint \(process.memoryFootprintBytes.numericValue.map { "\(Int64($0)) bytes" } ?? "unknown")"
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func json(for process: ObservedProcess) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(process)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
