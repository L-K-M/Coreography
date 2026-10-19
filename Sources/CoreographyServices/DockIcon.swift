import Foundation

/// What the Dock icon shows (plan: an optional live CPU or memory graph,
/// as Activity Monitor offers). Saved; the app icon is the default.
public enum DockIconStyle: String, CaseIterable, Identifiable, Sendable {
    case appIcon, cpu, memory

    public var id: Self { self }

    private static let defaultsKey = "dockIcon"

    static func saved(in defaults: UserDefaults = .standard) -> DockIconStyle {
        defaults.string(forKey: defaultsKey).flatMap(DockIconStyle.init(rawValue:)) ?? .appIcon
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    /// The lane the graph draws; nil for the app icon.
    public var metric: DashboardMetric? {
        switch self {
        case .appIcon: nil
        case .cpu: .cpu
        case .memory: .memory
        }
    }
}
