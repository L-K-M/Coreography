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
    private static let swapSource = MetricSource(
        provider: "memory", driver: "sysctl", channel: "vm.swapusage"
    )
    private static let pressureSource = MetricSource(
        provider: "memory", driver: "sysctl", channel: "kern.memorystatus_vm_pressure_level"
    )
    private static let compositionMethod = "Mach VM page composition"
    private static let thermalSource = MetricSource(
        provider: "thermal", driver: "notify", channel: "com.apple.system.thermalpressurelevel"
    )
    private let driver: any HostSampleReading
    private let maximumGap: Duration
    private var user: CounterRateTracker
    private var system: CounterRateTracker
    private var idle: CounterRateTracker
    private var nice: CounterRateTracker
    private var pageIns: CounterRateTracker
    private var swapIns: CounterRateTracker
    private var swapOuts: CounterRateTracker
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
        self.pageIns = try CounterRateTracker(maxGap: maximumGap, source: Self.memorySource)
        self.swapIns = try CounterRateTracker(maxGap: maximumGap, source: Self.memorySource)
        self.swapOuts = try CounterRateTracker(maxGap: maximumGap, source: Self.memorySource)
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
            resetCPUCounters()
            cpu = try missingReading(error, source: Self.cpuSource)
        }

        let physicalBytes = raw.inventory.physicalMemoryBytes
        let memory = try pageReading(raw.memory, as: .estimated) {
            try MemoryFootprint.usedBytes(from: $0, physicalBytes: physicalBytes)
        }
        let detail = try memoryDetail(raw, at: stamp, interrupted: interrupted)
        let thermal: MetricReading
        switch raw.thermalPressure {
        case .success(let kernelLevel):
            let level: ThermalPressureLevel = switch kernelLevel {
            case .nominal: .nominal
            case .moderate: .moderate
            case .heavy: .heavy
            case .trapping: .trapping
            case .sleeping: .sleeping
            }
            thermal = try .measured(Double(level.rawValue), source: Self.thermalSource)
        case .failure(let error):
            thermal = try missingReading(error, source: Self.thermalSource)
        }

        let snapshot = SystemSnapshot(
            stamp: stamp, inventory: raw.inventory,
            cpuPercentOfMachine: cpu, memoryUsedBytes: memory, memory: detail,
            thermalPressure: thermal, continuity: interrupted ? .interrupted : .continuous
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

    private func memoryDetail(
        _ raw: RawHostSnapshot, at stamp: SampleStamp, interrupted: Bool
    ) throws -> MemoryDetail {
        let physicalBytes = raw.inventory.physicalMemoryBytes
        let pages = raw.memory

        let swapUsed: MetricReading
        let swapTotal: MetricReading
        switch raw.swap {
        case .success(let swap):
            swapUsed = try .measured(Double(swap.usedBytes), source: Self.swapSource)
            swapTotal = try .measured(Double(swap.totalBytes), source: Self.swapSource)
        case .failure(let error):
            swapUsed = try missingReading(error, source: Self.swapSource)
            swapTotal = swapUsed
        }

        let pressure: MetricReading
        switch raw.memoryPressure {
        case .success(let kernelLevel):
            let level: MemoryPressureLevel = switch kernelLevel {
            case .normal: .normal
            case .warning: .warning
            case .critical: .critical
            }
            pressure = try .measured(Double(level.rawValue), source: Self.pressureSource)
        case .failure(let error):
            pressure = try missingReading(error, source: Self.pressureSource)
        }

        return MemoryDetail(
            appBytes: try pageReading(pages, as: .estimated) {
                try MemoryFootprint.appBytes(from: $0, physicalBytes: physicalBytes)
            },
            wiredBytes: try pageReading(pages, as: .measured) {
                try MemoryFootprint.bytes($0.wired, pageSize: $0.pageSizeBytes)
            },
            compressedBytes: try pageReading(pages, as: .measured) {
                try MemoryFootprint.bytes($0.compressed, pageSize: $0.pageSizeBytes)
            },
            cachedBytes: try pageReading(pages, as: .estimated) {
                try MemoryFootprint.cachedBytes(from: $0, physicalBytes: physicalBytes)
            },
            compressionRatio: try compressionRatio(pages),
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal,
            pageInBytesPerSecond: try pagingRate(pages, \.pageIns, tracker: &pageIns, at: stamp, interrupted: interrupted),
            swapInBytesPerSecond: try pagingRate(pages, \.swapIns, tracker: &swapIns, at: stamp, interrupted: interrupted),
            swapOutBytesPerSecond: try pagingRate(pages, \.swapOuts, tracker: &swapOuts, at: stamp, interrupted: interrupted),
            pressure: pressure
        )
    }

    private enum PageReadingKind { case measured, estimated }

    /// Convert one page-derived byte gauge; inconsistent counters stay unavailable.
    private func pageReading(
        _ pages: Result<MemoryPages, HostDriverError>, as kind: PageReadingKind,
        _ derive: (MemoryPages) throws -> UInt64
    ) throws -> MetricReading {
        switch pages {
        case .failure(let error):
            return try missingReading(error, source: Self.memorySource)
        case .success(let pages):
            guard let bytes = try? derive(pages) else {
                return try .unavailable(reason: "Inconsistent VM page counters", source: Self.memorySource)
            }
            switch kind {
            case .measured: return try .measured(Double(bytes), source: Self.memorySource)
            case .estimated:
                return try .estimated(Double(bytes), method: Self.compositionMethod, source: Self.memorySource)
            }
        }
    }

    private func compressionRatio(_ pages: Result<MemoryPages, HostDriverError>) throws -> MetricReading {
        switch pages {
        case .failure(let error):
            return try missingReading(error, source: Self.memorySource)
        case .success(let pages):
            guard pages.compressed > 0 else {
                return try .unavailable(reason: "Compressor is empty", source: Self.memorySource)
            }
            return try .measured(
                Double(pages.compressorContents) / Double(pages.compressed), source: Self.memorySource
            )
        }
    }

    /// Lifetime page counter to bytes per second over the real interval.
    private func pagingRate(
        _ pages: Result<MemoryPages, HostDriverError>, _ counter: KeyPath<MemoryPages, UInt64>,
        tracker: inout CounterRateTracker, at stamp: SampleStamp, interrupted: Bool
    ) throws -> MetricReading {
        switch pages {
        case .failure(let error):
            tracker.reset()
            return try missingReading(error, source: Self.memorySource)
        case .success(let pages):
            let rate = tracker.record(pages[keyPath: counter], at: stamp)
            if interrupted { return .gap(reason: "Sampling interrupted", source: Self.memorySource) }
            guard let pagesPerSecond = rate.numericValue else { return rate }
            return try .measured(pagesPerSecond * Double(pages.pageSizeBytes), source: Self.memorySource)
        }
    }

    private func resetCounters() {
        resetCPUCounters()
        pageIns.reset()
        swapIns.reset()
        swapOuts.reset()
    }

    private func resetCPUCounters() {
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
        case .malformedReply(let operation):
            return try .unavailable(reason: "\(operation) returned a malformed reply", source: source)
        case .unexpectedValue(let operation, let value):
            return try .unavailable(reason: "\(operation) returned unexpected value \(value)", source: source)
        case .systemCall(let operation, let code):
            return try .unavailable(
                reason: "\(operation) failed (\(code))", source: source
            )
        }
    }
}
