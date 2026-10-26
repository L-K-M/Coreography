import Foundation
import CoreographyKit

/// What one strand of the CPU braid stands for.
public enum BraidStrandKind: Hashable, Sendable {
    /// One app, as the ledger groups processes.
    case app(String)
    /// Every other app with activity in the window, together.
    case otherApps(count: Int)
    /// Host CPU no readable process accounts for: other users' processes,
    /// the kernel, and processes too short-lived to sample.
    case unattributed
}

/// One strand: who it is and how much it did over the window.
public struct BraidStrand: Identifiable, Hashable, Sendable {
    public var id: BraidStrandKind { kind }
    public let kind: BraidStrandKind
    /// CPU-seconds over the window's intervals; orders the strands.
    public let cpuSeconds: Double

    /// The app's name, for scope; nil for the grouped and remainder strands.
    public var appName: String? {
        if case .app(let name) = kind { return name }
        return nil
    }
}

/// One ledger interval of the braid: each strand's share of the machine.
public struct BraidColumn: Identifiable, Sendable {
    public var id: Date { end }
    public let start: Date
    public let end: Date
    /// Columns in different segments are separated by a sampling gap.
    public let segment: Int
    /// Percent of the whole machine per strand, in `CPUBraid.strands`
    /// order. Nil where the share is unknown: the remainder without a full
    /// set of measured host readings over the interval.
    public let shares: [Double?]
    /// The host's mean busy share over the interval; nil without a full set
    /// of measured readings.
    public let hostMean: Double?

    /// The moment the lens anchors to when it lands on this interval.
    public var middle: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }

    /// The top of the stack: every known share added up.
    public var total: Double { shares.reduce(0) { $0 + ($1 ?? 0) } }

    /// The apps' shares together exceed the host mean by more than sampling
    /// skew explains, so the remainder's zero hides a disagreement the UI
    /// must state rather than smooth over.
    public var reconciles: Bool {
        guard let hostMean, let remainder = shares.last, remainder == 0 else { return true }
        let apps = shares.dropLast().reduce(0) { $0 + ($1 ?? 0) }
        return apps <= hostMean + CPUBraid.reconcileTolerance
    }
}

/// The CPU lane's total as a braid of per-app strands (plan: cause beside
/// symptom). CPU is the one additive per-app quantity: the apps' shares and
/// the unattributed remainder add up to the host's busy share over each
/// process interval, so stacking them claims nothing the ledger did not
/// record. Memory footprints and GPU time do not add up and are not braided.
///
/// ```text
///  host line ─────╮      ╭────     the host's own 1 s samples, on top
///  unattributed ░░│░░░░░░│░░░░     host mean over the interval − apps, ≥ 0
///  other apps  ▒▒▒│▒▒▒▒▒▒│▒▒▒▒
///  Safari      ▓▓▓│▓▓▓▓▓▓│▓▓▓▓     named strands, biggest at the bottom,
///  Xcode       ███│██████│████     order fixed across the window
///             interval  interval
/// ```
public struct CPUBraid: Identifiable, Sendable {
    /// One per build: the model hands out the same braid until its data
    /// changes, so views can cache what they derive from it.
    public let id = UUID()
    /// Percentage points of skew between host and process sampling that
    /// still count as agreeing; their clocks tick apart by up to a sample.
    static let reconcileTolerance = 1.0
    /// Bottom first: named apps by CPU-seconds, other apps, unattributed.
    public let strands: [BraidStrand]
    /// Oldest first, every interval: an hour holds at most 1,800, and
    /// reducing them to extremes of one series would misplace the others.
    public let columns: [BraidColumn]

    /// The column whose interval holds `time`; nil between intervals.
    public func column(at time: Date) -> BraidColumn? {
        index(at: time).map { columns[$0] }
    }

    /// Arrow keys: the interval `offset` steps from the one holding `time`,
    /// or the newest when nothing is inspected yet; nil past either end.
    public func column(from time: Date?, offset: Int) -> BraidColumn? {
        guard let time, let current = index(at: time) else { return columns.last }
        let target = current + offset
        return columns.indices.contains(target) ? columns[target] : nil
    }

    /// Option-arrow keys: the next interval, in the given direction, whose
    /// total tops both neighbours in its segment; a plateau counts once, and
    /// an interval at a gap's edge has no neighbour there, so it is no peak.
    public func peak(from time: Date?, forward: Bool) -> BraidColumn? {
        let start = time.flatMap(index(at:)) ?? (forward ? -1 : columns.count)
        let order = forward ? Array(stride(from: start + 1, to: columns.count, by: 1)) : Array(stride(from: start - 1, through: 0, by: -1))
        return order.first { index in
            let column = columns[index]
            guard index > 0, index + 1 < columns.count, columns[index - 1].segment == column.segment,
                  columns[index + 1].segment == column.segment else { return false }
            return column.total > columns[index - 1].total && column.total >= columns[index + 1].total
        }.map { columns[$0] }
    }

    /// The column holding `time`, by binary search; nil between intervals.
    private func index(at time: Date) -> Int? {
        var low = 0
        var high = columns.count
        while low < high {
            let middle = (low + high) / 2
            if columns[middle].end < time { low = middle + 1 } else { high = middle }
        }
        guard columns.indices.contains(low), columns[low].start <= time else { return nil }
        return low
    }
}

enum Braids {
    /// Named strands before the rest fold into "other apps": enough for the
    /// usual culprits, few enough to tell apart.
    static let namedStrands = 5
    private static let percentScale = 100.0
    /// Clock jitter allowed when deciding host readings cover an interval.
    private static let coverageTolerance = 0.001

    /// - Parameters:
    ///   - host: the host's CPU readings, oldest first.
    ///   - pinned: an app kept as its own strand even outside the top, so a
    ///     scoped app never hides inside "other apps".
    static func cpu(
        intervals: [AppLedger.Interval], names: [String], host: [(time: Date, cpu: MetricReading)],
        window: ClosedRange<Date>, pinned: String? = nil
    ) -> CPUBraid? {
        // Without a core count an interval's CPU-seconds cannot become a share.
        let included = intervals.filter {
            $0.cores > 0 && $0.end > $0.start && $0.end > window.lowerBound && $0.start < window.upperBound
        }
        guard !included.isEmpty else { return nil }

        // Rank by the CPU-seconds inside the window: an interval the window
        // cuts counts in proportion, as if its rate held throughout.
        var seconds: [Int: Double] = [:]
        for interval in included {
            let inside = min(interval.end, window.upperBound).timeIntervalSince(max(interval.start, window.lowerBound))
            let weight = inside / interval.end.timeIntervalSince(interval.start)
            for entry in interval.entries { seconds[entry.app, default: 0] += entry.cpuSeconds * weight }
        }
        let active = seconds.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : names[$0.key] < names[$1.key] }
            .map(\.key)
        var named = Array(active.prefix(namedStrands))
        if let pinned, let app = active.first(where: { names[$0] == pinned }), !named.contains(app) {
            named.append(app)
        }
        let others = active.filter { !named.contains($0) }

        var strands = named.map { BraidStrand(kind: .app(names[$0]), cpuSeconds: seconds[$0] ?? 0) }
        if !others.isEmpty {
            strands.append(BraidStrand(
                kind: .otherApps(count: others.count), cpuSeconds: others.reduce(0) { $0 + (seconds[$1] ?? 0) }
            ))
        }

        let means = hostMeans(over: included, host: host)
        var columns: [BraidColumn] = []
        var unattributedSeconds = 0.0
        var segment = 0
        var previousEnd: Date?
        for (interval, hostMean) in zip(included, means) {
            if let previousEnd, previousEnd != interval.start { segment += 1 }
            previousEnd = interval.end
            let length = interval.end.timeIntervalSince(interval.start)
            func share(_ cpuSeconds: Double) -> Double { cpuSeconds / (length * interval.cores) * percentScale }

            var byApp: [Int: Double] = [:]
            for entry in interval.entries { byApp[entry.app, default: 0] += entry.cpuSeconds }
            var shares: [Double?] = named.map { share(byApp[$0] ?? 0) }
            if !others.isEmpty { shares.append(share(others.reduce(0) { $0 + (byApp[$1] ?? 0) })) }
            // Sampling skew can put the readable processes above the host mean; never below zero.
            let appsShare = share(byApp.values.reduce(0, +))
            let remainder = hostMean.map { max($0 - appsShare, 0) }
            unattributedSeconds += (remainder ?? 0) / percentScale * length * interval.cores
            shares.append(remainder)
            columns.append(BraidColumn(
                start: interval.start, end: interval.end, segment: segment, shares: shares, hostMean: hostMean
            ))
        }
        strands.append(BraidStrand(kind: .unattributed, cpuSeconds: unattributedSeconds))
        return CPUBraid(strands: strands, columns: columns)
    }

    /// Each interval's host CPU, weighted by time: a host reading is the
    /// busy share since the reading before it, so it covers that span.
    /// Nil unless measured spans cover the whole interval; the next reading
    /// may be needed to finish it, and nothing is extrapolated.
    ///
    /// ```text
    /// host spans:   (──40 %──](──60 %──](──20 %──]
    /// interval:          (──────────────]         1 s at 40 %, 2 s at 60 %
    /// mean:              (40 + 120) / 3 = 53.3 %
    /// ```
    static func hostMeans(over intervals: [AppLedger.Interval], host: [(time: Date, cpu: MetricReading)]) -> [Double?] {
        // A reading's span starts at the reading before it, whatever that one read.
        var spans: [(start: Date, end: Date, value: Double?)] = []
        for index in host.indices.dropFirst() {
            let reading = host[index].cpu
            let value = reading.availability == .measured ? reading.numericValue : nil
            spans.append((host[index - 1].time, host[index].time, value))
        }

        var means: [Double?] = []
        var first = 0
        for interval in intervals {
            while first < spans.count, spans[first].end <= interval.start { first += 1 }
            var weighted = 0.0
            var covered = 0.0
            var complete = true
            var index = first
            while index < spans.count, spans[index].start < interval.end {
                let overlap = min(spans[index].end, interval.end).timeIntervalSince(max(spans[index].start, interval.start))
                if overlap > 0 {
                    if let value = spans[index].value {
                        weighted += value * overlap
                        covered += overlap
                    } else {
                        complete = false
                    }
                }
                index += 1
            }
            let length = interval.end.timeIntervalSince(interval.start)
            means.append(complete && covered >= length - coverageTolerance ? weighted / length : nil)
        }
        return means
    }
}
