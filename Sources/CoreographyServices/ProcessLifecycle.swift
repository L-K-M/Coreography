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

/// Tracks first and last sightings across process samples (plan: new rows
/// tint briefly; exited rows stay as ghosts for 30 s). Exit status is not
/// claimed: the unprivileged sampler only knows the process is gone.
struct ProcessLifecycle: Sendable {
    static let newWindow: TimeInterval = 10
    static let ghostWindow: TimeInterval = 30

    private var firstSeen: [ProcessIdentity: Date] = [:]
    private var lastObserved: [ProcessIdentity: (name: String, app: String, time: Date)] = [:]
    private(set) var exited: [ExitedProcess] = []
    /// Processes present in the very first sample are not "new".
    private var baseline: Date?

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
    }

    func isNew(_ identity: ProcessIdentity, at time: Date) -> Bool {
        guard let seen = firstSeen[identity], let baseline, seen > baseline else { return false }
        return time.timeIntervalSince(seen) <= Self.newWindow
    }
}
