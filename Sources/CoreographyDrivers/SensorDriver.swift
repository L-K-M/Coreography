import Foundation
import Dispatch

#if os(macOS)
import Darwin
import CoreographySystem
#endif

/// Reads temperatures, fans and system power rails from AppleSMC.
///
/// Keys are discovered once (thousands of index reads), then each sample
/// reads only the keys found. Read-only: no SMC write is ever issued.
public actor SensorDriver: SensorSampleReading {
    private static let keyCapacity: UInt32 = 8192
    private static let maximumFans = 10
    private static let powerKeys = ["PSTR", "PDTR"]
    private static let temperatureTypes: Set<String> = ["flt ", "sp78"]
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.sensor-sampling")
    private let clockID = UUID()
    private var connection: UInt32 = 0
    private var openFailure: SensorDriverError?
    private var temperatureKeys: [String]?
    private var discoveryTruncated = false

    public init() {}

    deinit {
        #if os(macOS)
        coreo_smc_close(connection)
        #endif
    }

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func read() async -> RawSensorSnapshot {
        let sensors = readSensors()
        return RawSensorSnapshot(
            clockID: clockID, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            wallTime: Date(), sensors: sensors
        )
    }

    private func readSensors() -> Result<RawSensors, SensorDriverError> {
        #if os(macOS)
        if let openFailure { return .failure(openFailure) }
        if connection == 0 {
            var opened: UInt32 = 0
            let status = coreo_smc_open(&opened)
            guard status == 0 else {
                // A missing or refused service does not appear later; stop retrying it.
                let failure = Self.failure(status, operation: "AppleSMC open")
                if failure == .notPresent || failure == .restricted(code: status) { openFailure = failure }
                return .failure(failure)
            }
            connection = opened
        }

        // "#KEY" doubles as a liveness check: a connection that cannot read it
        // reopens next sample instead of reporting a Mac without sensors.
        guard let keyCount = value("#KEY").flatMap({ UInt32(exactly: $0) }) else {
            coreo_smc_close(connection)
            connection = 0
            temperatureKeys = nil
            return .failure(.systemCall(operation: "AppleSMC read #KEY", code: EIO))
        }
        let keys = temperatureKeys ?? discoverTemperatureKeys(count: keyCount)
        let temperatures = keys.compactMap { key in value(key).map { RawSensorValue(key: key, value: $0) } }
        let power = Self.powerKeys.compactMap { key in value(key).map { RawSensorValue(key: key, value: $0) } }
        return .success(RawSensors(
            power: power, temperatures: temperatures, fans: fans(), discoveryTruncated: discoveryTruncated
        ))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    /// Temperature keys start with "T" and use a decodable temperature type.
    private func discoverTemperatureKeys(count: UInt32) -> [String] {
        var keys: [String] = []
        discoveryTruncated = count > Self.keyCapacity
        var name = [CChar](repeating: 0, count: 5)
        for index in 0..<min(count, Self.keyCapacity) {
            guard coreo_smc_key_at(connection, index, &name) == 0 else { continue }
            let key = String(decoding: name.prefix(4).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard key.hasPrefix("T"), let raw = rawValue(key),
                  Self.temperatureTypes.contains(raw.type) else { continue }
            keys.append(key)
        }
        temperatureKeys = keys
        return keys
    }

    private func fans() -> [RawFan] {
        guard let count = value("FNum").flatMap({ Int(exactly: $0) }), count > 0 else { return [] }
        return (0..<min(count, Self.maximumFans)).map { index in
            RawFan(index: index, rpm: value("F\(index)Ac"), maximumRPM: value("F\(index)Mx"))
        }
    }

    private func value(_ key: String) -> Double? {
        guard let raw = rawValue(key) else { return nil }
        return SMCValueDecoder.number(type: raw.type, bytes: raw.bytes)
    }

    private func rawValue(_ key: String) -> (type: String, bytes: [UInt8])? {
        var value = coreo_smc_value()
        guard coreo_smc_read(connection, key, &value) == 0 else { return nil }
        let type = withUnsafeBytes(of: value.type) { String(decoding: $0.prefix(4), as: UTF8.self) }
        let bytes = withUnsafeBytes(of: value.bytes) { Array($0.prefix(Int(min(value.size, 32)))) }
        return (type, bytes)
    }

    private static func failure(_ code: Int32, operation: String) -> SensorDriverError {
        switch code {
        case ENOENT: .notPresent
        case EPERM, EACCES: .restricted(code: code)
        case ENOTSUP: .unsupportedPlatform
        default: .systemCall(operation: operation, code: code)
        }
    }
    #endif
}
