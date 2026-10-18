import Foundation

/// One temperature with its SMC key, so a change of hottest sensor is
/// visible rather than faking a trend.
public struct TemperatureReading: Codable, Sendable {
    public let key: String
    /// Coarse region from community key naming, where known.
    public let region: String?
    public let celsius: MetricReading
}

public struct FanReading: Identifiable, Codable, Sendable {
    public let id: Int
    public let rpm: MetricReading
    public let maximumRPM: MetricReading
}

public struct SensorSnapshot: Identifiable, Codable, Sendable {
    public let id: UUID
    public let stamp: SampleStamp
    public let continuity: SamplingContinuity
    /// Availability of the SMC itself; unsupported on Macs or VMs without it.
    public let source: MetricReading
    public let systemPowerWatts: MetricReading
    public let hottest: TemperatureReading?
    public let plausibleTemperatureCount: Int
    public let implausibleTemperatureCount: Int
    public let fans: [FanReading]
    public let discoveryTruncated: Bool
}
