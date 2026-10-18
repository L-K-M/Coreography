import Foundation
import CoreFoundation

public enum PowerDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case noBattery
    case unavailable(reason: String)
}

public enum PowerSourceState: String, Codable, Sendable {
    case externalPower
    case battery
}

/// The internal battery's IOPS description (public IOPSKeys.h).
public struct BatteryState: Equatable, Sendable {
    public let chargePercent: Double
    public let powerSource: PowerSourceState?
    public let isCharging: Bool?
    /// macOS estimates; nil while the OS is still calculating or when not applicable.
    public let minutesToEmpty: Int?
    public let minutesToFull: Int?

    public init(
        chargePercent: Double, powerSource: PowerSourceState?, isCharging: Bool?,
        minutesToEmpty: Int?, minutesToFull: Int?
    ) {
        self.chargePercent = chargePercent
        self.powerSource = powerSource
        self.isCharging = isCharging
        self.minutesToEmpty = minutesToEmpty
        self.minutesToFull = minutesToFull
    }
}

/// AppleSmartBattery gas-gauge registry values.
public struct BatteryGauge: Equatable, Sendable {
    public let voltageMillivolts: Int64
    /// Positive while charging, negative while discharging.
    public let amperageMilliamps: Int64
    public let cycleCount: Int64?
    public let designCapacityMilliampHours: Int64?
    public let fullChargeCapacityMilliampHours: Int64?

    public init(
        voltageMillivolts: Int64, amperageMilliamps: Int64, cycleCount: Int64?,
        designCapacityMilliampHours: Int64?, fullChargeCapacityMilliampHours: Int64?
    ) {
        self.voltageMillivolts = voltageMillivolts
        self.amperageMilliamps = amperageMilliamps
        self.cycleCount = cycleCount
        self.designCapacityMilliampHours = designCapacityMilliampHours
        self.fullChargeCapacityMilliampHours = fullChargeCapacityMilliampHours
    }
}

public struct RawPowerSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let battery: Result<BatteryState, PowerDriverError>
    public let gauge: Result<BatteryGauge, PowerDriverError>
    /// The connected adapter's rating, not its draw.
    public let adapterWatts: Result<Double, PowerDriverError>

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date,
        battery: Result<BatteryState, PowerDriverError>, gauge: Result<BatteryGauge, PowerDriverError>,
        adapterWatts: Result<Double, PowerDriverError>
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.battery = battery
        self.gauge = gauge
        self.adapterWatts = adapterWatts
    }
}

public protocol PowerSampleReading: Sendable {
    func read() async -> RawPowerSnapshot
}

/// Decode IOPS descriptions, adapter details and AppleSmartBattery properties.
///
/// IOPS keys are the string values of the public IOPSKeys.h constants; the
/// registry keys are the gas gauge's published property names.
enum PowerSourceDecoder {
    static let typeKey = "Type"
    static let internalBatteryType = "InternalBattery"
    static let currentCapacityKey = "Current Capacity"
    static let maxCapacityKey = "Max Capacity"
    static let isChargingKey = "Is Charging"
    static let powerSourceStateKey = "Power Source State"
    static let acPowerValue = "AC Power"
    static let batteryPowerValue = "Battery Power"
    static let timeToEmptyKey = "Time to Empty"
    static let timeToFullChargeKey = "Time to Full Charge"
    static let adapterWattsKey = "Watts"
    private static let voltageKey = "Voltage"
    private static let amperageKey = "Amperage"
    private static let cycleCountKey = "CycleCount"
    private static let designCapacityKey = "DesignCapacity"
    private static let rawMaxCapacityKey = "AppleRawMaxCapacity"
    private static let percentScale = 100.0

    static func battery(_ descriptions: [[String: Any]]) -> Result<BatteryState, PowerDriverError> {
        guard let battery = descriptions.first(where: { $0[typeKey] as? String == internalBatteryType }) else {
            return .failure(.noBattery)
        }
        guard let current = integer(battery[currentCapacityKey]),
              let maximum = integer(battery[maxCapacityKey]), maximum > 0,
              current >= 0, current <= maximum else {
            return .failure(.unavailable(reason: "Invalid battery capacity"))
        }
        let source: PowerSourceState? = switch battery[powerSourceStateKey] as? String {
        case acPowerValue: .externalPower
        case batteryPowerValue: .battery
        default: nil
        }
        return .success(BatteryState(
            chargePercent: Double(current) / Double(maximum) * percentScale,
            powerSource: source, isCharging: battery[isChargingKey] as? Bool,
            minutesToEmpty: minutes(battery[timeToEmptyKey]),
            minutesToFull: minutes(battery[timeToFullChargeKey])
        ))
    }

    static func gauge(_ properties: [String: Any]) -> Result<BatteryGauge, PowerDriverError> {
        guard let voltage = integer(properties[voltageKey]), voltage > 0,
              let amperage = integer(properties[amperageKey]) else {
            return .failure(.unavailable(reason: "Battery voltage or current is not published"))
        }
        return .success(BatteryGauge(
            voltageMillivolts: voltage, amperageMilliamps: amperage,
            cycleCount: integer(properties[cycleCountKey]).flatMap { $0 >= 0 ? $0 : nil },
            designCapacityMilliampHours: integer(properties[designCapacityKey]).flatMap { $0 > 0 ? $0 : nil },
            fullChargeCapacityMilliampHours: integer(properties[rawMaxCapacityKey]).flatMap { $0 > 0 ? $0 : nil }
        ))
    }

    static func adapterWatts(_ details: [String: Any]?) -> Result<Double, PowerDriverError> {
        guard let details else { return .failure(.unavailable(reason: "No power adapter connected")) }
        guard let watts = integer(details[adapterWattsKey]), watts > 0 else {
            return .failure(.unavailable(reason: "Adapter rating is not published"))
        }
        return .success(Double(watts))
    }

    /// IOPS uses -1 while calculating and 0 when the estimate does not apply.
    private static func minutes(_ value: Any?) -> Int? {
        guard let minutes = integer(value), minutes > 0, let result = Int(exactly: minutes) else { return nil }
        return result
    }

    /// Integral CFNumbers only; booleans and fractional values are rejected.
    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
        let native = unsafeBitCast(number, to: CFNumber.self)
        guard !CFNumberIsFloatType(native) else { return nil }
        return number.int64Value
    }
}
