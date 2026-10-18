import Foundation
import CoreographyDrivers

public typealias PowerSource = PowerSourceState

/// Power and battery state for one sample. All values are gauges.
///
/// System draw is known only while running from the battery: the gas
/// gauge's discharge then supplies the whole Mac. On external power it is
/// unavailable until an SMC system-power source exists.
public struct PowerSnapshot: Identifiable, Codable, Sendable {
    public let id: UUID
    public let stamp: SampleStamp
    public let continuity: SamplingContinuity
    public let systemPowerWatts: MetricReading
    public let batteryChargePercent: MetricReading
    /// Positive while charging, negative while discharging.
    public let batteryPowerWatts: MetricReading
    public let batteryMinutesRemaining: MetricReading
    public let batteryHealthPercent: MetricReading
    public let batteryCycleCount: MetricReading
    public let adapterRatingWatts: MetricReading
    public let powerSource: PowerSource?
    public let isCharging: Bool?
}
