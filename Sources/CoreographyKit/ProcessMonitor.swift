import Foundation
import CoreographyDrivers

public actor ProcessMonitor {
    private static let nanosecondsPerSecond = 1_000_000_000.0
    private static let percentScale = 100.0
    private static let enumerationSource = MetricSource(
        provider: "processes", driver: "libproc", channel: "PROC_ALL_PIDS / PROC_PIDTBSDINFO"
    )
    private static let usageSource = MetricSource(
        provider: "processes", driver: "libproc", channel: "RUSAGE_INFO_V2"
    )
    private let driver: any ProcessSampleReading
    private let maximumGap: Duration
    private var previousStamp: SampleStamp?
    private var rates: [ProcessIdentity: ProcessRates] = [:]

    public init() throws { try self.init(driver: ProcessStatisticsDriver()) }

    init(driver: any ProcessSampleReading, maximumGap: Duration = .seconds(6)) throws {
        // Validate once; each process then uses the same bounded rate contract.
        _ = try CounterRateTracker(maxGap: maximumGap)
        self.driver = driver
        self.maximumGap = maximumGap
    }

    public func reset() {
        previousStamp = nil
        rates.removeAll()
    }

    public func sample() async throws -> ProcessSnapshot {
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(
            clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds,
            wallTime: raw.wallTime
        )
        let interrupted = isInterrupted(stamp)
        if interrupted { rates.removeAll() }
        previousStamp = stamp

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
                processes.append(ProcessReading(
                    id: identity, parentPID: process.parentPID, uid: process.uid,
                    name: process.name, stamp: processStamp,
                    cpuPercentOfMachine: readings.cpu, memoryFootprintBytes: readings.memory,
                    diskReadBytesPerSecond: readings.read, diskWriteBytesPerSecond: readings.write
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

    private func isInterrupted(_ stamp: SampleStamp) -> Bool {
        guard let previous = previousStamp else { return false }
        guard stamp.clockID == previous.clockID,
              stamp.monotonicNanoseconds > previous.monotonicNanoseconds else { return true }
        let elapsed = Duration.nanoseconds(stamp.monotonicNanoseconds - previous.monotonicNanoseconds)
        let components = maximumGap.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        let wallElapsed = stamp.wallTime.timeIntervalSince(previous.wallTime)
        return elapsed > maximumGap || wallElapsed < 0 || wallElapsed > seconds
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

    private struct UsageReadings {
        let cpu: MetricReading
        let memory: MetricReading
        let read: MetricReading
        let write: MetricReading

        init(cpu: MetricReading, memory: MetricReading, read: MetricReading, write: MetricReading) {
            self.cpu = cpu
            self.memory = memory
            self.read = read
            self.write = write
        }

        init(missing: MetricReading) {
            self.init(cpu: missing, memory: missing, read: missing, write: missing)
        }
    }

    private struct ProcessRates {
        var cpu: CounterRateTracker
        var read: CounterRateTracker
        var write: CounterRateTracker

        init(maximumGap: Duration) throws {
            cpu = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            read = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
            write = try CounterRateTracker(maxGap: maximumGap, source: usageSource)
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
                    cpuReading = percent <= percentScale
                        ? try .measured(percent, source: usageSource)
                        : .gap(reason: "Process CPU delta exceeds machine capacity", source: usageSource)
                } else {
                    cpuReading = rate
                }
            }
            let readReading = read.record(counters.diskReadBytes, at: stamp)
            let writeReading = write.record(counters.diskWriteBytes, at: stamp)
            let gap = MetricReading.gap(reason: "Sampling interrupted", source: usageSource)
            return UsageReadings(
                cpu: interrupted ? gap : cpuReading,
                memory: try .measured(Double(counters.physicalFootprintBytes), source: usageSource),
                read: interrupted ? gap : readReading, write: interrupted ? gap : writeReading
            )
        }
    }
}
