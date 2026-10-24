import Foundation
import CoreographyKit

/// How a ghosted process ended, decoded from the wait-status word the
/// kernel reports with `NOTE_EXITSTATUS`.
public enum ProcessExit: Equatable, Sendable {
    /// Exited on its own with this code.
    case exited(code: Int32)
    /// Killed by this signal; `name` is its BSD name where known.
    case signalled(signal: Int32, name: String)

    /// The wait-status encoding `waitpid` reports: signalled deaths carry
    /// the signal in the low 7 bits, clean exits the code above them.
    public init(status: Int32) {
        let signal = status & 0x7f
        if signal == 0 {
            self = .exited(code: (status >> 8) & 0xff)
        } else {
            self = .signalled(signal: signal, name: Self.signalNames[signal] ?? "SIG\(signal)")
        }
    }

    /// Short text for the ghost row, e.g. "exit 1" or "SIGKILL".
    public var label: String {
        switch self {
        case .exited(let code): return "exit \(code)"
        case .signalled(_, let name): return name
        }
    }

    private static let signalNames: [Int32: String] = [
        1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP",
        6: "SIGABRT", 7: "SIGEMT", 8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS",
        11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE", 14: "SIGALRM", 15: "SIGTERM",
        16: "SIGURG", 17: "SIGSTOP", 18: "SIGTSTP", 19: "SIGCONT", 20: "SIGCHLD",
        21: "SIGTTIN", 22: "SIGTTOU", 23: "SIGIO", 24: "SIGXCPU", 25: "SIGXFSZ",
        26: "SIGVTALRM", 27: "SIGPROF", 28: "SIGWINCH", 29: "SIGINFO",
        30: "SIGUSR1", 31: "SIGUSR2"
    ]
}

/// A process seen in an earlier sample and missing from the latest one.
public struct ExitedProcess: Identifiable, Sendable {
    public var id: ProcessIdentity { identity }
    public let identity: ProcessIdentity
    public let name: String
    public let appName: String
    /// The last sample that still observed it; the exit happened after this.
    public let lastSeen: Date
    /// How it ended where the kernel shared the status; nil when only the
    /// exit itself was observable (processes of other users, or a watcher
    /// that had not seen the pid yet).
    public let exit: ProcessExit?
}

/// An app's first process appearing or its last one leaving (plan:
/// markers for observed process starts and exits).
struct AppLifecycleEvent: Equatable, Sendable {
    enum Change: Equatable, Sendable { case started, exited }

    let app: String
    let change: Change
    /// A start is its first observed sample; an exit, its last.
    let time: Date
}

/// Tracks first and last sightings across process samples (plan: new rows
/// tint briefly; exited rows stay as ghosts for 30 s). Exit status is the
/// caller's kqueue observation: it arrives only where the kernel shares it,
/// which needs the same rights as signalling.
struct ProcessLifecycle: Sendable {
    static let newWindow: TimeInterval = 10
    static let ghostWindow: TimeInterval = 30
    /// App events are kept for the live hour the lanes show.
    static let eventWindow: TimeInterval = 3600
    /// Only programs inside an app bundle count as apps: daemons and
    /// helpers come and go every few seconds and would bury the timeline.
    private static let bundleMarker = ".app/"

    private var firstSeen: [ProcessIdentity: Date] = [:]
    private var lastObserved: [ProcessIdentity: (name: String, app: String, time: Date)] = [:]
    private var pendingExits: [ProcessIdentity: ProcessExit] = [:]
    private(set) var exited: [ExitedProcess] = []
    /// Processes present in the very first sample are not "new".
    private var baseline: Date?
    private(set) var appEvents: [AppLifecycleEvent] = []
    /// Each running app's last observed sample; nil before the first.
    private var appsSeen: [String: Date]?

    /// `exits` carries pid → wait status for exits observed since the last
    /// sample; a ghost whose pid is absent keeps a nil `exit`.
    mutating func record(_ snapshot: CapturedProcesses, exits: [Int32: Int32] = [:]) {
        let time = snapshot.stamp.wallTime
        let rows = ProcessGroups.rows(in: snapshot, matching: "", sortedBy: .name, grouping: .app)
        var apps: [ProcessIdentity: String] = [:]
        for row in rows {
            if let process = row.process { apps[process.id] = row.appName }
            for child in row.children ?? [] { if let process = child.process { apps[process.id] = child.appName } }
        }

        let present = Set(snapshot.processes.map(\.id))
        if baseline == nil { baseline = time }
        // An interrupted sample (sleep) cannot tell exits from missed samples,
        // and a truncated list leaves out processes that still run.
        let truncated = snapshot.enumerationTruncated
        // Queue delivery can precede the first sample that omits the process.
        if snapshot.continuity == .continuous {
            for identity in lastObserved.keys {
                if let status = exits[identity.pid], pendingExits[identity] == nil {
                    pendingExits[identity] = ProcessExit(status: status)
                }
            }
        } else {
            pendingExits.removeAll()
        }
        if snapshot.continuity == .continuous, !truncated {
            for (identity, last) in lastObserved where !present.contains(identity) {
                exited.append(ExitedProcess(
                    identity: identity, name: last.name, appName: last.app,
                    lastSeen: last.time, exit: pendingExits[identity]
                ))
            }
        }
        var observed = Dictionary(uniqueKeysWithValues: snapshot.processes.map {
            ($0.id, (name: $0.name, app: apps[$0.id] ?? $0.name, time: time))
        })
        // Left-out processes keep their last sighting until a full list settles them.
        if truncated { observed.merge(lastObserved) { current, _ in current } }
        lastObserved = observed
        pendingExits = pendingExits.filter { observed[$0.key] != nil }
        for identity in present where firstSeen[identity] == nil { firstSeen[identity] = time }
        if !truncated { firstSeen = firstSeen.filter { present.contains($0.key) } }
        exited.removeAll { present.contains($0.identity) || time.timeIntervalSince($0.lastSeen) > Self.ghostWindow }
        recordApps(Self.runningApps(snapshot.processes), at: time, continuity: snapshot.continuity, truncated: truncated)
    }

    /// Starts and exits only between two complete, continuous samples: after
    /// sleep the apps that changed did so at an unknown time, and a truncated
    /// list leaves running apps out.
    ///
    /// ```text
    /// sample:  t0 {Safari}   t2 {Safari, Mail}   t4 {Mail}
    /// events:                Mail started @t2    Safari exited @t2
    /// ```
    private mutating func recordApps(
        _ running: Set<String>, at time: Date, continuity: SamplingContinuity, truncated: Bool
    ) {
        defer { appEvents.removeAll { time.timeIntervalSince($0.time) > Self.eventWindow } }

        let now = Dictionary(uniqueKeysWithValues: running.map { ($0, time) })
        // Only a complete list can be the baseline: one cut short would make
        // every app it left out look started on the next sample.
        guard let seen = appsSeen, continuity == .continuous else {
            appsSeen = truncated ? nil : now
            return
        }
        guard !truncated else {
            appsSeen = seen.merging(now) { _, latest in latest }
            return
        }

        appEvents += running.subtracting(seen.keys).sorted().map {
            AppLifecycleEvent(app: $0, change: .started, time: time)
        }
        appEvents += seen.filter { !running.contains($0.key) }.sorted { $0.key < $1.key }.map {
            AppLifecycleEvent(app: $0.key, change: .exited, time: $0.value)
        }
        appsSeen = now
    }

    /// Apps by their outermost bundle, so the name holds while helpers come
    /// and go. Example: ".../Google Chrome.app/Contents/Frameworks/.../
    /// Google Chrome Helper.app/..." is "Google Chrome".
    private static func runningApps(_ processes: [ObservedProcess]) -> Set<String> {
        Set(processes.compactMap { process in
            // Volumes are usually case-insensitive, so "Old.APP" is a bundle too.
            guard let path = process.executablePath,
                  let bundle = path.range(of: bundleMarker, options: .caseInsensitive) else { return nil }
            let name = (String(path[..<bundle.lowerBound]) as NSString).lastPathComponent
            return name.isEmpty ? nil : name
        })
    }

    func isNew(_ identity: ProcessIdentity, at time: Date) -> Bool {
        guard let seen = firstSeen[identity], let baseline, seen > baseline else { return false }
        return time.timeIntervalSince(seen) <= Self.newWindow
    }
}
