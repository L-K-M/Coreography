import Foundation
import Dispatch

#if os(macOS)
import Darwin
import CoreographySystem
#endif

public enum ProcessDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case restricted(code: Int32)
    case disappeared
    case identityChanged
    case systemCall(operation: String, code: Int32)
}

public struct ProcessCounters: Equatable, Sendable {
    public let userNanoseconds: UInt64
    public let systemNanoseconds: UInt64
    public let physicalFootprintBytes: UInt64
    public let diskReadBytes: UInt64
    public let diskWriteBytes: UInt64
    /// Cumulative package-idle and interrupt wakeups.
    public let wakeups: UInt64
    /// Cumulative energy from the kernel's model; zero where it keeps none.
    public let energyNanojoules: UInt64

    public init(
        userNanoseconds: UInt64, systemNanoseconds: UInt64,
        physicalFootprintBytes: UInt64, diskReadBytes: UInt64, diskWriteBytes: UInt64, wakeups: UInt64 = 0,
        energyNanojoules: UInt64 = 0
    ) {
        self.wakeups = wakeups
        self.energyNanojoules = energyNanojoules
        self.userNanoseconds = userNanoseconds
        self.systemNanoseconds = systemNanoseconds
        self.physicalFootprintBytes = physicalFootprintBytes
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
    }
}

/// The instruction set a process runs, as the OS reports it.
public enum ProcessCPUType: Equatable, Sendable {
    case arm64
    case x86_64
    /// x86_64 code translated by Rosetta on Apple silicon.
    case x86_64Translated
}

public struct RawProcessInfo: Sendable {
    public let pid: Int32
    public let parentPID: UInt32
    public let uid: UInt32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64
    public let name: String
    public let monotonicNanoseconds: UInt64
    public let counters: Result<ProcessCounters, ProcessDriverError>
    /// Absent when the path or the private responsibility lookup is unreadable.
    public let executablePath: String?
    public let responsiblePID: Int32?
    /// Threads the process has now; a gauge, read with the counters.
    public let threads: Result<Int, ProcessDriverError>
    public let cpuType: Result<ProcessCPUType, ProcessDriverError>

    public init(
        pid: Int32, parentPID: UInt32, uid: UInt32,
        startSeconds: UInt64, startMicroseconds: UInt64, name: String,
        monotonicNanoseconds: UInt64,
        counters: Result<ProcessCounters, ProcessDriverError>,
        executablePath: String? = nil, responsiblePID: Int32? = nil,
        threads: Result<Int, ProcessDriverError> = .failure(.unsupportedPlatform),
        cpuType: Result<ProcessCPUType, ProcessDriverError> = .failure(.unsupportedPlatform)
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.uid = uid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
        self.name = name
        self.monotonicNanoseconds = monotonicNanoseconds
        self.counters = counters
        self.executablePath = executablePath
        self.responsiblePID = responsiblePID
        self.threads = threads
        self.cpuType = cpuType
    }
}

public struct ProcessReadFailure: Sendable {
    public let pid: Int32
    public let error: ProcessDriverError

    public init(pid: Int32, error: ProcessDriverError) {
        self.pid = pid
        self.error = error
    }
}

public struct ProcessEnumeration: Sendable {
    public let processes: [RawProcessInfo]
    public let failures: [ProcessReadFailure]
    public let isTruncated: Bool

    public init(
        processes: [RawProcessInfo], failures: [ProcessReadFailure] = [],
        isTruncated: Bool = false
    ) {
        self.processes = processes
        self.failures = failures
        self.isTruncated = isTruncated
    }
}

public struct RawProcessSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let logicalCPUCount: Int
    public let collectorPID: Int32
    public let enumeration: Result<ProcessEnumeration, ProcessDriverError>

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date,
        logicalCPUCount: Int, collectorPID: Int32,
        enumeration: Result<ProcessEnumeration, ProcessDriverError>
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.logicalCPUCount = logicalCPUCount
        self.collectorPID = collectorPID
        self.enumeration = enumeration
    }
}

public protocol ProcessSampleReading: Sendable {
    func read() async -> RawProcessSnapshot
}

/// Enumerate a bounded process set without invoking ps or acquiring task ports.
public actor ProcessStatisticsDriver: ProcessSampleReading {
    private static let processCapacity = 16_384
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.process-sampling")
    private let clockID = UUID()
    private let logicalCPUCount = ProcessInfo.processInfo.processorCount
    private let collectorPID = ProcessInfo.processInfo.processIdentifier
    /// A process's CPU type never changes, so each identity is asked once;
    /// failures are not kept. Pruned to the processes of the latest read.
    private var cpuTypes: [CPUTypeKey: ProcessCPUType] = [:]
    private var hostIsARM64: Result<Bool, ProcessDriverError>?

    private struct CPUTypeKey: Hashable {
        let pid: Int32
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func read() async -> RawProcessSnapshot {
        let enumeration = readProcesses()
        return RawProcessSnapshot(
            clockID: clockID,
            monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            wallTime: Date(), logicalCPUCount: logicalCPUCount, collectorPID: collectorPID,
            enumeration: enumeration
        )
    }

    private func readProcesses() -> Result<ProcessEnumeration, ProcessDriverError> {
        #if os(macOS)
        var pids = [Int32](repeating: 0, count: Self.processCapacity)
        var count: Int32 = 0
        var truncated: Int32 = 0
        let error = coreo_process_list(&pids, Int32(Self.processCapacity), &count, &truncated)
        guard error == 0 else { return .failure(Self.failure(error, operation: "proc_listpids")) }
        guard count >= 0, Int(count) <= Self.processCapacity else {
            return .failure(.systemCall(operation: "invalid proc_listpids count", code: EOVERFLOW))
        }

        var processes: [RawProcessInfo] = []
        var failures: [ProcessReadFailure] = []
        for pid in Set(pids.prefix(Int(count))).sorted() where pid >= 0 {
            if Task.isCancelled { break }
            var sample = coreo_process_sample()
            let status = coreo_process_read(pid, &sample)
            let time = DispatchTime.now().uptimeNanoseconds
            guard status == 0 else {
                failures.append(ProcessReadFailure(
                    pid: pid, error: Self.failure(status, operation: "proc_pidinfo")
                ))
                continue
            }
            let name = withUnsafeBytes(of: sample.name) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let path = sample.path_error != 0 ? nil : withUnsafeBytes(of: sample.path) { bytes in
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let counters: Result<ProcessCounters, ProcessDriverError>
            if sample.usage_error == 0 {
                counters = .success(ProcessCounters(
                    userNanoseconds: sample.user_nanoseconds,
                    systemNanoseconds: sample.system_nanoseconds,
                    physicalFootprintBytes: sample.physical_footprint_bytes,
                    diskReadBytes: sample.disk_read_bytes, diskWriteBytes: sample.disk_write_bytes,
                    wakeups: sample.wakeups, energyNanojoules: sample.energy_nanojoules
                ))
            } else {
                counters = .failure(Self.failure(sample.usage_error, operation: "proc_pid_rusage"))
            }
            processes.append(RawProcessInfo(
                pid: pid, parentPID: sample.parent_pid, uid: sample.uid,
                startSeconds: sample.start_seconds, startMicroseconds: sample.start_microseconds,
                name: name.isEmpty ? "PID \(pid)" : name,
                monotonicNanoseconds: time, counters: counters,
                executablePath: path?.isEmpty == false ? path : nil,
                responsiblePID: sample.responsible_error == 0 ? sample.responsible_pid : nil,
                threads: sample.threads_error == 0
                    ? .success(Int(sample.threads))
                    : .failure(Self.failure(sample.threads_error, operation: "PROC_PIDTASKINFO")),
                cpuType: cpuType(CPUTypeKey(
                    pid: pid, startSeconds: sample.start_seconds, startMicroseconds: sample.start_microseconds
                ))
            ))
        }
        let current = Set(processes.map {
            CPUTypeKey(pid: $0.pid, startSeconds: $0.startSeconds, startMicroseconds: $0.startMicroseconds)
        })
        cpuTypes = cpuTypes.filter { current.contains($0.key) }
        return .success(ProcessEnumeration(
            processes: processes, failures: failures,
            isTruncated: truncated != 0 || Task.isCancelled
        ))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    private func cpuType(_ key: CPUTypeKey) -> Result<ProcessCPUType, ProcessDriverError> {
        if let known = cpuTypes[key] { return .success(known) }

        var translated: Int32 = 0
        let status = coreo_process_translated(key.pid, key.startSeconds, key.startMicroseconds, &translated)
        guard status == 0 else { return .failure(Self.failure(status, operation: "KERN_PROC_PID")) }

        let host = hostIsARM64 ?? Self.readHostIsARM64()
        if case .success = host { hostIsARM64 = host }
        let type: ProcessCPUType
        switch host {
        case .failure(let error): return .failure(error)
        case .success(true): type = translated != 0 ? .x86_64Translated : .arm64
        case .success(false): type = .x86_64
        }
        cpuTypes[key] = type
        return .success(type)
    }

    private static func readHostIsARM64() -> Result<Bool, ProcessDriverError> {
        var isARM64: Int32 = 0
        let status = coreo_host_is_arm64(&isARM64)
        return status == 0 ? .success(isARM64 != 0) : .failure(failure(status, operation: "hw.optional.arm64"))
    }

    private static func failure(_ code: Int32, operation: String) -> ProcessDriverError {
        switch code {
        case EPERM, EACCES: .restricted(code: code)
        case ESRCH, ENOENT: .disappeared
        case EAGAIN: .identityChanged
        case ENOTSUP: .unsupportedPlatform
        default: .systemCall(operation: operation, code: code)
        }
    }
    #endif
}
