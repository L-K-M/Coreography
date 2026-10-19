import Foundation

/// How much the HUD shows (plan: one density control, P16). Level 1 is a
/// single value; level 4 adds per-tier, memory, network, battery and fans.
public enum HUDDensity: Int, CaseIterable, Identifiable, Sendable {
    case single = 1, line, block, detailed

    public var id: Self { self }

    /// The next level, wrapping, for the cycle shortcut.
    public var next: HUDDensity { HUDDensity(rawValue: rawValue % HUDDensity.allCases.count + 1) ?? .single }
}

public enum HUDCorner: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var id: Self { self }
}

/// One reading the HUD shows; the app formats it.
public enum HUDItem: Hashable, Sendable {
    /// Absent, not zero, until macOS 27's frame-rate source is wired (S4).
    case frameRate
    case cpu, topTier, gpu, gpuClock, power, temperature, thermalPressure
    case tiers, memoryPressure, swap, network, batteryTime, fans
    case hint
}

/// The HUD's look and behaviour, saved.
public struct HUDSettings: Equatable, Sendable {
    public static let opacityRange = 0.3...1.0
    public static let textScaleRange = 0.8...1.6
    private static let prefix = "hud."

    public var density: HUDDensity = .block
    public var corner: HUDCorner = .topRight
    public var opacity = 0.85
    public var textScale = 1.0
    /// A dark backing behind text for bright scenes.
    public var scrim = true
    /// Clicks pass through to the game; off, the panel can be dragged.
    public var clickThrough = true

    public init() {}

    public static func saved(in defaults: UserDefaults = .standard) -> HUDSettings {
        var settings = HUDSettings()
        if let density = HUDDensity(rawValue: defaults.integer(forKey: prefix + "density")) { settings.density = density }
        if let corner = defaults.string(forKey: prefix + "corner").flatMap(HUDCorner.init(rawValue:)) { settings.corner = corner }
        if defaults.object(forKey: prefix + "opacity") != nil {
            settings.opacity = clamp(defaults.double(forKey: prefix + "opacity"), opacityRange)
        }
        if defaults.object(forKey: prefix + "textScale") != nil {
            settings.textScale = clamp(defaults.double(forKey: prefix + "textScale"), textScaleRange)
        }
        if defaults.object(forKey: prefix + "scrim") != nil { settings.scrim = defaults.bool(forKey: prefix + "scrim") }
        if defaults.object(forKey: prefix + "clickThrough") != nil { settings.clickThrough = defaults.bool(forKey: prefix + "clickThrough") }
        return settings
    }

    public func save(in defaults: UserDefaults = .standard) {
        defaults.set(density.rawValue, forKey: Self.prefix + "density")
        defaults.set(corner.rawValue, forKey: Self.prefix + "corner")
        defaults.set(Self.clamp(opacity, Self.opacityRange), forKey: Self.prefix + "opacity")
        defaults.set(Self.clamp(textScale, Self.textScaleRange), forKey: Self.prefix + "textScale")
        defaults.set(scrim, forKey: Self.prefix + "scrim")
        defaults.set(clickThrough, forKey: Self.prefix + "clickThrough")
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

public enum HUDLayout {
    /// What each level shows. Without a frame-rate source, level 1 shows CPU
    /// and the FPS slot is left out rather than drawn empty.
    public static func items(_ density: HUDDensity, frameRateAvailable: Bool, hasHint: Bool) -> [HUDItem] {
        let lead: [HUDItem] = frameRateAvailable ? [.frameRate] : []
        let hint: [HUDItem] = hasHint ? [.hint] : []
        switch density {
        case .single: return frameRateAvailable ? [.frameRate] : [.cpu]
        case .line: return lead + [.cpu, .gpu, .power, .temperature]
        case .block: return lead + [.cpu, .topTier, .gpu, .gpuClock, .power, .temperature, .thermalPressure] + hint
        case .detailed:
            return lead + [.cpu, .tiers, .gpu, .gpuClock, .power, .temperature, .thermalPressure,
                           .memoryPressure, .swap, .network, .batteryTime, .fans] + hint
        }
    }
}
