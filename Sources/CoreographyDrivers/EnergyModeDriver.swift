import Foundation

public protocol EnergyModeReading: Sendable {
    /// Whether Low Power Mode is on (System Settings > Battery).
    func isLowPowerModeEnabled() -> Bool
}

/// Reads the public ProcessInfo flag; a property read, cheap enough for every tick.
public struct EnergyModeDriver: EnergyModeReading {
    public init() {}

    public func isLowPowerModeEnabled() -> Bool {
        #if os(macOS)
        ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        false
        #endif
    }
}
