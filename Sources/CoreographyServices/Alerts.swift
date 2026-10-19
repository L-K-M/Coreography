import Foundation
import CoreographyKit

/// System notification delivery for the app; command-line hosts pass none.
public typealias AlertNotifications = AlertDelivery

/// Lanes an alert can tint.
public enum AlertLane: String, Sendable {
    case memory, thermal, power, disk
}

/// A rule is a condition, a duration and an action, with hysteresis
/// (plan: "CPU above 90% for 10 s, clear below 70% for 30 s").
public struct AlertRule: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let lane: AlertLane
    public let raiseAfter: TimeInterval
    public let clearAfter: TimeInterval
    /// Most rules tint silently; only actionable ones notify.
    public let notifies: Bool
    /// true raises, false clears, nil is unknown and changes nothing.
    let condition: @Sendable (AlertInputs) -> Bool?
}

/// The readings rules look at, taken from the newest frames.
struct AlertInputs: Sendable {
    let memoryPressure: MemoryPressureLevel?
    let thermalPressure: ThermalPressureLevel?
    let batteryPercent: Double?
    let onBattery: Bool?
    /// Available share of the startup volume, 0...1.
    var startupFreeFraction: Double? = nil
}

/// One transition, for markers and notifications.
public struct AlertEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case raised, cleared }
    public let ruleID: String
    public let kind: Kind
    public let time: Date
}

enum AlertRules {
    private static let lowBatteryPercent = 15.0
    private static let lowStartupFreeFraction = 0.10

    /// The plan's shipped rules.
    static let shipped: [AlertRule] = [
        AlertRule(id: "memory-critical", title: "Critical memory pressure", lane: .memory,
                  raiseAfter: 30, clearAfter: 30, notifies: true) { inputs in
            inputs.memoryPressure.map { $0 == .critical }
        },
        AlertRule(id: "thermal-serious", title: "Heavy thermal pressure", lane: .thermal,
                  raiseAfter: 30, clearAfter: 30, notifies: false) { inputs in
            inputs.thermalPressure.map { $0.rawValue >= ThermalPressureLevel.heavy.rawValue }
        },
        AlertRule(id: "battery-low", title: "Battery under 15% while discharging", lane: .power,
                  raiseAfter: 0, clearAfter: 30, notifies: true) { inputs in
            guard let percent = inputs.batteryPercent, let onBattery = inputs.onBattery else { return nil }
            return onBattery && percent < lowBatteryPercent
        },
        AlertRule(id: "startup-disk-low", title: "Startup disk under 10% free", lane: .disk,
                  raiseAfter: 0, clearAfter: 60, notifies: true) { inputs in
            inputs.startupFreeFraction.map { $0 < lowStartupFreeFraction }
        }
    ]
}

/// Debounced rule state. A condition must hold for `raiseAfter` to raise and
/// stay false for `clearAfter` to clear; unknown readings pause both clocks.
struct AlertEngine: Sendable {
    private struct RuleState: Sendable {
        var active = false
        /// When the condition started disagreeing with the current state.
        var pendingSince: Date?
    }

    let rules: [AlertRule]
    private var states: [String: RuleState] = [:]

    init(rules: [AlertRule]) { self.rules = rules }

    var activeRuleIDs: Set<String> { Set(states.filter(\.value.active).keys) }

    mutating func evaluate(_ inputs: AlertInputs, at time: Date) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for rule in rules {
            var state = states[rule.id] ?? RuleState()
            defer { states[rule.id] = state }
            guard let holds = rule.condition(inputs) else {
                state.pendingSince = nil
                continue
            }
            guard holds != state.active else {
                state.pendingSince = nil
                continue
            }
            let since = state.pendingSince ?? time
            state.pendingSince = since
            let wait = holds ? rule.raiseAfter : rule.clearAfter
            guard time.timeIntervalSince(since) >= wait else { continue }
            state.active = holds
            state.pendingSince = nil
            events.append(AlertEvent(ruleID: rule.id, kind: holds ? .raised : .cleared, time: time))
        }
        return events
    }
}

/// Rate limits notifications per rule and collapses repeats (plan: cooldown).
struct AlertCooldown: Sendable {
    static let interval: TimeInterval = 15 * 60
    private var lastSent: [String: Date] = [:]

    mutating func admit(_ ruleID: String, at time: Date) -> Bool {
        if let last = lastSent[ruleID], time.timeIntervalSince(last) < Self.interval { return false }
        lastSent[ruleID] = time
        return true
    }
}

/// Which of the person's Shortcuts each rule runs when it raises (plan:
/// alert actions); saved by rule id.
struct AlertShortcuts {
    private static let defaultsKey = "alertShortcuts"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    var all: [String: String] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }

    /// A blank or nil name removes the action.
    func set(_ name: String?, for ruleID: String) -> [String: String] {
        var current = all
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        current[ruleID] = trimmed.isEmpty ? nil : trimmed
        defaults.set(current, forKey: Self.defaultsKey)
        return current
    }
}
