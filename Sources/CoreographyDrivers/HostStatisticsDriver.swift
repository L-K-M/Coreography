import Foundation
import Dispatch

#if os(macOS)
import Darwin
import CoreographySystem
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

/// One `HOST_VM_INFO64` read: current page counts plus lifetime counters.
public struct MemoryPages: Equatable, Sendable {
    public let active: UInt64
    public let inactive: UInt64
    public let speculative: UInt64
    public let wired: UInt64
    /// Physical pages holding compressed data.
    public let compressed: UInt64
    /// Uncompressed pages the compressor's data represents.
    public let compressorContents: UInt64
    public let purgeable: UInt64
    public let fileBacked: UInt64
    /// Lifetime counters; swaps count compressor-segment I/O in pages.
    public let pageIns: UInt64
    public let swapIns: UInt64
    public let swapOuts: UInt64
    public let pageSizeBytes: UInt64

    public init(
        active: UInt64, inactive: UInt64, speculative: UInt64,
        wired: UInt64, compressed: UInt64, compressorContents: UInt64,
        purgeable: UInt64, fileBacked: UInt64,
        pageIns: UInt64, swapIns: UInt64, swapOuts: UInt64,
        pageSizeBytes: UInt64
    ) {
        self.active = active
        self.inactive = inactive
        self.speculative = speculative
        self.wired = wired
        self.compressed = compressed
        self.compressorContents = compressorContents
        self.purgeable = purgeable
        self.fileBacked = fileBacked
        self.pageIns = pageIns
        self.swapIns = swapIns
        self.swapOuts = swapOuts
        self.pageSizeBytes = pageSizeBytes
    }
}

/// `vm.swapusage`: the dynamic swap files' current size and use.
public struct SwapUsage: Equatable, Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64

    public init(totalBytes: UInt64, usedBytes: UInt64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
    }
}

/// Kernel memory-pressure state reported by `kern.memorystatus_vm_pressure_level`.
public enum KernelMemoryPressure: String, Equatable, Sendable {
    case normal
    case warning
    case critical

    // The sysctl reports the public DISPATCH_MEMORYPRESSURE_* bit values.
    private static let normalLevel: UInt32 = 0x1
    private static let warningLevel: UInt32 = 0x2
    private static let criticalLevel: UInt32 = 0x4

    /// Decode one sysctl value; unknown values are not guessed.
    public init?(dispatchLevel: UInt32) {
        switch dispatchLevel {
        case Self.normalLevel: self = .normal
        case Self.warningLevel: self = .warning
        case Self.criticalLevel: self = .critical
        default: return nil
        }
    }
}

/// `OSThermalPressureLevel` on macOS; the C bridge checks these against the SDK.
public enum KernelThermalPressure: UInt64, Equatable, Sendable {
    case nominal = 0
    case moderate = 1
    case heavy = 2
    case trapping = 3
    case sleeping = 4
}

public enum HostDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case systemCall(operation: String, code: Int32)
    case invalidPageSize
    case malformedReply(operation: String)
    case unexpectedValue(operation: String, value: UInt64)
}

public struct RawHostSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let inventory: HostInventory
    public let cpu: Result<ProcessorTicks, HostDriverError>
    public let memory: Result<MemoryPages, HostDriverError>
    public let swap: Result<SwapUsage, HostDriverError>
    public let memoryPressure: Result<KernelMemoryPressure, HostDriverError>
    public let thermalPressure: Result<KernelThermalPressure, HostDriverError>

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date,
        inventory: HostInventory,
        cpu: Result<ProcessorTicks, HostDriverError>,
        memory: Result<MemoryPages, HostDriverError>,
        swap: Result<SwapUsage, HostDriverError>,
        memoryPressure: Result<KernelMemoryPressure, HostDriverError>,
        thermalPressure: Result<KernelThermalPressure, HostDriverError>
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.inventory = inventory
        self.cpu = cpu
        self.memory = memory
        self.swap = swap
        self.memoryPressure = memoryPressure
        self.thermalPressure = thermalPressure
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
        let swap = readSwap()
        let pressure = readPressure()
        let thermal = readThermalPressure()
        #else
        let cpu: Result<ProcessorTicks, HostDriverError> = .failure(.unsupportedPlatform)
        let memory: Result<MemoryPages, HostDriverError> = .failure(.unsupportedPlatform)
        let swap: Result<SwapUsage, HostDriverError> = .failure(.unsupportedPlatform)
        let pressure: Result<KernelMemoryPressure, HostDriverError> = .failure(.unsupportedPlatform)
        let thermal: Result<KernelThermalPressure, HostDriverError> = .failure(.unsupportedPlatform)
        #endif

        return RawHostSnapshot(
            clockID: clockID,
            monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            wallTime: Date(),
            inventory: inventory,
            cpu: cpu,
            memory: memory,
            swap: swap,
            memoryPressure: pressure,
            thermalPressure: thermal
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
            compressorContents: info.total_uncompressed_pages_in_compressor,
            purgeable: UInt64(info.purgeable_count), fileBacked: UInt64(info.external_page_count),
            pageIns: info.pageins, swapIns: info.swapins, swapOuts: info.swapouts,
            pageSizeBytes: UInt64(pageSize)
        ))
    }

    private func readSwap() -> Result<SwapUsage, HostDriverError> {
        let operation = "sysctl vm.swapusage"
        switch readSysctl("vm.swapusage", as: xsw_usage.self, operation: operation) {
        case .failure(let error):
            return .failure(error)
        case .success(let usage):
            guard usage.xsu_used <= usage.xsu_total else {
                return .failure(.unexpectedValue(operation: operation, value: usage.xsu_used))
            }
            return .success(SwapUsage(totalBytes: usage.xsu_total, usedBytes: usage.xsu_used))
        }
    }

    private func readPressure() -> Result<KernelMemoryPressure, HostDriverError> {
        let operation = "sysctl kern.memorystatus_vm_pressure_level"
        switch readSysctl("kern.memorystatus_vm_pressure_level", as: UInt32.self, operation: operation) {
        case .failure(let error):
            return .failure(error)
        case .success(let level):
            guard let pressure = KernelMemoryPressure(dispatchLevel: level) else {
                return .failure(.unexpectedValue(operation: operation, value: UInt64(level)))
            }
            return .success(pressure)
        }
    }

    private func readThermalPressure() -> Result<KernelThermalPressure, HostDriverError> {
        let operation = "notify_get_state thermal pressure"
        var level: UInt64 = 0
        let status = coreo_thermal_pressure(&level)
        guard status == 0 else { return .failure(.systemCall(operation: operation, code: status)) }
        guard let pressure = KernelThermalPressure(rawValue: level) else {
            return .failure(.unexpectedValue(operation: operation, value: level))
        }
        return .success(pressure)
    }

    /// Read one fixed-size sysctl value; a short or long reply is malformed.
    private func readSysctl<Value>(
        _ name: String, as type: Value.Type, operation: String
    ) -> Result<Value, HostDriverError> {
        let expectedSize = MemoryLayout<Value>.size
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: expectedSize, alignment: MemoryLayout<Value>.alignment
        )
        defer { storage.deallocate() }

        var size = expectedSize
        guard sysctlbyname(name, storage, &size, nil, 0) == 0 else {
            return .failure(.systemCall(operation: operation, code: errno))
        }
        guard size == expectedSize else { return .failure(.malformedReply(operation: operation)) }
        return .success(storage.load(as: Value.self))
    }
    #endif
}
