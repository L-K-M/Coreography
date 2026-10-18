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
    private let maximumGap: Duration
    private var previousStamp: SampleStamp?
    private var buffer: SampleBuffer<SensorSnapshot>

    public init() throws { try self.init(driver: SensorDriver()) }

    init(driver: any SensorSampleReading, maximumGap: Duration = .seconds(3), historyCapacity: Int = 60) throws {
        _ = try CounterRateTracker(maxGap: maximumGap)
        self.driver = driver
        self.maximumGap = maximumGap
        self.buffer = try SampleBuffer(capacity: historyCapacity)
    }

    public func reset() {
        previousStamp = nil
        buffer.removeAll()
    }

    public func history() -> [SensorSnapshot] { buffer.elements }

    public func sample() async throws -> SensorSnapshot {
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(
            clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds, wallTime: raw.wallTime
        )
        let interrupted = updateContinuity(stamp)
        let continuity: SamplingContinuity = interrupted ? .interrupted : .continuous

        let snapshot: SensorSnapshot
        switch raw.sensors {
        case .failure(let error):
            let missing = try missing(error)
            snapshot = SensorSnapshot(
                id: UUID(), stamp: stamp, continuity: continuity, source: missing, systemPowerWatts: missing,
                hottest: nil, plausibleTemperatureCount: 0, implausibleTemperatureCount: 0, fans: [],
                discoveryTruncated: false
            )
        case .success(let sensors):
            let plausible = sensors.temperatures.filter { Self.plausibleCelsius.contains($0.value) }
            let hottest = try plausible.max { $0.value < $1.value }.map { value in
                TemperatureReading(
                    key: value.key, region: Self.regions[String(value.key.prefix(2))],
                    celsius: try .measured(value.value, source: Self.source(value.key))
                )
            }
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

    private func updateContinuity(_ stamp: SampleStamp) -> Bool {
        defer { previousStamp = stamp }
        guard let previous = previousStamp else { return false }
        let wallElapsed = stamp.wallTime.timeIntervalSince(previous.wallTime)
        if wallElapsed < 0 || stamp.clockID != previous.clockID { buffer.removeAll() }
        guard stamp.clockID == previous.clockID,
              stamp.monotonicNanoseconds > previous.monotonicNanoseconds else { return true }
        let components = maximumGap.components
        let gapSeconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return wallElapsed < 0 || wallElapsed > gapSeconds
            || Duration.nanoseconds(stamp.monotonicNanoseconds - previous.monotonicNanoseconds) > maximumGap
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
