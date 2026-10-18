import Foundation

/// One lane of the window, in the plan's default semantic order:
/// compute, cost, pipes, environment.
public enum LaneKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, memory, gpu, power, disk, network, thermal

    public var id: Self { self }
}

/// Graph height; lanes shed header detail as they shrink, never the graph.
public enum LaneSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact, regular, tall

    public var id: Self { self }
}

public enum LaneMove: Sendable {
    case up, down
}

public enum LaneVisibility: Sendable {
    case shown, hidden
}

/// The person's lane order, hidden lanes and sizes (plan: hide, reorder
/// and resize from each lane's menu). Every lane appears in the order
/// exactly once, and at least one stays visible.
public struct LaneLayout: Equatable, Sendable {
    public static let standard = LaneLayout(order: LaneKind.allCases, hidden: [], sizes: [:])
    private static let defaultsKey = "laneLayout"

    public private(set) var order: [LaneKind]
    public private(set) var hidden: Set<LaneKind>
    private var sizes: [LaneKind: LaneSize]

    private init(order: [LaneKind], hidden: Set<LaneKind>, sizes: [LaneKind: LaneSize]) {
        self.order = order
        self.hidden = hidden
        self.sizes = sizes
    }

    public var visible: [LaneKind] { order.filter { !hidden.contains($0) } }

    public func size(of lane: LaneKind) -> LaneSize { sizes[lane] ?? .regular }

    /// Whether the lane can move that way past a visible neighbour.
    public func canMove(_ lane: LaneKind, _ move: LaneMove) -> Bool { neighbour(of: lane, move) != nil }

    /// Swaps the lane with its visible neighbour; hidden lanes keep their places.
    public mutating func move(_ lane: LaneKind, _ move: LaneMove) {
        guard let other = neighbour(of: lane, move),
              let from = order.firstIndex(of: lane), let to = order.firstIndex(of: other) else { return }
        order.swapAt(from, to)
    }

    /// The last visible lane cannot be hidden: an empty window answers nothing.
    public mutating func set(_ lane: LaneKind, _ visibility: LaneVisibility) {
        switch visibility {
        case .shown: hidden.remove(lane)
        case .hidden: if visible != [lane] { hidden.insert(lane) }
        }
    }

    public mutating func set(_ lane: LaneKind, _ size: LaneSize) {
        sizes[lane] = size == .regular ? nil : size
    }

    private func neighbour(of lane: LaneKind, _ move: LaneMove) -> LaneKind? {
        let lanes = visible
        guard let index = lanes.firstIndex(of: lane) else { return nil }
        let target = move == .up ? index - 1 : index + 1
        return lanes.indices.contains(target) ? lanes[target] : nil
    }

    /// Saved layouts from other versions keep their order for known lanes;
    /// unknown names drop out and new lanes join at their default place.
    static func normalized(order: [LaneKind], hidden: Set<LaneKind>, sizes: [LaneKind: LaneSize]) -> LaneLayout {
        var seen: Set<LaneKind> = []
        var kept = order.filter { seen.insert($0).inserted }
        for lane in LaneKind.allCases where !seen.contains(lane) {
            let before = LaneKind.allCases.prefix { $0 != lane }.last { kept.contains($0) }
            let index = before.flatMap { kept.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            kept.insert(lane, at: index)
        }
        let shownSomething = kept.contains { !hidden.contains($0) }
        return LaneLayout(order: kept, hidden: shownSomething ? hidden : [], sizes: sizes.filter { $0.value != .regular })
    }

    private struct Stored: Codable {
        let order: [String]
        let hidden: [String]
        let sizes: [String: String]
    }

    static func saved(in defaults: UserDefaults = .standard) -> LaneLayout {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return standard }
        return normalized(
            order: stored.order.compactMap(LaneKind.init(rawValue:)),
            hidden: Set(stored.hidden.compactMap(LaneKind.init(rawValue:))),
            sizes: Dictionary(uniqueKeysWithValues: stored.sizes.compactMap { key, value in
                LaneKind(rawValue: key).flatMap { lane in LaneSize(rawValue: value).map { (lane, $0) } }
            })
        )
    }

    func save(in defaults: UserDefaults = .standard) {
        let stored = Stored(
            order: order.map(\.rawValue), hidden: hidden.map(\.rawValue).sorted(),
            sizes: Dictionary(uniqueKeysWithValues: sizes.map { ($0.key.rawValue, $0.value.rawValue) })
        )
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.defaultsKey)
    }
}
