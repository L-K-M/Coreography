import Foundation
import CoreographyDrivers

public actor ProcessMonitor {
    private static let nanosecondsPerSecond = 1_000_000_000.0
    private static let percentScale = 100.0
    // Counter/rate/percentage conversions can overshoot capacity by a few ULPs.
    private static let cpuCapacityRoundingTolerance = percentScale.ulp * 8
    private static let enumerationSource = MetricSource(
        provider: "processes", driver: "libproc", channel: "PROC_ALL_PIDS / PROC_PIDTBSDINFO"
    )
    private static let usageSource = MetricSource(
        provider: "processes", driver: "libproc", channel: "RUSAGE_INFO_V6"
    )
    private static let gpuSource = MetricSource(
        provider: "processes", driver: "IOKit", channel: "IOAccelerator user clients"
    )
    private static let nanojoulesPerJoule = 1_000_000_000.0
    private static let energyMethod = "The kernel's CPU energy model (ri_energy_nj)"
    private let driver: any ProcessSampleReading
    private let gpuClients: any GPUClientTimeReading
    private let maximumGap: Duration
    private var continuity: ContinuityTracker
    private var rates: [ProcessIdentity: ProcessRates] = [:]
    private var gpuLedger: GPUTimeLedger

    public init() throws { try self.init(driver: ProcessStatisticsDriver(), gpuClients: GPUClientDriver()) }

    init(
        driver: any ProcessSampleReading, gpuClients: any GPUClientTimeReading = GPUClientDriver(),
        maximumGap: Duration = .seconds(6)
    ) throws {
        // Validate once; each process then uses the same bounded rate contract.
        _ = try CounterRateTracker(maxGap: maximumGap)
        self.driver = driver
        self.gpuClients = gpuClients
        self.maximumGap = maximumGap
        self.continuity = ContinuityTracker(maximumGap: maximumGap)
        gpuLedger = GPUTimeLedger(maximumGap: maximumGap)
    }

    public func reset() {
        continuity.reset()
        rates.removeAll()
        gpuLedger.reset()
    }

    public func sample() async throws -> ProcessSnapshot {
        let raw = await driver.read()
        let gpuUsage = gpuLedger.record(await gpuClients.read())
        try Task.checkCancellation()
        let stamp = SampleStamp(
            clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds,
            wallTime: raw.wallTime
        )
        let interrupted = continuity.record(stamp) != .continuous
        if interrupted { rates.removeAll() }

        switch raw.enumeration {
        case .failure(let error):
            rates.removeAll()
            return ProcessSnapshot(
                stamp: stamp, collectorPID: raw.collectorPID,
                enumeration: try missing(error, source: Self.enumerationSource),
                enumerationTruncated: false, processes: [], issues: [],
                continuity: .interrupted
            )
        case .success(let enumeration):
            var processes: [ProcessReading] = []
            var issues = try enumeration.failures.map {
                ProcessCollectionIssue(
                    pid: $0.pid, reading: try missing($0.error, source: Self.enumerationSource)
                )
            }
            var nextRates: [ProcessIdentity: ProcessRates] = [:]
            var seen: Set<ProcessIdentity> = []
            for process in enumeration.processes {
                guard let identity = try? ProcessIdentity(
                    pid: process.pid, startSeconds: process.startSeconds,
                    startMicroseconds: process.startMicroseconds
                ), process.monotonicNanoseconds <= raw.monotonicNanoseconds,
                   seen.insert(identity).inserted else {
                    issues.append(ProcessCollectionIssue(
                        pid: process.pid, reading: try .unavailable(
                            reason: "Invalid or duplicate process observation", source: Self.enumerationSource
                        )
                    ))
                    continue
                }
                let age = Double(raw.monotonicNanoseconds - process.monotonicNanoseconds)
                    / Self.nanosecondsPerSecond
                let processStamp = SampleStamp(
                    clockID: raw.clockID, monotonicNanoseconds: process.monotonicNanoseconds,
                    wallTime: raw.wallTime.addingTimeInterval(-age)
                )
                var state = try rates[identity] ?? ProcessRates(maximumGap: maximumGap)
                let readings: UsageReadings
                switch process.counters {
                case .success(let counters):
                    readings = try state.record(
                        counters, at: processStamp,
                        logicalCPUCount: raw.logicalCPUCount, interrupted: interrupted
                    )
                    nextRates[identity] = state
                case .failure(let error):
                    readings = UsageReadings(missing: try missing(error, source: Self.usageSource))
                }
                // GPU time comes from the registry, readable even where usage is not.
                let gpu = interrupted
                    ? .gap(reason: "Sampling interrupted", source: Self.gpuSource)
                    : try gpuReading(gpuUsage, pid: process.pid)
                processes.append(ProcessReading(
                    id: identity, parentPID: process.parentPID, uid: process.uid,
                    name: process.name, stamp: processStamp,
                    cpuPercentOfMachine: readings.cpu, memoryFootprintBytes: readings.memory,
                    diskReadBytesPerSecond: readings.read, diskWriteBytesPerSecond: readings.write,
                    wakeupsPerSecond: readings.wakeups, gpuMillisecondsPerSecond: gpu, cpuPowerWatts: readings.power,
                    executablePath: process.executablePath, responsiblePID: process.responsiblePID
                ))
            }
            // Retain every observed process, but never reuse a missing process's baseline.
            rates = nextRates
            return ProcessSnapshot(
                stamp: stamp, collectorPID: raw.collectorPID,
                enumeration: try .measured(
                    Double(enumeration.processes.count + enumeration.failures.count),
                    source: Self.enumerationSource
                ),
                enumerationTruncated: enumeration.isTruncated, processes: processes,
                issues: issues, continuity: interrupted ? .interrupted : .continuous
            )
        }
    }

    private func missing(_ error: ProcessDriverError, source: MetricSource) throws -> MetricReading {
        switch error {
        case .unsupportedPlatform:
            .unsupported(reason: "libproc requires macOS", source: source)
        case .restricted(let code):
            try .restricted(reason: "Process access denied (\(code)); no helper access", source: source)
        case .disappeared:
            try .unavailable(reason: "Process exited during collection", source: source)
        case .identityChanged:
            .gap(reason: "PID identity changed during collection", source: source)
        case .systemCall(let operation, let code):
            try .unavailable(reason: "\(operation) failed (\(code))", source: source)
        }
    }

    private func gpuReading(_ usage: GPUTimeLedger.Usage, pid: Int32) throws -> MetricReading {
        switch usage {
        case .collecting: .collecting(source: Self.gpuSource)
        case .gap(let reason): .gap(reason: reason, source: Self.gpuSource)
        case .unavailable(let reason): try .unavailable(reason: reason, source: Self.gpuSource)
        case .unsupported(let reason): .unsupported(reason: reason, source: Self.gpuSource)
        case .millisecondsPerSecond(let times): try .measured(times[pid] ?? 0, source: Self.gpuSource)
        }
    }

    private struct UsageReadings {
        let cpu: MetricReading
        let memory: MetricReading
        let read: MetricReading
        let write: MetricReading
        let wakeups: MetricReading
        let power: MetricReading

        init(
            cpu: MetricReading, memory: MetricReading, read: MetricReading, write: MetricReading,
            wakeups: MetricReading, power: MetricReading
        ) {
            self.cpu = cpu
            self.memory = memory
            self.read = read
            self.write = write
            self.wakeups = wakeups
            self.power = power
        }

        init(missing: MetricReading) {
            self.init(cpu: missing, memory: missing, read: missing, write: missing, wakeups: missing, power: missing)
        }
    }

    private struct ProcessRates {
        var cpu: CounterRateTracker
        var read: CounterRateTracker
        var write: CounterRateTracker
        var wakeups: CounterRateTracker
        var energy: CounterRateTracker

        init(maximumGap: Duration) throws {
            cpu = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            read = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            write = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            wakeups = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            energy = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
        }

        mutating func record(
            _ counters: ProcessCounters, at stamp: SampleStamp,
            logicalCPUCount: Int, interrupted: Bool
        ) throws -> UsageReadings {
            let total = counters.userNanoseconds.addingReportingOverflow(counters.systemNanoseconds)
            let cpuReading: MetricReading
            if total.overflow || logicalCPUCount <= 0 {
                cpu.reset()
                cpuReading = .gap(reason: "Invalid process CPU counters or CPU count", source: usageSource)
            } else {
                let rate = cpu.record(total.partialValue, at: stamp)
                if let value = rate.numericValue {
                    let percent = value / nanosecondsPerSecond * percentScale / Double(logicalCPUCount)
                    cpuReading = percent <= percentScale + cpuCapacityRoundingTolerance
                        ? try .measured(min(percent, percentScale), source: usageSource)
                        : .gap(reason: "Process CPU delta exceeds machine capacity", source: usageSource)
                } else {
                    cpuReading = rate
                }
            }
            let readReading = read.record(counters.diskReadBytes, at: stamp)
            let writeReading = write.record(counters.diskWriteBytes, at: stamp)
            let wakeupReading = wakeups.record(counters.wakeups, at: stamp)
            let powerReading: MetricReading
            if counters.energyNanojoules == 0, total.partialValue > 0 {
                // A process that ran but used no energy has no counter on this Mac, not zero watts.
                energy.reset()
                powerReading = .unsupported(reason: "No energy counter for this process", source: usageSource)
            } else {
                let rate = energy.record(counters.energyNanojoules, at: stamp)
                powerReading = try rate.numericValue.map {
                    try .estimated($0 / nanojoulesPerJoule, method: energyMethod, source: usageSource)
                } ?? rate
            }
            let gap = MetricReading.gap(reason: "Sampling interrupted", source: usageSource)
            return UsageReadings(
                cpu: interrupted ? gap : cpuReading,
                memory: try .measured(Double(counters.physicalFootprintBytes), source: usageSource),
                read: interrupted ? gap : readReading, write: interrupted ? gap : writeReading,
                wakeups: interrupted ? gap : wakeupReading,
                power: interrupted ? gap : powerReading
            )
        }
    }
}
