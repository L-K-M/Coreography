import Foundation
import CoreographyKit

/// One app's activity over a selected range.
public struct AppRangeTotal: Identifiable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let cpuSeconds: Double
    public let diskBytes: Double
    /// Some member was unreadable in some sample, so the totals are lower bounds.
    public let isLowerBound: Bool
}

/// Per-app activity per process interval for the live hour (plan: the
/// observed-app ledger). Every active app is kept, not just the top
/// contributors, so a range can rank the tail too.
///
/// ```text
/// process sample:   t0 ──── t1 ──── t2 ──── t3
/// ledger interval:       [t0,t1] [t1,t2] [t2,t3]  each: app -> cpu-s, bytes
/// range report:     whole intervals whose midpoint lies in the range
/// ```
struct AppLedger: Sendable {
    struct Entry: Sendable {
        let app: Int
        let cpuSeconds: Double
        let diskBytes: Double
        let isLowerBound: Bool
    }

    struct Interval: Sendable {
        let start: Date
        let end: Date
        let cores: Double
        let entries: [Entry]
    }

    private static let percentScale = 100.0
    let capacity: Int
    private(set) var names: [String] = []
    private var indices: [String: Int] = [:]
    private(set) var intervals: [Interval] = []
    private var previousTime: Date?

    init(capacity: Int) { self.capacity = capacity }

    /// Integrate each app's rates over the sample's real interval: a rate is
    /// a delta over that interval, so rate × interval restores the delta.
    mutating func record(_ processes: CapturedProcesses, logicalCPUCount: Int?) {
        let end = processes.stamp.wallTime
        defer { previousTime = end }
        guard let start = previousTime, processes.continuity == .continuous, end > start else { return }
        let seconds = end.timeIntervalSince(start)
        let cores = Double(logicalCPUCount ?? 0)

        var entries: [Entry] = []
        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .name, grouping: .app)
        for row in rows {
            let disk = ProcessGroups.total([row.diskReadBytesPerSecond, row.diskWriteBytesPerSecond], overlap: nil)
            let cpuSeconds = cores > 0
                ? (row.cpuPercentOfMachine.numericValue ?? 0) / Self.percentScale * cores * seconds : 0
            let diskBytes = (disk.numericValue ?? 0) * seconds
            guard cpuSeconds > 0 || diskBytes > 0 else { continue }
            entries.append(Entry(
                app: index(of: row.name), cpuSeconds: cpuSeconds, diskBytes: diskBytes,
                isLowerBound: row.cpuPercentOfMachine.availability != .measured || disk.availability != .measured
            ))
        }
        intervals.append(Interval(start: start, end: end, cores: cores, entries: entries))
        if intervals.count > capacity { intervals.removeFirst(intervals.count - capacity) }
    }

    func totals(in range: ClosedRange<Date>) -> (apps: [AppRangeTotal], covered: ClosedRange<Date>?) {
        let included = intervals.filter {
            range.contains($0.start.addingTimeInterval($0.end.timeIntervalSince($0.start) / 2))
        }
        guard let first = included.first, let last = included.last else { return ([], nil) }

        var cpu: [Int: Double] = [:]
        var disk: [Int: Double] = [:]
        var lowerBound: Set<Int> = []
        for entry in included.flatMap(\.entries) {
            cpu[entry.app, default: 0] += entry.cpuSeconds
            disk[entry.app, default: 0] += entry.diskBytes
            if entry.isLowerBound { lowerBound.insert(entry.app) }
        }
        let apps = Set(cpu.keys).union(disk.keys).map { app in
            AppRangeTotal(
                name: names[app], cpuSeconds: cpu[app] ?? 0, diskBytes: disk[app] ?? 0,
                isLowerBound: lowerBound.contains(app)
            )
        }
        return (apps, first.start...last.end)
    }

    /// One app's CPU share (% of machine) and disk rate per interval, at
    /// interval ends. An absent entry is idle (0); a missing interval is a gap.
    func series(for name: String) -> (cpu: [DashboardPoint], disk: [DashboardPoint]) {
        let app = indices[name]
        var cpu: [DashboardPoint] = []
        var disk: [DashboardPoint] = []
        var segment = 0
        var previousEnd: Date?
        for interval in intervals {
            if let previousEnd, previousEnd != interval.start { segment += 1 }
            previousEnd = interval.end
            let seconds = interval.end.timeIntervalSince(interval.start)
            let entry = app.flatMap { app in interval.entries.first { $0.app == app } }
            let id = UUID()
            if interval.cores > 0 {
                let share = (entry?.cpuSeconds ?? 0) / (seconds * interval.cores) * Self.percentScale
                cpu.append(DashboardPoint(id: id, time: interval.end, value: share, segment: segment))
            }
            disk.append(DashboardPoint(id: id, time: interval.end, value: (entry?.diskBytes ?? 0) / seconds, segment: segment))
        }
        return (cpu, disk)
    }

    private mutating func index(of name: String) -> Int {
        if let existing = indices[name] { return existing }
        names.append(name)
        indices[name] = names.count - 1
        return names.count - 1
    }
}
