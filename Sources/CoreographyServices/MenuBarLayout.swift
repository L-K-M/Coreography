import Foundation

/// A reading the menu bar extra can show.
public enum MenuBarMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, memory, gpu, download, upload, temperature

    public var id: Self { self }
}

public enum MenuBarStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case value, graph, both

    public var id: Self { self }
}

/// One menu bar item (plan: up to three, each a value, a sparkline or both).
public struct MenuBarItem: Codable, Hashable, Identifiable, Sendable {
    public var metric: MenuBarMetric
    public var style: MenuBarStyle

    public var id: MenuBarMetric { metric }

    public init(metric: MenuBarMetric, style: MenuBarStyle) {
        self.metric = metric
        self.style = style
    }
}

public enum MenuBarLayout {
    public static let maximumItems = 3
    public static let defaultItems = [MenuBarItem(metric: .cpu, style: .value)]
    private static let defaultsKey = "menuBarItems"

    /// At most three, one per metric, never empty.
    public static func normalized(_ items: [MenuBarItem]) -> [MenuBarItem] {
        var seen: Set<MenuBarMetric> = []
        let unique = items.filter { seen.insert($0.metric).inserted }
        let kept = Array(unique.prefix(maximumItems))
        return kept.isEmpty ? defaultItems : kept
    }

    static func saved(in defaults: UserDefaults = .standard) -> [MenuBarItem] {
        guard let data = defaults.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([MenuBarItem].self, from: data) else { return defaultItems }
        return normalized(items)
    }

    static func save(_ items: [MenuBarItem], in defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(normalized(items)), forKey: defaultsKey)
    }
}
