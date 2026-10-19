import Foundation
import CoreographyDrivers

public actor SensorMonitor {
    private static let source = MetricSource(provider: "sensors", driver: "AppleSMC")
    /// Readings outside this band are sensor faults, not temperatures
    /// (mactop drops sub-10 °C post-boot values the same way).
    private static let plausibleCelsius = 10.0...130.0
    // Community key naming for Apple Silicon; unlisted prefixes stay unnamed.
    private static let regions = ["Tp": "CPU performance cores", "Te": "CPU efficiency cores", "Tg": "GPU", "TB": "Battery"]
    private static let powerMethods = [
        "PSTR": "SMC PSTR system power rail; per-chip validation pending",
        "PDTR": "SMC PDTR DC-in power rail; per-chip validation pending"
    ]
    private let driver: any SensorSampleReading
    private var continuity: ContinuityTracker
    private var buffer: SampleBuffer<SensorSnapshot>
    /// Every plausible temperature of the newest sample. Kept apart from
    /// history: an hour of every key per second would cost tens of MB.
    private var latestTemperatures: [TemperatureReading] = []

    public init() throws { try self.init(driver: SensorDriver(), historyCapacity: LiveHistory.capacity) }

    init(driver: any SensorSampleReading, maximumGap: Duration = .seconds(3), historyCapacity: Int = 60) throws {
        _ = try CounterRateTracker(maxGap: maximumGap)
        self.driver = driver
        self.continuity = ContinuityTracker(maximumGap: maximumGap)
        self.buffer = try SampleBuffer(capacity: historyCapacity)
    }

    public func reset() {
        continuity.reset()
        buffer.removeAll()
        latestTemperatures = []
    }

    public func history() -> [SensorSnapshot] { buffer.elements }

    /// The newest sample's plausible temperatures, by key.
    public func temperatures() -> [TemperatureReading] { latestTemperatures }

    public func sample() async throws -> SensorSnapshot {
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(
            clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds, wallTime: raw.wallTime
        )
        let outcome = continuity.record(stamp)
        if outcome == .discontinuous { buffer.removeAll() }
        let interrupted = outcome != .continuous
        let continuity: SamplingContinuity = interrupted ? .interrupted : .continuous

        let snapshot: SensorSnapshot
        switch raw.sensors {
        case .failure(let error):
            let missing = try missing(error)
            latestTemperatures = []
            snapshot = SensorSnapshot(
                id: UUID(), stamp: stamp, continuity: continuity, source: missing, systemPowerWatts: missing,
                hottest: nil, plausibleTemperatureCount: 0, implausibleTemperatureCount: 0, fans: [],
                discoveryTruncated: false
            )
        case .success(let sensors):
            let plausible = sensors.temperatures.filter { Self.plausibleCelsius.contains($0.value) }
            latestTemperatures = try plausible.map(temperature).sorted { $0.key < $1.key }
            let hottest = try plausible.max { $0.value < $1.value }.map(temperature)
            snapshot = SensorSnapshot(
                id: UUID(), stamp: stamp, continuity: continuity,
                source: try .measured(Double(sensors.temperatures.count), source: Self.source),
                systemPowerWatts: try systemPower(sensors.power), hottest: hottest,
                plausibleTemperatureCount: plausible.count,
                implausibleTemperatureCount: sensors.temperatures.count - plausible.count,
                fans: try sensors.fans.map(fan), discoveryTruncated: sensors.discoveryTruncated
            )
        }
        buffer.append(snapshot)
        return snapshot
    }

    private func temperature(_ value: RawSensorValue) throws -> TemperatureReading {
        TemperatureReading(
            key: value.key, region: Self.regions[String(value.key.prefix(2))],
            celsius: try .measured(value.value, source: Self.source(value.key))
        )
    }

    /// The first published rail in preference order; a non-positive draw is a fault.
    private func systemPower(_ rails: [RawSensorValue]) throws -> MetricReading {
        for rail in rails {
            guard let method = Self.powerMethods[rail.key] else { continue }
            guard rail.value > 0 else { continue }
            return try .estimated(rail.value, method: method, source: Self.source(rail.key))
        }
        return try .unavailable(reason: "This Mac publishes no SMC system power rail", source: Self.source)
    }

    private func fan(_ raw: RawFan) throws -> FanReading {
        let source = Self.source("F\(raw.index)Ac")
        return FanReading(
            id: raw.index,
            rpm: try raw.rpm.map { try .measured($0, source: source) }
                ?? .unavailable(reason: "Fan speed is not published", source: source),
            maximumRPM: try raw.maximumRPM.map { try .measured($0, source: Self.source("F\(raw.index)Mx")) }
                ?? .unavailable(reason: "Fan maximum is not published", source: source)
        )
    }

    private static func source(_ key: String) -> MetricSource {
        MetricSource(provider: "sensors", driver: "AppleSMC", channel: key)
    }

    private func missing(_ error: SensorDriverError) throws -> MetricReading {
        switch error {
        case .unsupportedPlatform: .unsupported(reason: "Native sensor sampling requires macOS", source: Self.source)
        case .notPresent: .unsupported(reason: "AppleSMC is not present on this Mac", source: Self.source)
        case .restricted(let code): try .restricted(reason: "AppleSMC access denied (\(code))", source: Self.source)
        case .systemCall(let operation, let code):
            try .unavailable(reason: "\(operation) failed (\(code))", source: Self.source)
        }
    }
}
