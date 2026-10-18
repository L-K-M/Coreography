import Foundation
import Dispatch

#if os(macOS)
import Darwin
#endif

public struct HostInventory: Codable, Equatable, Sendable {
    public let operatingSystem: String
    public let architecture: String
    public let logicalCPUCount: Int
    public let physicalMemoryBytes: UInt64

    public init(
        operatingSystem: String, architecture: String,
        logicalCPUCount: Int, physicalMemoryBytes: UInt64
    ) {
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.logicalCPUCount = logicalCPUCount
        self.physicalMemoryBytes = physicalMemoryBytes
    }

    public static func current() -> Self {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif

        let process = ProcessInfo.processInfo
        return Self(
            operatingSystem: process.operatingSystemVersionString,
            architecture: architecture,
            logicalCPUCount: process.processorCount,
            physicalMemoryBytes: process.physicalMemory
        )
    }
}

public struct ProcessorTicks: Equatable, Sendable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public struct MemoryPages: Equatable, Sendable {
    public let active: UInt64
    public let inactive: UInt64
    public let speculative: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let purgeable: UInt64
    public let fileBacked: UInt64
    public let pageSizeBytes: UInt64

    public init(
        active: UInt64, inactive: UInt64, speculative: UInt64,
        wired: UInt64, compressed: UInt64, purgeable: UInt64,
        fileBacked: UInt64, pageSizeBytes: UInt64
    ) {
        self.active = active
        self.inactive = inactive
        self.speculative = speculative
        self.wired = wired
        self.compressed = compressed
        self.purgeable = purgeable
        self.fileBacked = fileBacked
        self.pageSizeBytes = pageSizeBytes
    }
}

public enum HostDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case systemCall(operation: String, code: Int32)
    case invalidPageSize
}

public struct RawHostSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let inventory: HostInventory
    public let cpu: Result<ProcessorTicks, HostDriverError>
    public let memory: Result<MemoryPages, HostDriverError>

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date,
        inventory: HostInventory,
        cpu: Result<ProcessorTicks, HostDriverError>,
        memory: Result<MemoryPages, HostDriverError>
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.inventory = inventory
        self.cpu = cpu
        self.memory = memory
    }
}

public protocol HostSampleReading: Sendable {
    func read() async -> RawHostSnapshot
}

/// Own the host port in one actor so collection cannot race its lifetime.
public actor HostStatisticsDriver: HostSampleReading {
    private let clockID = UUID()
    private let inventory = HostInventory.current()

    #if os(macOS)
    private let host = mach_host_self()

    deinit {
        mach_port_deallocate(mach_task_self_, host)
    }
    #endif

    public init() {}

    public func read() async -> RawHostSnapshot {
        #if os(macOS)
        let cpu = readCPU()
        let memory = readMemory()
        #else
        let cpu: Result<ProcessorTicks, HostDriverError> = .failure(.unsupportedPlatform)
        let memory: Result<MemoryPages, HostDriverError> = .failure(.unsupportedPlatform)
        #endif

        return RawHostSnapshot(
            clockID: clockID,
            monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            wallTime: Date(),
            inventory: inventory,
            cpu: cpu,
            memory: memory
        )
    }

    #if os(macOS)
    private func readCPU() -> Result<ProcessorTicks, HostDriverError> {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return .failure(.systemCall(operation: "host_statistics", code: result))
        }

        return withUnsafeBytes(of: info.cpu_ticks) { buffer in
            let ticks = buffer.bindMemory(to: UInt32.self)
            return .success(ProcessorTicks(
                user: UInt64(ticks[Int(CPU_STATE_USER)]),
                system: UInt64(ticks[Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(ticks[Int(CPU_STATE_IDLE)]),
                nice: UInt64(ticks[Int(CPU_STATE_NICE)])
            ))
        }
    }

    private func readMemory() -> Result<MemoryPages, HostDriverError> {
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        guard pageResult == KERN_SUCCESS else {
            return .failure(.systemCall(operation: "host_page_size", code: pageResult))
        }
        guard pageSize > 0 else { return .failure(.invalidPageSize) }

        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return .failure(.systemCall(operation: "host_statistics64", code: result))
        }

        return .success(MemoryPages(
            active: UInt64(info.active_count), inactive: UInt64(info.inactive_count),
            speculative: UInt64(info.speculative_count), wired: UInt64(info.wire_count),
            compressed: UInt64(info.compressor_page_count),
            purgeable: UInt64(info.purgeable_count), fileBacked: UInt64(info.external_page_count),
            pageSizeBytes: UInt64(pageSize)
        ))
    }
    #endif
}
