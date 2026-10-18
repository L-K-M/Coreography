import Foundation
import CoreographyKit

/// One app's activity over a selected range.
public struct AppRangeTotal: Identifiable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let cpuSeconds: Double
    public let diskBytes: Double
    /// TCP and UDP bytes in and out; nil when no interval in the range read network.
    public let networkBytes: Double?
    /// Some member was unreadable in some sample, so the totals are lower bounds.
    public let isLowerBound: Bool

    init(name: String, cpuSeconds: Double, diskBytes: Double, networkBytes: Double? = nil, isLowerBound: Bool) {
        self.name = name
        self.cpuSeconds = cpuSeconds
        self.diskBytes = diskBytes
        self.networkBytes = networkBytes
        self.isLowerBound = isLowerBound
    }
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
        var networkBytes: Double = 0
        let isLowerBound: Bool
    }

    struct Interval: Sendable {
        let start: Date
        let end: Date
        let cores: Double
        var coversNetwork = false
        let entries: [Entry]
    }

    private static let percentScale = 100.0
    let capacity: Int
    private(set) var names: [String] = []
    private var indices: [String: Int] = [:]
    private(set) var intervals: [Interval] = []
    private var previousTime: Date?

    init(capacity: Int) { self.capacity = capacity }

    /// Rebuild from stored intervals, oldest first.
    init(stored: [LedgerInterval]) {
        self.init(capacity: max(stored.count, 1))
        for interval in stored {
            let entries = interval.entries.map {
                Entry(
                    app: index(of: $0.app), cpuSeconds: $0.cpuSeconds, diskBytes: $0.diskBytes,
                    networkBytes: $0.networkBytes, isLowerBound: $0.isLowerBound
                )
            }
            intervals.append(Interval(
                start: interval.start, end: interval.end, cores: interval.cores, coversNetwork: interval.coversNetwork, entries: entries
            ))
        }
        previousTime = stored.last?.end
    }

    /// Integrate each app's rates over the sample's real interval: a rate is
    /// a delta over that interval, so rate × interval restores the delta.
    /// Returns the new interval in its stored form, or nil when the sample
    /// opened no interval (the first one, or one after an interruption).
    /// Network counts only with a traffic sample of the same moment; a
    /// process's first interval with traffic has no rate yet and adds nothing.
    @discardableResult
    mutating func record(
        _ processes: CapturedProcesses, traffic: CapturedTraffic? = nil, logicalCPUCount: Int?
    ) -> LedgerInterval? {
        let end = processes.stamp.wallTime
        defer { previousTime = end }
        guard let start = previousTime, processes.continuity == .continuous, end > start else { return nil }
        let seconds = end.timeIntervalSince(start)
        let cores = Double(logicalCPUCount ?? 0)

        var entries: [Entry] = []
        let coversNetwork = traffic.map { $0.unavailableReason == nil } ?? false
        let rows = ProcessGroups.rows(
            in: processes, matching: "", sortedBy: .name, grouping: .app,
            facts: ProcessFacts(traffic: coversNetwork ? traffic : nil)
        )
        for row in rows {
            let disk = ProcessGroups.total([row.diskReadBytesPerSecond, row.diskWriteBytesPerSecond], overlap: nil)
            let share = row.cpuPercentOfMachine.numericValue ?? 0
            // Without a core count, CPU share cannot become CPU-seconds: record a lower bound.
            let cpuSeconds = cores > 0 ? share / Self.percentScale * cores * seconds : 0
            let diskBytes = (disk.numericValue ?? 0) * seconds
            let network = coversNetwork
                ? (ProcessNetwork.total(row.networkReceivedBytesPerSecond, row.networkSentBytesPerSecond) ?? 0) * seconds : 0
            guard cpuSeconds > 0 || diskBytes > 0 || share > 0 || network > 0 else { continue }
            entries.append(Entry(
                app: index(of: row.name), cpuSeconds: cpuSeconds, diskBytes: diskBytes, networkBytes: network,
                isLowerBound: cores <= 0 || row.cpuPercentOfMachine.availability != .measured
                    || disk.availability != .measured
            ))
        }
        intervals.append(Interval(start: start, end: end, cores: cores, coversNetwork: coversNetwork, entries: entries))
        if intervals.count > capacity { intervals.removeFirst(intervals.count - capacity) }
        return LedgerInterval(
            start: start, end: end, cores: cores, coversNetwork: coversNetwork,
            entries: entries.map {
                LedgerEntry(
                    app: names[$0.app], cpuSeconds: $0.cpuSeconds, diskBytes: $0.diskBytes,
                    networkBytes: $0.networkBytes, isLowerBound: $0.isLowerBound
                )
            }
        )
    }

    /// - Parameter cutoff: only intervals ending by then count; stored
    ///   history passes the live ledger's start so no interval counts twice.
    func totals(
        in range: ClosedRange<Date>, endingBy cutoff: Date = .distantFuture
    ) -> (apps: [AppRangeTotal], covered: ClosedRange<Date>?) {
        let included = intervals.filter {
            $0.end <= cutoff && range.contains($0.start.addingTimeInterval($0.end.timeIntervalSince($0.start) / 2))
        }
        guard let first = included.first, let last = included.last else { return ([], nil) }

        var cpu: [Int: Double] = [:]
        var disk: [Int: Double] = [:]
        var network: [Int: Double] = [:]
        var lowerBound: Set<Int> = []
        for entry in included.flatMap(\.entries) {
            cpu[entry.app, default: 0] += entry.cpuSeconds
            disk[entry.app, default: 0] += entry.diskBytes
            network[entry.app, default: 0] += entry.networkBytes
            if entry.isLowerBound { lowerBound.insert(entry.app) }
        }
        // Without one interval that read network, zero would be a claim the ledger cannot make.
        let coversNetwork = included.contains(where: \.coversNetwork)
        let apps = Set(cpu.keys).union(disk.keys).map { app in
            AppRangeTotal(
                name: names[app], cpuSeconds: cpu[app] ?? 0, diskBytes: disk[app] ?? 0,
                networkBytes: coversNetwork ? network[app] ?? 0 : nil, isLowerBound: lowerBound.contains(app)
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

    /// Two totals over disjoint intervals, combined per app.
    static func combine(
        _ older: (apps: [AppRangeTotal], covered: ClosedRange<Date>?),
        _ newer: (apps: [AppRangeTotal], covered: ClosedRange<Date>?)
    ) -> (apps: [AppRangeTotal], covered: ClosedRange<Date>?) {
        var merged: [String: AppRangeTotal] = [:]
        for app in older.apps + newer.apps {
            guard let existing = merged[app.name] else {
                merged[app.name] = app
                continue
            }
            let network = existing.networkBytes == nil && app.networkBytes == nil
                ? nil : (existing.networkBytes ?? 0) + (app.networkBytes ?? 0)
            merged[app.name] = AppRangeTotal(
                name: app.name, cpuSeconds: existing.cpuSeconds + app.cpuSeconds,
                diskBytes: existing.diskBytes + app.diskBytes, networkBytes: network,
                isLowerBound: existing.isLowerBound || app.isLowerBound
            )
        }
        let spans = [older.covered, newer.covered].compactMap { $0 }
        let covered = spans.isEmpty ? nil
            : spans.map(\.lowerBound).min()!...spans.map(\.upperBound).max()!
        return (Array(merged.values), covered)
    }

    private mutating func index(of name: String) -> Int {
        if let existing = indices[name] { return existing }
        names.append(name)
        indices[name] = names.count - 1
        return names.count - 1
    }
}
