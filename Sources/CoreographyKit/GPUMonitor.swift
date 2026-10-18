import Foundation
import CoreographyDrivers

/// GPU gauges need no baseline, so each sample stands alone; continuity
/// only marks where history must not draw a line across missed time.
public actor GPUMonitor {
    private static let source = MetricSource(
        provider: "gpu", driver: "IOKit", channel: "IOAccelerator / PerformanceStatistics"
    )
    private let driver: any GPUSampleReading
    private var continuity: ContinuityTracker
    private var buffer: SampleBuffer<GPUSnapshot>

    public init() throws { try self.init(driver: GPUStatisticsDriver(), historyCapacity: LiveHistory.capacity) }

    init(driver: any GPUSampleReading, maximumGap: Duration = .seconds(3), historyCapacity: Int = 60) throws {
        _ = try CounterRateTracker(maxGap: maximumGap)
        self.driver = driver
        self.continuity = ContinuityTracker(maximumGap: maximumGap)
        self.buffer = try SampleBuffer(capacity: historyCapacity)
    }

    public func reset() {
        continuity.reset()
        buffer.removeAll()
    }

    public func history() -> [GPUSnapshot] { buffer.elements }

    public func sample() async throws -> GPUSnapshot {
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(
            clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds, wallTime: raw.wallTime
        )
        let outcome = continuity.record(stamp)
        if outcome == .discontinuous { buffer.removeAll() }
        let interrupted = outcome != .continuous

        var devices: [GPUDeviceReading] = []
        var issues: [GPUCollectionIssue] = []
        let enumerationReading: MetricReading
        let truncated: Bool
        switch raw.enumeration {
        case .failure(let error):
            enumerationReading = try missing(error)
            truncated = false
        case .success(let enumeration):
            truncated = enumeration.isTruncated
            enumerationReading = try .measured(
                Double(enumeration.devices.count + enumeration.failures.count), source: Self.source
            )
            issues = try enumeration.failures.map { GPUCollectionIssue(reading: try missing($0)) }
            var seen: Set<GPUDeviceID> = []
            for device in enumeration.devices {
                guard let identity = try? GPUDeviceID(registryEntryID: device.registryEntryID),
                      seen.insert(identity).inserted else {
                    issues.append(GPUCollectionIssue(reading: try .unavailable(
                        reason: "Invalid or duplicate GPU observation", source: Self.source
                    )))
                    continue
                }
                devices.append(try reading(device, identity: identity))
            }
        }

        let snapshot = GPUSnapshot(
            id: UUID(), stamp: stamp, enumeration: enumerationReading, enumerationTruncated: truncated,
            devices: devices, issues: issues, continuity: interrupted ? .interrupted : .continuous
        )
        buffer.append(snapshot)
        return snapshot
    }

    private func reading(_ device: RawGPUDevice, identity: GPUDeviceID) throws -> GPUDeviceReading {
        switch device.statistics {
        case .failure(let error):
            let missingReading = try missing(error)
            return GPUDeviceReading(
                id: identity, name: device.name, utilizationPercent: missingReading,
                rendererPercent: missingReading, tilerPercent: missingReading, inUseMemoryBytes: missingReading
            )
        case .success(let statistics):
            func optional(_ value: Double?, _ name: String) throws -> MetricReading {
                guard let value else {
                    return try .unavailable(reason: "\(name) is not published", source: Self.source)
                }
                return try .measured(value, source: Self.source)
            }
            return GPUDeviceReading(
                id: identity, name: device.name,
                utilizationPercent: try .measured(statistics.utilizationPercent, source: Self.source),
                rendererPercent: try optional(statistics.rendererPercent, "Renderer utilization"),
                tilerPercent: try optional(statistics.tilerPercent, "Tiler utilization"),
                inUseMemoryBytes: try optional(statistics.inUseMemoryBytes.map { Double($0) }, "GPU memory in use")
            )
        }
    }

    private func missing(_ error: GPUDriverError) throws -> MetricReading {
        switch error {
        case .unsupportedPlatform: .unsupported(reason: "Native GPU sampling requires macOS", source: Self.source)
        case .unavailable(let reason): try .unavailable(reason: reason, source: Self.source)
        case .systemCall(let operation, let code):
            try .unavailable(reason: "\(operation) failed (\(code))", source: Self.source)
        }
    }
}
