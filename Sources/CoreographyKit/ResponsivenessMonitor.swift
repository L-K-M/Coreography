import Foundation
import CoreographyDrivers

/// Turns the responsiveness probe into a stable "not responding" set: a
/// process is marked only after `requiredStreak` consecutive unresponsive
/// samples, so one busy moment never marks it (plan: the state needs
/// persistence, not a single spike).
public struct ResponsivenessMonitor: Sendable {
    /// Consecutive unresponsive samples before a process is marked.
    public static let requiredStreak = 2
    private let probe: any ResponsivenessProbing
    /// Identities marked at the last `record`; empty until then.
    public private(set) var notResponding: Set<ProcessIdentity> = []
    private var streaks: [ProcessIdentity: Int] = [:]

    /// Nil where the probe is unavailable: not macOS, or the private symbols
    /// are absent.
    public init?() {
        guard let probe = ResponsivenessDriver() else { return nil }
        self.probe = probe
    }

    init(probe: any ResponsivenessProbing) { self.probe = probe }

    /// One probe per sampled process, called once per process sample. A
    /// process the probe cannot judge is responsive: without a session
    /// connection it can never beachball.
    public mutating func record(_ processes: [ProcessReading]) {
        var seen: Set<ProcessIdentity> = []
        var marked: Set<ProcessIdentity> = []
        for process in processes {
            seen.insert(process.id)
            let streak = probe.unresponsive(process.id.pid) == true ? streaks[process.id, default: 0] + 1 : 0
            streaks[process.id] = streak
            if streak >= Self.requiredStreak { marked.insert(process.id) }
        }
        streaks = streaks.filter { seen.contains($0.key) }
        notResponding = marked
    }

    /// Forgets every streak; the next `record` starts counting again.
    public mutating func reset() {
        streaks = [:]
        notResponding = []
    }
}
