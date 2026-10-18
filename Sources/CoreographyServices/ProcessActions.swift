import Foundation
import CoreographyKit

public typealias QuitMode = ProcessQuitMode

/// A confirmed-before-sent request to quit one process (plan: actions
/// re-check identity and state their consequences).
public struct ProcessActionRequest: Identifiable, Sendable {
    public var id: String { "\(target.pid)-\(target.startSeconds)-\(target.startMicroseconds)-\(mode)" }
    public let target: ProcessIdentity
    public let name: String
    public let mode: QuitMode
    public let consequences: [String]
    /// Ending this process ends the login session.
    public let endsSession: Bool
}

/// A timeline marker for an action the person took (plan: actions drop markers).
public struct TimelineMarker: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let label: String
}

enum ProcessActions {
    // Ending these processes ends the login session.
    private static let sessionProcesses: Set<String> = ["loginwindow", "WindowServer"]

    static func request(for process: ObservedProcess, mode: QuitMode, in snapshot: CapturedProcesses?) -> ProcessActionRequest {
        let children = snapshot?.processes.filter { $0.parentPID == UInt32(bitPattern: process.id.pid) }.count ?? 0
        let endsSession = sessionProcesses.contains(process.name)
        var consequences: [String] = []
        if endsSession {
            consequences.append("This logs you out; unsaved work in every app is lost.")
        }
        switch mode {
        case .graceful:
            consequences.append("A regular app is asked to quit and can save or ask first; other processes receive SIGTERM.")
        case .forced:
            consequences.append("The process ends immediately without a chance to save.")
        }
        if children > 0 {
            consequences.append("\(children) child process\(children == 1 ? "" : "es") may also exit.")
        }
        return ProcessActionRequest(
            target: process.id, name: process.name, mode: mode, consequences: consequences, endsSession: endsSession
        )
    }
}
