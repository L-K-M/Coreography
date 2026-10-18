import Foundation
import CoreographyKit

/// History retention presets (plan: presets with their disk cost shown,
/// under a hard size cap and hard time caps). The size cap holds for
/// every preset.
public enum HistoryRetention: String, CaseIterable, Identifiable, Sendable {
    case compact, standard, extended

    public var id: Self { self }

    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86_400
    private static let defaultsKey = "historyRetention"
    // Typical bytes per hour kept, from row sizes: 1 s readings of 17
    // series plus two-second app-ledger intervals, and 10 s buckets.
    private static let recentBytesPerHour = 3.7e6
    private static let dayBytesPerHour = 0.3e6

    var plan: RetentionPlan {
        switch self {
        case .compact: RetentionPlan(recent: Self.hour, day: Self.day)
        case .standard: RetentionPlan(recent: HistoryStore.retention, day: HistoryStore.dayRetention)
        case .extended: RetentionPlan(recent: 12 * Self.hour, day: 14 * Self.day)
        }
    }

    /// Hours of 1 s readings and app ledger.
    public var detailedHours: Int { Int(plan.recent / Self.hour) }
    /// Days of 10 s history.
    public var summaryDays: Int { Int(plan.day / Self.day) }

    /// About how much disk the preset fills once full: an estimate from
    /// typical row sizes, shown beside the measured size.
    public var estimatedBytes: Int64 {
        Int64(plan.recent / Self.hour * Self.recentBytesPerHour + plan.day / Self.hour * Self.dayBytesPerHour)
    }

    /// The hard size cap every preset stays under.
    public static var sizeCap: Int64 { HistoryStore.maximumBytes }

    /// The longest 1 s retention any preset keeps; readers clamp to it.
    static var longestRecent: TimeInterval { allCases.map(\.plan.recent).max() ?? HistoryStore.retention }

    /// The saved choice, or the plan's defaults.
    static func saved(in defaults: UserDefaults = .standard) -> HistoryRetention {
        defaults.string(forKey: defaultsKey).flatMap(HistoryRetention.init(rawValue:)) ?? .standard
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
