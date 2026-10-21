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
    private static let taskSource = MetricSource(
        provider: "processes", driver: "libproc", channel: "PROC_PIDTASKINFO"
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
    /// Some process on this Mac has reported energy; until one does, zero is no counter at all.
    private var energyCounters = CounterPresence.absent
    /// Some process has retired instructions; until one does, a zero
    /// counter means the CPU or VM keeps none, not an idle process.
    private var instructionCounters = CounterPresence.absent

    public init() throws {
        try self.init(
            driver: HelperCounterFill(base: ProcessStatisticsDriver(), helper: PrivilegedHelper()),
            gpuClients: GPUClientDriver()
        )
    }

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
            if energyCounters == .absent, enumeration.processes.contains(where: {
                if case .success(let counters) = $0.counters { counters.energyNanojoules > 0 } else { false }
            }) {
                energyCounters = .present
            }
            if instructionCounters == .absent, enumeration.processes.contains(where: {
                if case .success(let counters) = $0.counters { counters.instructions > 0 } else { false }
            }) {
                instructionCounters = .present
            }
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
                        logicalCPUCount: raw.logicalCPUCount, interrupted: interrupted,
                        energyCounters: energyCounters, instructionCounters: instructionCounters
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
                    cpuTimeSeconds: try cpuTime(process.counters, unreadable: readings.cpu),
                    threadCount: try threadCount(process.threads),
                    instructionsPerSecond: readings.instructions, qosCPUPercent: readings.qos,
                    architecture: architecture(process.cpuType),
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

    /// Lifetime CPU time is a counter, not a rate, so the first sample has it.
    private func cpuTime(_ counters: Result<ProcessCounters, ProcessDriverError>, unreadable: MetricReading) throws -> MetricReading {
        guard case .success(let counters) = counters else { return unreadable }
        let (total, overflow) = counters.userNanoseconds.addingReportingOverflow(counters.systemNanoseconds)
        guard !overflow else { return .gap(reason: "CPU time out of range", source: Self.usageSource) }
        return try .measured(Double(total) / Self.nanosecondsPerSecond, source: Self.usageSource)
    }

    /// A gauge, like footprint: it needs no baseline and no gap over an interruption.
    private func threadCount(_ threads: Result<Int, ProcessDriverError>) throws -> MetricReading {
        switch threads {
        case .success(let count): try .measured(Double(count), source: Self.taskSource)
        case .failure(let error): try missing(error, source: Self.taskSource)
        }
    }

    private func architecture(_ cpuType: Result<ProcessCPUType, ProcessDriverError>) -> ProcessArchitecture? {
        switch cpuType {
        case .success(.arm64): .appleSilicon
        case .success(.x86_64): .intel
        case .success(.x86_64Translated): .intelTranslated
        case .failure: nil
        }
    }

    private struct UsageReadings {
        let cpu: MetricReading
        let memory: MetricReading
        let read: MetricReading
        let write: MetricReading
        let wakeups: MetricReading
        let power: MetricReading
        let instructions: MetricReading
        /// Nil when the counters carrying the split could not be read.
        let qos: [ProcessQoS: MetricReading]?

        init(
            cpu: MetricReading, memory: MetricReading, read: MetricReading, write: MetricReading,
            wakeups: MetricReading, power: MetricReading,
            instructions: MetricReading, qos: [ProcessQoS: MetricReading]?
        ) {
            self.cpu = cpu
            self.memory = memory
            self.read = read
            self.write = write
            self.wakeups = wakeups
            self.power = power
            self.instructions = instructions
            self.qos = qos
        }

        init(missing: MetricReading) {
            self.init(
                cpu: missing, memory: missing, read: missing, write: missing, wakeups: missing,
                power: missing, instructions: missing, qos: nil
            )
        }
    }

    private struct ProcessRates {
        var cpu: CounterRateTracker
        var read: CounterRateTracker
        var write: CounterRateTracker
        var wakeups: CounterRateTracker
        var energy: CounterRateTracker
        var instructions: CounterRateTracker
        var qos: [ProcessQoS: CounterRateTracker]

        init(maximumGap: Duration) throws {
            cpu = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            read = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            write = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            wakeups = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            energy = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            instructions = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            qos = Dictionary(uniqueKeysWithValues: try ProcessQoS.allCases.map {
                ($0, try CounterRateTracker(maxGap: maximumGap, source: usageSource))
            })
        }

        /// A per-second counter delta as a percent of the whole machine, the
        /// same scale cpuPercentOfMachine uses.
        private static func machinePercent(_ rate: MetricReading, logicalCPUCount: Int) throws -> MetricReading {
            guard let value = rate.numericValue else { return rate }
            let percent = value / nanosecondsPerSecond * percentScale / Double(logicalCPUCount)
            return percent <= percentScale + cpuCapacityRoundingTolerance
                ? try .measured(min(percent, percentScale), source: usageSource)
                : .gap(reason: "Process CPU delta exceeds machine capacity", source: usageSource)
        }

        mutating func record(
            _ counters: ProcessCounters, at stamp: SampleStamp,
            logicalCPUCount: Int, interrupted: Bool,
            energyCounters: CounterPresence, instructionCounters: CounterPresence
        ) throws -> UsageReadings {
            let total = counters.userNanoseconds.addingReportingOverflow(counters.systemNanoseconds)
            let cpuReading: MetricReading
            if total.overflow || logicalCPUCount <= 0 {
                cpu.reset()
                cpuReading = .gap(reason: "Invalid process CPU counters or CPU count", source: usageSource)
            } else {
                cpuReading = try Self.machinePercent(cpu.record(total.partialValue, at: stamp), logicalCPUCount: logicalCPUCount)
            }
            let readReading = read.record(counters.diskReadBytes, at: stamp)
            let writeReading = write.record(counters.diskWriteBytes, at: stamp)
            let wakeupReading = wakeups.record(counters.wakeups, at: stamp)
            let powerReading: MetricReading
            if counters.energyNanojoules == 0, total.partialValue > 0 || energyCounters == .absent {
                // A process that ran but used no energy has no counter, not zero watts; on a Mac
                // where no process reports energy, an idle one has none either.
                energy.reset()
                powerReading = .unsupported(reason: "No energy counter for this process", source: usageSource)
            } else {
                let rate = energy.record(counters.energyNanojoules, at: stamp)
                powerReading = try rate.numericValue.map {
                    try .estimated($0 / nanojoulesPerJoule, method: energyMethod, source: usageSource)
                } ?? rate
            }
            let instructionReading: MetricReading
            if counters.instructions == 0, instructionCounters == .absent {
                // Zero in both samples: the CPU or VM keeps no counter, so
                // no baseline exists for a later nonzero reading either.
                instructions.reset()
                instructionReading = .unsupported(reason: "This Mac reports no instruction counter", source: usageSource)
            } else {
                instructionReading = instructions.record(counters.instructions, at: stamp)
            }
            var qosSplit: [ProcessQoS: MetricReading] = [:]
            for driverClass in ProcessQoSClass.allCases {
                let qosClass = ProcessQoS(driverClass)
                guard let rate = qos[qosClass]?.record(counters.qosNanoseconds[driverClass] ?? 0, at: stamp) else {
                    continue
                }
                qosSplit[qosClass] = logicalCPUCount > 0
                    ? try Self.machinePercent(rate, logicalCPUCount: logicalCPUCount)
                    : .gap(reason: "Invalid process CPU counters or CPU count", source: usageSource)
            }
            let gap = MetricReading.gap(reason: "Sampling interrupted", source: usageSource)
            return UsageReadings(
                cpu: interrupted ? gap : cpuReading,
                memory: try .measured(Double(counters.physicalFootprintBytes), source: usageSource),
                read: interrupted ? gap : readReading, write: interrupted ? gap : writeReading,
                wakeups: interrupted ? gap : wakeupReading,
                power: interrupted ? gap : powerReading,
                instructions: interrupted ? gap : instructionReading,
                qos: qosSplit.mapValues { interrupted ? gap : $0 }
            )
        }
    }
}

/// Whether this Mac's kernel keeps a counter of this kind at all.
enum CounterPresence: Sendable {
    case present, absent
}
