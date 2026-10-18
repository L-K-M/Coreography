import Foundation
import CoreFoundation

public enum GPUDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case unavailable(reason: String)
    case systemCall(operation: String, code: Int32)
}

/// One `PerformanceStatistics` read. Utilization is the driver's own
/// percentage over its internal window; memory is unified system memory.
public struct GPUStatistics: Equatable, Sendable {
    public let utilizationPercent: Double
    public let rendererPercent: Double?
    public let tilerPercent: Double?
    public let inUseMemoryBytes: UInt64?

    public init(
        utilizationPercent: Double, rendererPercent: Double?,
        tilerPercent: Double?, inUseMemoryBytes: UInt64?
    ) {
        self.utilizationPercent = utilizationPercent
        self.rendererPercent = rendererPercent
        self.tilerPercent = tilerPercent
        self.inUseMemoryBytes = inUseMemoryBytes
    }
}

public struct RawGPUDevice: Sendable {
    public let registryEntryID: UInt64
    public let name: String
    public let statistics: Result<GPUStatistics, GPUDriverError>

    public init(registryEntryID: UInt64, name: String, statistics: Result<GPUStatistics, GPUDriverError>) {
        self.registryEntryID = registryEntryID
        self.name = name
        self.statistics = statistics
    }
}

public struct GPUEnumeration: Sendable {
    public let devices: [RawGPUDevice]
    public let failures: [GPUDriverError]
    public let isTruncated: Bool

    public init(devices: [RawGPUDevice], failures: [GPUDriverError] = [], isTruncated: Bool = false) {
        self.devices = devices
        self.failures = failures
        self.isTruncated = isTruncated
    }
}

public struct RawGPUSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let enumeration: Result<GPUEnumeration, GPUDriverError>

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date,
        enumeration: Result<GPUEnumeration, GPUDriverError>
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.enumeration = enumeration
    }
}

public protocol GPUSampleReading: Sendable {
    func read() async -> RawGPUSnapshot
}

/// Decode an IOAccelerator `PerformanceStatistics` table.
///
/// Keys are driver-defined, not SDK constants: Apple's AGX publishes
/// "Device Utilization %"; AMD and Intel drivers may publish "GPU Activity(%)".
enum GPUStatisticsDecoder {
    private static let utilizationKeys = ["Device Utilization %", "GPU Activity(%)"]
    private static let rendererKey = "Renderer Utilization %"
    private static let tilerKey = "Tiler Utilization %"
    private static let inUseMemoryKey = "In use system memory"
    private static let percentRange = 0.0...100.0

    static func statistics(_ table: [String: Any]) -> Result<GPUStatistics, GPUDriverError> {
        guard let key = utilizationKeys.first(where: { table[$0] != nil }) else {
            return .failure(.unavailable(reason: "GPU utilization is not published"))
        }
        guard let utilization = percent(table[key]) else {
            return .failure(.unavailable(reason: "Invalid \(key) value"))
        }
        return .success(GPUStatistics(
            utilizationPercent: utilization,
            rendererPercent: percent(table[rendererKey]),
            tilerPercent: percent(table[tilerKey]),
            inUseMemoryBytes: unsigned(table[inUseMemoryKey])
        ))
    }

    /// Accept finite CFNumbers in 0...100; booleans and strings are rejected.
    private static func percent(_ value: Any?) -> Double? {
        guard let number = cfNumber(value) else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite, percentRange.contains(percent) else { return nil }
        return percent
    }

    private static func unsigned(_ value: Any?) -> UInt64? {
        guard let number = cfNumber(value) else { return nil }
        let native = unsafeBitCast(number, to: CFNumber.self)
        guard !CFNumberIsFloatType(native) else { return nil }
        return number as? UInt64
    }

    private static func cfNumber(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
        return number
    }
}
