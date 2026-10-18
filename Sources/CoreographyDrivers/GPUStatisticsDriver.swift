import Foundation
import Dispatch

#if os(macOS)
import IOKit
#endif

/// Reads utilization each IOAccelerator publishes in its registry entry.
/// No user client is opened, so no privilege or entitlement is needed.
public actor GPUStatisticsDriver: GPUSampleReading {
    private static let deviceCapacity = 16
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.gpu-sampling")
    private let clockID = UUID()

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func read() async -> RawGPUSnapshot {
        let enumeration = readDevices()
        return RawGPUSnapshot(
            clockID: clockID, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            wallTime: Date(), enumeration: enumeration
        )
    }

    private func readDevices() -> Result<GPUEnumeration, GPUDriverError> {
        #if os(macOS)
        var iterator = io_iterator_t()
        // IOServiceGetMatchingServices consumes the matching dictionary.
        let status = IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
        )
        defer { if iterator != IO_OBJECT_NULL { IOObjectRelease(iterator) } }
        guard status == KERN_SUCCESS else {
            return .failure(.systemCall(operation: "IOServiceGetMatchingServices", code: status))
        }

        var devices: [RawGPUDevice] = []
        var failures: [GPUDriverError] = []
        var truncated = false
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard !Task.isCancelled, devices.count + failures.count < Self.deviceCapacity else {
                truncated = true
                break
            }
            var registryID: UInt64 = 0
            let idStatus = IORegistryEntryGetRegistryEntryID(service, &registryID)
            guard idStatus == KERN_SUCCESS else {
                failures.append(.systemCall(operation: "IORegistryEntryGetRegistryEntryID", code: idStatus))
                continue
            }
            guard registryID != 0 else {
                failures.append(.unavailable(reason: "GPU reports a zero registry identity"))
                continue
            }
            devices.append(RawGPUDevice(
                registryEntryID: registryID, name: name(service, registryID: registryID),
                statistics: statistics(service)
            ))
        }
        return .success(GPUEnumeration(
            devices: devices, failures: failures,
            isTruncated: truncated || Task.isCancelled || IOIteratorIsValid(iterator) == 0
        ))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    private func statistics(_ service: io_registry_entry_t) -> Result<GPUStatistics, GPUDriverError> {
        // Unmanaged +1 result; takeRetainedValue() balances it.
        guard let property = IORegistryEntryCreateCFProperty(
            service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
        ) else {
            return .failure(.unavailable(reason: "GPU performance statistics are not published"))
        }
        guard let table = property.takeRetainedValue() as? [String: Any] else {
            return .failure(.unavailable(reason: "Malformed GPU performance statistics"))
        }
        return GPUStatisticsDecoder.statistics(table)
    }

    /// AGX publishes "model" as a string; AMD and Intel as NUL-terminated data.
    private func name(_ service: io_registry_entry_t, registryID: UInt64) -> String {
        if let property = IORegistryEntryCreateCFProperty(
            service, "model" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() {
            if let model = property as? String, !model.isEmpty { return model }
            if let data = property as? Data {
                let model = String(decoding: data.prefix(while: { $0 != 0 }), as: UTF8.self)
                if !model.isEmpty { return model }
            }
        }
        var buffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        if IOObjectGetClass(service, &buffer) == KERN_SUCCESS {
            let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            let className = String(decoding: bytes, as: UTF8.self)
            if !className.isEmpty { return className }
        }
        return "GPU-\(registryID)"
    }
    #endif
}
