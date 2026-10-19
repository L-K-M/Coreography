import Foundation
import CoreographyKit

/// A process seen in an earlier sample and missing from the latest one.
public struct ExitedProcess: Identifiable, Sendable {
    public var id: ProcessIdentity { identity }
    public let identity: ProcessIdentity
    public let name: String
    public let appName: String
    /// The last sample that still observed it; the exit happened after this.
    public let lastSeen: Date
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
/// tint briefly; exited rows stay as ghosts for 30 s). Exit status is not
/// claimed: the unprivileged sampler only knows the process is gone.
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
    private(set) var exited: [ExitedProcess] = []
    /// Processes present in the very first sample are not "new".
    private var baseline: Date?
    private(set) var appEvents: [AppLifecycleEvent] = []
    /// Each running app's last observed sample; nil before the first.
    private var appsSeen: [String: Date]?

    mutating func record(_ snapshot: CapturedProcesses) {
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
        if snapshot.continuity == .continuous, !truncated {
            for (identity, last) in lastObserved where !present.contains(identity) {
                exited.append(ExitedProcess(identity: identity, name: last.name, appName: last.app, lastSeen: last.time))
            }
        }
        var observed = Dictionary(uniqueKeysWithValues: snapshot.processes.map {
            ($0.id, (name: $0.name, app: apps[$0.id] ?? $0.name, time: time))
        })
        // Left-out processes keep their last sighting until a full list settles them.
        if truncated { observed.merge(lastObserved) { current, _ in current } }
        lastObserved = observed
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
        guard let seen = appsSeen, continuity == .continuous else {
            appsSeen = now
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
