import Foundation
import CoreographyDrivers

public actor PowerMonitor {
    private static let batterySource = MetricSource(provider: "power", driver: "IOKit.ps", channel: "InternalBattery")
    private static let gaugeSource = MetricSource(provider: "power", driver: "IOKit", channel: "AppleSmartBattery")
    private static let adapterSource = MetricSource(
        provider: "power", driver: "IOKit.ps", channel: "IOPSCopyExternalPowerAdapterDetails"
    )
    private static let microwattsPerWatt = 1_000_000.0
    private static let percentScale = 100.0
    private let driver: any PowerSampleReading
    private var continuity: ContinuityTracker
    private var buffer: SampleBuffer<PowerSnapshot>

    public init() throws { try self.init(driver: PowerSourceDriver(), historyCapacity: LiveHistory.capacity) }

    init(driver: any PowerSampleReading, maximumGap: Duration = .seconds(3), historyCapacity: Int = 60) throws {
        _ = try CounterRateTracker(maxGap: maximumGap)
        self.driver = driver
        self.continuity = ContinuityTracker(maximumGap: maximumGap)
        self.buffer = try SampleBuffer(capacity: historyCapacity)
    }

    public func reset() {
        continuity.reset()
        buffer.removeAll()
    }

    public func history() -> [PowerSnapshot] { buffer.elements }

    public func sample() async throws -> PowerSnapshot {
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(
            clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds, wallTime: raw.wallTime
        )
        let outcome = continuity.record(stamp)
        if outcome == .discontinuous { buffer.removeAll() }
        let interrupted = outcome != .continuous

        let battery = try? raw.battery.get()
        let charge: MetricReading
        let remaining: MetricReading
        switch raw.battery {
        case .failure(let error):
            charge = try missing(error, source: Self.batterySource)
            remaining = charge
        case .success(let state):
            charge = try .measured(state.chargePercent, source: Self.batterySource)
            remaining = try minutesRemaining(state)
        }

        let batteryPower: MetricReading
        let health: MetricReading
        let cycles: MetricReading
        var dischargeWatts: Double?
        switch raw.gauge {
        case .failure(let error):
            batteryPower = try missing(error, source: Self.gaugeSource)
            health = batteryPower
            cycles = batteryPower
        case .success(let gauge):
            // mV × mA = µW.
            let watts = Double(gauge.voltageMillivolts) * Double(gauge.amperageMilliamps) / Self.microwattsPerWatt
            batteryPower = try .estimated(watts, method: "Gas-gauge voltage × current", source: Self.gaugeSource)
            if watts < 0 { dischargeWatts = -watts }
            health = try batteryHealth(gauge)
            cycles = try gauge.cycleCount.map { try .measured(Double($0), source: Self.gaugeSource) }
                ?? .unavailable(reason: "Cycle count is not published", source: Self.gaugeSource)
        }

        let system: MetricReading
        switch (battery?.powerSource, dischargeWatts) {
        case (.battery, let watts?):
            system = try .estimated(watts, method: "Battery discharge while unplugged", source: Self.gaugeSource)
        case (.battery, nil):
            system = try .unavailable(
                reason: "On battery, but the gas gauge reports no discharge current", source: Self.gaugeSource
            )
        case (.externalPower, _):
            system = try .unavailable(
                reason: "On external power, system draw needs the SMC power provider", source: Self.gaugeSource
            )
        case (nil, _):
            system = try .unavailable(
                reason: "System power needs the SMC power provider without a known battery source",
                source: Self.gaugeSource
            )
        }

        let adapter: MetricReading
        switch raw.adapterWatts {
        case .success(let watts): adapter = try .measured(watts, source: Self.adapterSource)
        case .failure(let error): adapter = try missing(error, source: Self.adapterSource)
        }

        let snapshot = PowerSnapshot(
            id: UUID(), stamp: stamp, continuity: interrupted ? .interrupted : .continuous,
            systemPowerWatts: system, batteryChargePercent: charge, batteryPowerWatts: batteryPower,
            batteryMinutesRemaining: remaining, batteryHealthPercent: health, batteryCycleCount: cycles,
            adapterRatingWatts: adapter, powerSource: battery?.powerSource, isCharging: battery?.isCharging
        )
        buffer.append(snapshot)
        return snapshot
    }

    private func minutesRemaining(_ state: BatteryState) throws -> MetricReading {
        let minutes = state.isCharging == true ? state.minutesToFull : state.minutesToEmpty
        guard let minutes else {
            return try .unavailable(reason: "macOS has no time estimate yet", source: Self.batterySource)
        }
        return try .estimated(Double(minutes), method: "macOS time estimate", source: Self.batterySource)
    }

    private func batteryHealth(_ gauge: BatteryGauge) throws -> MetricReading {
        guard let full = gauge.fullChargeCapacityMilliampHours, let design = gauge.designCapacityMilliampHours else {
            return try .unavailable(reason: "Battery capacities are not published", source: Self.gaugeSource)
        }
        return try .estimated(
            Double(full) / Double(design) * Self.percentScale,
            method: "Full-charge capacity / design capacity", source: Self.gaugeSource
        )
    }

    private func missing(_ error: PowerDriverError, source: MetricSource) throws -> MetricReading {
        switch error {
        case .unsupportedPlatform: .unsupported(reason: "Native power sampling requires macOS", source: source)
        case .noBattery: .unsupported(reason: "This Mac has no internal battery", source: source)
        case .unavailable(let reason): try .unavailable(reason: reason, source: source)
        }
    }
}
