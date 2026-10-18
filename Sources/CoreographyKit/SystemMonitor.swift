import Foundation
import CoreographyDrivers

public actor SystemMonitor {
    private static let percentScale = 100.0
    private static let attosecondsPerSecond = 1_000_000_000_000_000_000.0
    private static let cpuSource = MetricSource(
        provider: "cpu", driver: "Mach", channel: "HOST_CPU_LOAD_INFO"
    )
    private static let memorySource = MetricSource(
        provider: "memory", driver: "Mach", channel: "HOST_VM_INFO64"
    )
    private let driver: any HostSampleReading
    private let maximumGap: Duration
    private var user: CounterRateTracker
    private var system: CounterRateTracker
    private var idle: CounterRateTracker
    private var nice: CounterRateTracker
    private var buffer: SampleBuffer<SystemSnapshot>
    private var previousStamp: SampleStamp?

    public init() throws {
        try self.init(
            driver: HostStatisticsDriver(), historyCapacity: 60,
            maximumGap: .seconds(3)
        )
    }

    init(
        driver: any HostSampleReading, historyCapacity: Int = 60,
        maximumGap: Duration = .seconds(3)
    ) throws {
        self.driver = driver
        self.maximumGap = maximumGap
        self.user = try CounterRateTracker(maxGap: maximumGap, source: Self.cpuSource)
        self.system = try CounterRateTracker(maxGap: maximumGap, source: Self.cpuSource)
        self.idle = try CounterRateTracker(maxGap: maximumGap, source: Self.cpuSource)
        self.nice = try CounterRateTracker(maxGap: maximumGap, source: Self.cpuSource)
        self.buffer = try SampleBuffer(capacity: historyCapacity)
    }

    public func sample() async throws -> SystemSnapshot {
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(
            clockID: raw.clockID,
            monotonicNanoseconds: raw.monotonicNanoseconds,
            wallTime: raw.wallTime
        )

        // Uptime clocks can exclude sleep; wall-clock gaps must not become idle CPU.
        var interrupted = false
        if let previous = previousStamp {
            let wallElapsed = stamp.wallTime.timeIntervalSince(previous.wallTime)
            let components = maximumGap.components
            let gapSeconds = Double(components.seconds)
                + Double(components.attoseconds) / Self.attosecondsPerSecond
            let monotonicBreak = stamp.monotonicNanoseconds <= previous.monotonicNanoseconds
                || Duration.nanoseconds(
                    stamp.monotonicNanoseconds - previous.monotonicNanoseconds
                ) > maximumGap
            interrupted = wallElapsed < 0 || wallElapsed > gapSeconds
                || stamp.clockID != previous.clockID || monotonicBreak
            if wallElapsed < 0 || stamp.clockID != previous.clockID {
                buffer.removeAll()
            }
            if interrupted { resetCounters() }
        }
        previousStamp = stamp

        let cpu: MetricReading
        switch raw.cpu {
        case .success(let ticks):
            let reading = try cpuReading(ticks, at: stamp)
            cpu = interrupted
                ? .gap(reason: "Sampling interrupted", source: Self.cpuSource)
                : reading
        case .failure(let error):
            resetCounters()
            cpu = try missingReading(error, source: Self.cpuSource)
        }

        let memory: MetricReading
        switch raw.memory {
        case .success(let pages):
            do {
                let bytes = try MemoryFootprint.usedBytes(
                    from: pages, physicalBytes: raw.inventory.physicalMemoryBytes
                )
                memory = try .estimated(
                    Double(bytes), method: "Mach VM page composition",
                    source: Self.memorySource
                )
            } catch {
                memory = try .unavailable(
                    reason: "Inconsistent VM page counters", source: Self.memorySource
                )
            }
        case .failure(let error):
            memory = try missingReading(error, source: Self.memorySource)
        }

        let snapshot = SystemSnapshot(
            stamp: stamp, inventory: raw.inventory,
            cpuPercentOfMachine: cpu, memoryUsedBytes: memory,
            continuity: interrupted ? .interrupted : .continuous
        )
        buffer.append(snapshot)
        return snapshot
    }

    public func history() -> [SystemSnapshot] { buffer.elements }

    public func reset() {
        previousStamp = nil
        resetCounters()
        buffer.removeAll()
    }

    private func cpuReading(_ ticks: ProcessorTicks, at stamp: SampleStamp) throws -> MetricReading {
        let rates = [
            user.record(ticks.user, at: stamp),
            system.record(ticks.system, at: stamp),
            idle.record(ticks.idle, at: stamp),
            nice.record(ticks.nice, at: stamp)
        ]
        if let missing = rates.first(where: { $0.numericValue == nil }) { return missing }

        let values = rates.compactMap(\.numericValue)
        let total = values.reduce(0, +)
        guard total > 0, total.isFinite else {
            return .gap(reason: "No elapsed CPU ticks", source: Self.cpuSource)
        }
        let busy = values[0] + values[1] + values[3]
        return try .measured(busy / total * Self.percentScale, source: Self.cpuSource)
    }

    private func resetCounters() {
        user.reset()
        system.reset()
        idle.reset()
        nice.reset()
    }

    private func missingReading(
        _ error: HostDriverError, source: MetricSource
    ) throws -> MetricReading {
        switch error {
        case .unsupportedPlatform:
            return .unsupported(reason: "Mach host statistics require macOS", source: source)
        case .invalidPageSize:
            return try .unavailable(reason: "Invalid host page size", source: source)
        case .systemCall(let operation, let code):
            return try .unavailable(
                reason: "\(operation) failed (\(code))", source: source
            )
        }
    }
}
