import Foundation

public enum SensorDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case notPresent
    case restricted(code: Int32)
    case systemCall(operation: String, code: Int32)
}

/// One decoded SMC key value in its natural unit (°C, W, rpm).
public struct RawSensorValue: Equatable, Sendable {
    public let key: String
    public let value: Double

    public init(key: String, value: Double) {
        self.key = key
        self.value = value
    }
}

public struct RawFan: Equatable, Sendable {
    public let index: Int
    public let rpm: Double?
    public let maximumRPM: Double?

    public init(index: Int, rpm: Double?, maximumRPM: Double?) {
        self.index = index
        self.rpm = rpm
        self.maximumRPM = maximumRPM
    }
}

public struct RawSensors: Sendable {
    /// System power rails present on this Mac, keyed by SMC key (PSTR, PDTR).
    public let power: [RawSensorValue]
    public let temperatures: [RawSensorValue]
    public let fans: [RawFan]
    /// Key discovery stopped at its bound; more sensors may exist.
    public let discoveryTruncated: Bool

    public init(power: [RawSensorValue], temperatures: [RawSensorValue], fans: [RawFan], discoveryTruncated: Bool) {
        self.power = power
        self.temperatures = temperatures
        self.fans = fans
        self.discoveryTruncated = discoveryTruncated
    }
}

public struct RawSensorSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let sensors: Result<RawSensors, SensorDriverError>

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date,
        sensors: Result<RawSensors, SensorDriverError>
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.sensors = sensors
    }
}

public protocol SensorSampleReading: Sendable {
    func read() async -> RawSensorSnapshot
}

/// Decode SMC data types. `spXY` is signed and `fpXY` unsigned fixed point
/// with Y (hex) fraction bits, both big-endian; `flt ` is a host-order
/// IEEE float (little-endian on every supported Mac).
///
/// Example: sp78 `0x2A 0x80` = 0x2A80 / 2^8 = 42.5.
enum SMCValueDecoder {
    private static let fixedPointWidth = 2

    static func number(type: String, bytes: [UInt8]) -> Double? {
        let code = Array(type.utf8)
        guard code.count == 4 else { return nil }

        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case "ui8 ", "si8 ":
            guard let byte = bytes.first else { return nil }
            return type == "ui8 " ? Double(byte) : Double(Int8(bitPattern: byte))
        case "ui16", "si16":
            guard let raw = bigEndian16(bytes) else { return nil }
            return type == "ui16" ? Double(raw) : Double(Int16(bitPattern: raw))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            break
        }

        // Fixed point: "sp" or "fp", then integer and fraction bit counts in hex.
        let prefix = String(decoding: code[0..<2], as: UTF8.self)
        guard prefix == "sp" || prefix == "fp",
              let fraction = Int(String(decoding: code[3..<4], as: UTF8.self), radix: 16),
              let raw = bigEndian16(bytes) else { return nil }
        let scale = Double(1 << fraction)
        return prefix == "sp" ? Double(Int16(bitPattern: raw)) / scale : Double(raw) / scale
    }

    private static func bigEndian16(_ bytes: [UInt8]) -> UInt16? {
        guard bytes.count >= fixedPointWidth else { return nil }
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }
}
