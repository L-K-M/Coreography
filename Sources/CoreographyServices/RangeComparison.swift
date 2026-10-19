import Foundation

/// Two selected ranges side by side (plan P7: Command-drag a second range
/// to compare two windows). Ranges may differ in length, so apps compare
/// by rate over the time the ledger covered: average cores and bytes per
/// second, not raw totals.
public struct RangeComparison: Sendable {
    public struct AppChange: Identifiable, Equatable, Sendable {
        public var id: String { app }
        public let app: String
        /// Average cores busy over each range's covered time.
        public let firstCores: Double
        public let secondCores: Double
        public let firstDiskBytesPerSecond: Double
        public let secondDiskBytesPerSecond: Double
        /// Either range counted only readable members.
        public let isLowerBound: Bool

        public var coresChange: Double { secondCores - firstCores }
    }

    public static let changeLimit = 5
    /// Smaller changes are noise at sampling resolution.
    static let minimumCoresChange = 0.01

    public let first: RangeReport
    public let second: RangeReport
    /// Largest CPU changes first, at most `changeLimit`; empty when a range has no coverage.
    public let changes: [AppChange]

    /// Both ranges hold process samples, so an empty `changes` means stable apps.
    public var coversBoth: Bool { first.covered != nil && second.covered != nil }

    public var cpuMeanChange: Double? {
        guard let first = first.cpuMeanPercent, let second = second.cpuMeanPercent else { return nil }
        return second - first
    }

    public var memoryPeakChange: Double? {
        guard let first = first.memoryPeakBytes, let second = second.memoryPeakBytes else { return nil }
        return second - first
    }

    static func make(first: RangeReport, second: RangeReport) -> RangeComparison {
        guard let firstSpan = first.covered.map(seconds), let secondSpan = second.covered.map(seconds),
              firstSpan > 0, secondSpan > 0 else {
            return RangeComparison(first: first, second: second, changes: [])
        }
        let before = Dictionary(first.apps.map { ($0.name, $0) }) { lhs, _ in lhs }
        let after = Dictionary(second.apps.map { ($0.name, $0) }) { lhs, _ in lhs }
        var all: [AppChange] = []
        for app in Set(before.keys).union(after.keys) {
            let old = before[app]
            let new = after[app]
            let change = AppChange(
                app: app,
                firstCores: (old?.cpuSeconds ?? 0) / firstSpan,
                secondCores: (new?.cpuSeconds ?? 0) / secondSpan,
                firstDiskBytesPerSecond: (old?.diskBytes ?? 0) / firstSpan,
                secondDiskBytesPerSecond: (new?.diskBytes ?? 0) / secondSpan,
                isLowerBound: (old?.isLowerBound ?? false) || (new?.isLowerBound ?? false)
            )
            if abs(change.coresChange) >= minimumCoresChange { all.append(change) }
        }
        let changes = all.sorted { lhs, rhs in
            let left = abs(lhs.coresChange)
            let right = abs(rhs.coresChange)
            return left != right ? left > right : lhs.app < rhs.app
        }
        return RangeComparison(first: first, second: second, changes: Array(changes.prefix(changeLimit)))
    }

    private static func seconds(_ range: ClosedRange<Date>) -> TimeInterval {
        range.upperBound.timeIntervalSince(range.lowerBound)
    }
}
