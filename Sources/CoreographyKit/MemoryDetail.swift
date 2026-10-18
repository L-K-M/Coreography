import Foundation

/// Kernel memory pressure, ordered by severity.
///
/// Readings store the raw value as a measured ordinal so history, gaps and
/// accessibility reuse the numeric pipeline; never average or interpolate it.
public enum MemoryPressureLevel: Int, Codable, CaseIterable, Sendable {
    case normal = 0
    case warning = 1
    case critical = 2

    public init?(reading: MetricReading) {
        guard let value = reading.numericValue, let level = Int(exactly: value) else { return nil }
        self.init(rawValue: level)
    }
}

/// Memory composition, swap and paging for one host sample.
///
/// ```text
/// used = app + wired + compressed      (capacity: physical memory)
/// cached files are reclaimable and sit outside used
/// ```
/// Composition parts and cached files are gauges. Paging and swap rates are
/// counter deltas over the sample's real interval, so interruptions are gaps.
public struct MemoryDetail: Codable, Equatable, Sendable {
    public let appBytes: MetricReading
    public let wiredBytes: MetricReading
    public let compressedBytes: MetricReading
    public let cachedBytes: MetricReading
    /// Uncompressed pages held per physical compressor page.
    public let compressionRatio: MetricReading
    public let swapUsedBytes: MetricReading
    public let swapTotalBytes: MetricReading
    public let pageInBytesPerSecond: MetricReading
    public let swapInBytesPerSecond: MetricReading
    public let swapOutBytesPerSecond: MetricReading
    /// Measured `MemoryPressureLevel` ordinal.
    public let pressure: MetricReading

    public var pressureLevel: MemoryPressureLevel? { MemoryPressureLevel(reading: pressure) }
}
