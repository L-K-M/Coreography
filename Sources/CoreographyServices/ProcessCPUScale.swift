import Foundation

/// How per-process CPU reads (plan: whole machine by default, or `top`'s
/// one core = 100 %, where a process using four cores shows 400 %).
public enum ProcessCPUScale: String, CaseIterable, Identifiable, Sendable {
    case machine, oneCore

    public var id: Self { self }

    private static let defaultsKey = "processCPUScale"

    /// The multiplier from a whole-machine share to this scale.
    public func factor(logicalCPUs: Int) -> Double {
        switch self {
        case .machine: 1
        case .oneCore: Double(max(logicalCPUs, 1))
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> ProcessCPUScale {
        defaults.string(forKey: defaultsKey).flatMap(ProcessCPUScale.init(rawValue:)) ?? .machine
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
