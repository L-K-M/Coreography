import Foundation
import CoreographyDrivers

/// The Mac's energy preference as sampling cares about it.
public enum EnergyMode: Sendable {
    case normal, lowPower
}

public struct EnergyModeMonitor: Sendable {
    private let driver: any EnergyModeReading

    public init() { self.init(driver: EnergyModeDriver()) }

    init(driver: any EnergyModeReading) { self.driver = driver }

    public func current() -> EnergyMode { driver.isLowPowerModeEnabled() ? .lowPower : .normal }
}
