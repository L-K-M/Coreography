import Foundation
import CoreographyKit

/// What a person's own alert rule can watch: the readings history records,
/// so a rule sees the primary interface, the only storage device and the
/// only GPU, as the stored lanes do. Raw values are the saved format, so a
/// renamed case must keep its raw value.
public enum AlertMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, memoryUsed, gpuBusy, hottestCelsius, systemPower, batteryCharge
    case networkReceived, networkSent, diskRead, diskWritten

    public var id: Self { self }

    public var name: String {
        switch self {
        case .cpu: "CPU"
        case .memoryUsed: "Memory used"
        case .gpuBusy: "GPU"
        case .hottestCelsius: "Hottest sensor"
        case .systemPower: "System power"
        case .batteryCharge: "Battery"
        case .networkReceived: "Download"
        case .networkSent: "Upload"
        case .diskRead: "Disk read"
        case .diskWritten: "Disk write"
        }
    }

    /// The unit thresholds are typed in.
    public var unit: String {
        switch self {
        case .cpu, .gpuBusy, .batteryCharge: "%"
        case .memoryUsed: "GB"
        case .hottestCelsius: "°C"
        case .systemPower: "W"
        case .networkReceived, .networkSent, .diskRead, .diskWritten: "MB/s"
        }
    }

    /// Stored readings per display unit: bytes per GB, bytes per second per MB/s.
    var scale: Double {
        switch self {
        case .memoryUsed: 1e9
        case .networkReceived, .networkSent, .diskRead, .diskWritten: 1e6
        case .cpu, .gpuBusy, .batteryCharge, .hottestCelsius, .systemPower: 1
        }
    }

    var lane: AlertLane {
        switch self {
        case .cpu: .cpu
        case .memoryUsed: .memory
        case .gpuBusy: .gpu
        case .hottestCelsius: .thermal
        case .systemPower, .batteryCharge: .power
        case .networkReceived, .networkSent: .network
        case .diskRead, .diskWritten: .disk
        }
    }

    init?(_ metric: HistoryMetric) {
        switch metric {
        case .cpu: self = .cpu
        case .memoryUsed: self = .memoryUsed
        case .gpuBusy: self = .gpuBusy
        case .hottestCelsius: self = .hottestCelsius
        case .systemPower: self = .systemPower
        case .batteryCharge: self = .batteryCharge
        case .networkReceived: self = .networkReceived
        case .networkSent: self = .networkSent
        case .diskRead: self = .diskRead
        case .diskWritten: self = .diskWritten
        default: return nil
        }
    }
}

/// A person's rule (plan: "a metric, a threshold, a duration and an action,
/// with hysteresis"). It raises once the reading has stayed past
/// `threshold` for `raiseAfter` and clears once it has stayed back past
/// `clearThreshold` for `clearAfter`; in between, the state holds.
///
/// ```text
/// above 90, clear 70:  ──raise──> 90 ════ holds ════ 70 <──clear──
/// ```
public struct CustomAlertRule: Codable, Equatable, Identifiable, Sendable {
    public enum Direction: String, Codable, CaseIterable, Sendable { case above, below }

    /// Waits longer than an hour are not alerts.
    static let maximumSeconds: TimeInterval = 3600
    /// Rules a person can keep.
    public static let maximumCount = 20

    public var id = UUID()
    public var metric: AlertMetric
    public var direction: Direction
    /// In the metric's unit, e.g. GB or MB/s.
    public var threshold: Double
    public var clearThreshold: Double
    public var raiseAfter: TimeInterval
    public var clearAfter: TimeInterval
    /// Tinting the lane and marking the timeline are always on; this adds a notification.
    public var notifies: Bool

    /// The plan's example, for a new rule.
    public static var starter: CustomAlertRule {
        CustomAlertRule(metric: .cpu, direction: .above, threshold: 90, clearThreshold: 70, raiseAfter: 10, clearAfter: 30, notifies: false)
    }

    /// Example: "CPU above 90 % for 10 s".
    public var title: String {
        "\(metric.name) \(direction.rawValue) \(Self.number(threshold)) \(metric.unit) for \(Self.number(raiseAfter)) s"
    }

    /// Durations within an hour, and a clear threshold on the clearing side
    /// of the raise threshold, so every rule can clear. Without a finite
    /// threshold there is no rule (only damaged saved data has none), rather
    /// than one at 0 that would always fire.
    public func normalized() -> CustomAlertRule? {
        guard threshold.isFinite else { return nil }
        var rule = self
        let clear = clearThreshold.isFinite ? clearThreshold : threshold
        rule.clearThreshold = direction == .above ? min(clear, rule.threshold) : max(clear, rule.threshold)
        rule.raiseAfter = Self.seconds(raiseAfter)
        rule.clearAfter = Self.seconds(clearAfter)
        return rule
    }

    var alertRule: AlertRule {
        let rule = self
        return AlertRule(
            id: "custom-\(id.uuidString)", title: title, lane: metric.lane,
            raiseAfter: raiseAfter, clearAfter: clearAfter, notifies: notifies
        ) { inputs, active in
            // Without a recent reading a raised rule heads for clearing, so a stopped sampler cannot hold it.
            guard let reading = inputs.readings[rule.metric] else { return active ? false : nil }
            let value = reading / rule.metric.scale
            // Raised, the rule holds until the reading passes the clear threshold.
            switch (rule.direction, active) {
            case (.above, false): return value > rule.threshold
            case (.above, true): return value >= rule.clearThreshold
            case (.below, false): return value < rule.threshold
            case (.below, true): return value <= rule.clearThreshold
            }
        }
    }

    private static func seconds(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? min(max(value, 0), maximumSeconds) : 0
    }

    /// Whole numbers without a fraction, others to one decimal.
    private static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(format: "%.1f", value)
    }
}

/// The person's rules, saved as JSON; unreadable data reads as no rules.
struct CustomAlertRules {
    static let defaultsKey = "customAlertRules"
    static let maximumCount = CustomAlertRule.maximumCount
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    var all: [CustomAlertRule] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let rules = try? JSONDecoder().decode([CustomAlertRule].self, from: data) else { return [] }
        return Self.cleaned(rules)
    }

    func save(_ rules: [CustomAlertRule]) {
        guard let data = try? JSONEncoder().encode(Self.cleaned(rules)) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// One rule per id, each normalized, at most `maximumCount`.
    static func cleaned(_ rules: [CustomAlertRule]) -> [CustomAlertRule] {
        var seen: Set<UUID> = []
        let unique = rules.filter { seen.insert($0.id).inserted }.compactMap { $0.normalized() }
        return Array(unique.prefix(maximumCount))
    }
}

/// The newest value of each watchable metric.
enum AlertReadings {
    /// A sampler that stopped must not hold an alert raised on its last value.
    static let maximumAge: TimeInterval = 10

    static func latest(_ samples: [HistorySample], now: Date) -> [AlertMetric: Double] {
        var readings: [AlertMetric: Double] = [:]
        for sample in samples {
            guard let metric = AlertMetric(sample.metric), let value = sample.value,
                  now.timeIntervalSince(sample.time) <= maximumAge else { continue }
            readings[metric] = value
        }
        return readings
    }
}
