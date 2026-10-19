import Foundation
import Dispatch

#if os(macOS)
import IOKit
#endif

/// One process's connection to a GPU and the GPU time its command queues used.
public struct RawGPUClient: Equatable, Sendable {
    /// The client's registry entry; a reopened connection gets a new one.
    public let registryEntryID: UInt64
    public let pid: Int32
    /// Sum of `accumulatedGPUTime` over the client's command queues.
    public let gpuNanoseconds: UInt64

    public init(registryEntryID: UInt64, pid: Int32, gpuNanoseconds: UInt64) {
        self.registryEntryID = registryEntryID
        self.pid = pid
        self.gpuNanoseconds = gpuNanoseconds
    }
}

public struct GPUClientWalk: Sendable {
    public let clients: [RawGPUClient]
    /// False when clients opened or closed during every attempt, so some may be missing.
    public let isComplete: Bool

    public init(clients: [RawGPUClient], isComplete: Bool) {
        self.clients = clients
        self.isComplete = isComplete
    }
}

public struct RawGPUClientSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let walk: Result<GPUClientWalk, GPUDriverError>

    public init(clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date, walk: Result<GPUClientWalk, GPUDriverError>) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.walk = walk
    }
}

public protocol GPUClientTimeReading: Sendable {
    func read() async -> RawGPUClientSnapshot
}

/// Reads GPU time per user client (plan: per-process GPU, as Activity
/// Monitor's % GPU). Clients are unregistered children of each
/// IOAccelerator in the service plane, so no matching query finds them;
/// the walk reads their properties and opens nothing.
///
/// ```text
/// IOAccelerator (AGXAccelerator…)
///   ├─ user client  IOUserClientCreator "pid 631, WindowServer"
///   │               AppUsage [{accumulatedGPUTime: ns, …}, …]   one per command queue
///   └─ user client  …
/// ```
public actor GPUClientDriver: GPUClientTimeReading {
    /// A client opening or closing mid-walk invalidates the iterator; walk again this many times.
    private static let walkAttempts = 3
    private static let creatorKey = "IOUserClientCreator"
    private static let usageKey = "AppUsage"
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.gpu-clients")
    private let clockID = UUID()

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func read() async -> RawGPUClientSnapshot {
        let walk = walkClients()
        return RawGPUClientSnapshot(
            clockID: clockID, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds, wallTime: Date(), walk: walk
        )
    }

    private func walkClients() -> Result<GPUClientWalk, GPUDriverError> {
        #if os(macOS)
        var gpus = io_iterator_t()
        // IOServiceGetMatchingServices consumes the matching dictionary.
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &gpus)
        defer { if gpus != IO_OBJECT_NULL { IOObjectRelease(gpus) } }
        guard status == KERN_SUCCESS else {
            return .failure(.systemCall(operation: "IOServiceGetMatchingServices", code: status))
        }

        var clients: [RawGPUClient] = []
        var complete = true
        while case let gpu = IOIteratorNext(gpus), gpu != IO_OBJECT_NULL {
            defer { IOObjectRelease(gpu) }
            var attempt = 1
            while true {
                let walked = children(of: gpu)
                guard case .success(let found) = walked else {
                    if case .failure(let error) = walked { return .failure(error) }
                    break
                }
                if found.isComplete || attempt == Self.walkAttempts {
                    clients += found.clients
                    complete = complete && found.isComplete
                    break
                }
                attempt += 1
            }
        }
        return .success(GPUClientWalk(clients: clients, isComplete: complete))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    private func children(of gpu: io_registry_entry_t) -> Result<GPUClientWalk, GPUDriverError> {
        var iterator = io_iterator_t()
        let status = IORegistryEntryGetChildIterator(gpu, kIOServicePlane, &iterator)
        defer { if iterator != IO_OBJECT_NULL { IOObjectRelease(iterator) } }
        guard status == KERN_SUCCESS else {
            return .failure(.systemCall(operation: "IORegistryEntryGetChildIterator", code: status))
        }

        var clients: [RawGPUClient] = []
        while case let child = IOIteratorNext(iterator), child != IO_OBJECT_NULL {
            defer { IOObjectRelease(child) }
            // Children without a creator are not user clients (e.g. the GPU's own services).
            guard let creator = property(child, Self.creatorKey) as? String,
                  let pid = GPUClientDecoder.pid(creator: creator) else { continue }
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(child, &registryID) == KERN_SUCCESS, registryID != 0 else { continue }
            clients.append(RawGPUClient(
                registryEntryID: registryID, pid: pid,
                gpuNanoseconds: GPUClientDecoder.gpuNanoseconds(appUsage: property(child, Self.usageKey))
            ))
        }
        return .success(GPUClientWalk(clients: clients, isComplete: IOIteratorIsValid(iterator) != 0))
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        // Unmanaged +1 result; takeRetainedValue() balances it.
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    #endif
}

/// Decodes a GPU user client's registry properties. Both are driver
/// conventions, not SDK constants, so anything else reads as absent.
enum GPUClientDecoder {
    private static let creatorPrefix = "pid "
    private static let gpuTimeKey = "accumulatedGPUTime"

    /// `"pid 631, WindowServer"` → 631.
    static func pid(creator: String) -> Int32? {
        guard creator.hasPrefix(creatorPrefix) else { return nil }
        let digits = creator.dropFirst(creatorPrefix.count).prefix { $0 != "," }
        guard let pid = Int32(digits), pid >= 0 else { return nil }
        return pid
    }

    /// Total `accumulatedGPUTime` of `AppUsage`, one dictionary per command
    /// queue; entries without a non-negative integer are skipped.
    static func gpuNanoseconds(appUsage: Any?) -> UInt64 {
        guard let queues = appUsage as? [Any] else { return 0 }
        var total: UInt64 = 0
        for case let queue as [String: Any] in queues {
            guard let time = GPUStatisticsDecoder.unsigned(queue[gpuTimeKey]) else { continue }
            total = total.addingReportingOverflow(time).overflow ? .max : total + time
        }
        return total
    }
}
