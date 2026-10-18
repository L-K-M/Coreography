import Foundation
import Dispatch

#if os(macOS)
import Darwin
import IOKit
#endif

/// Reads the byte counters the kernel publishes on each IOBlockStorageDriver.
public actor DiskIODriver: DiskSampleReading {
    /// Registry scans are bounded so an overfull table cannot stall sampling.
    private static let deviceCapacity = 256
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.disk-sampling")
    private let clockID = UUID()

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func read() async -> RawDiskSnapshot {
        let enumeration = readDevices()
        return RawDiskSnapshot(
            clockID: clockID, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            wallTime: Date(), enumeration: enumeration
        )
    }

    private func readDevices() -> Result<DiskEnumeration, DiskDriverError> {
        #if os(macOS)
        var iterator = io_iterator_t()
        // The matching dictionary reference is always consumed by this call
        // (CF_RELEASES_ARGUMENT); the +1 IOServiceMatching result is passed
        // directly and never released again.
        let status = IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator
        )
        defer { if iterator != IO_OBJECT_NULL { IOObjectRelease(iterator) } }
        guard status == KERN_SUCCESS else {
            return .failure(.systemCall(operation: "IOServiceGetMatchingServices", code: status))
        }

        var devices: [RawDiskDevice] = []
        var failures: [DiskReadFailure] = []
        var truncated = false
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard !Task.isCancelled, devices.count + failures.count < Self.deviceCapacity else {
                truncated = true
                break
            }
            if let failure = collect(service, devices: &devices) {
                failures.append(failure)
            }
        }
        // An iterator invalidated mid-scan means the registry changed while
        // enumerating, so the collected devices are only a partial view.
        return .success(DiskEnumeration(
            devices: devices, failures: failures,
            isTruncated: truncated || Task.isCancelled || IOIteratorIsValid(iterator) == 0
        ))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    /// Appends a device and returns nil; a service without a valid registry
    /// identity cannot be named or deduplicated and becomes a read failure.
    private func collect(
        _ service: io_registry_entry_t, devices: inout [RawDiskDevice]
    ) -> DiskReadFailure? {
        var registryID: UInt64 = 0
        let status = IORegistryEntryGetRegistryEntryID(service, &registryID)
        guard status == KERN_SUCCESS else {
            return DiskReadFailure(
                registryEntryID: nil,
                error: .systemCall(operation: "IORegistryEntryGetRegistryEntryID", code: status)
            )
        }
        guard registryID != 0 else {
            return DiskReadFailure(
                registryEntryID: nil,
                error: .unavailable(reason: "Storage driver reports a zero registry identity")
            )
        }

        let name = deviceName(service: service, registryID: registryID)
        let counters = statistics(service)
        // Taken after the counter read so counters pair with the sample instant.
        let timestamp = DispatchTime.now().uptimeNanoseconds
        devices.append(RawDiskDevice(
            registryEntryID: registryID, name: name,
            monotonicNanoseconds: timestamp, counters: counters
        ))
        return nil
    }

    /// IOBlockStorageDriver publishes an OSDictionary under
    /// kIOBlockStorageDriverStatisticsKey ("Statistics") holding OSNumber64
    /// counters; the decoder validates their presence and width.
    private func statistics(_ service: io_registry_entry_t) -> Result<DiskByteCounters, DiskDriverError> {
        // Returns Unmanaged<CFTypeRef>: takeRetainedValue() consumes the +1.
        guard let property = IORegistryEntryCreateCFProperty(
            service, "Statistics" as CFString, kCFAllocatorDefault, 0
        ) else {
            return .failure(.unavailable(reason: "Storage statistics are not published"))
        }
        guard let table = property.takeRetainedValue() as? [String: Any] else {
            return .failure(.unavailable(reason: "Malformed storage statistics table"))
        }
        return DiskStatisticsDecoder.counters(table)
    }

    /// BSD names are display labels; only registry identity owns the rate baseline.
    private func deviceName(service: io_registry_entry_t, registryID: UInt64) -> String {
        if let name = mediaBSDName(service) { return name }
        if let name = productName(service) { return "\(name)-\(registryID)" }
        if let name = registryName(service) { return "\(name)-\(registryID)" }
        return "disk-\(registryID)"
    }

    /// The driver's immediate IOMedia child carries kIOBSDNameKey ("BSD Name")
    /// once the IOMediaBSDClient has registered a devfs node for the media.
    private func mediaBSDName(_ service: io_registry_entry_t) -> String? {
        var children = io_iterator_t()
        let status = IORegistryEntryGetChildIterator(service, kIOServicePlane, &children)
        defer { if children != IO_OBJECT_NULL { IOObjectRelease(children) } }
        guard status == KERN_SUCCESS else {
            return nil
        }
        while case let child = IOIteratorNext(children), child != IO_OBJECT_NULL {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "IOMedia") != 0 else { continue }
            guard let whole = IORegistryEntryCreateCFProperty(
                child, "Whole" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? Bool, whole else { continue }
            guard let property = IORegistryEntryCreateCFProperty(
                child, "BSD Name" as CFString, kCFAllocatorDefault, 0
            ) else { continue }
            let value = property.takeRetainedValue()
            guard let name = value as? String, !name.isEmpty else { continue }
            return name
        }
        return nil
    }

    /// The kIOPropertyDeviceCharacteristicsKey table lives on the driver's
    /// provider chain, so the recursive parent search finds the first node
    /// that published a kIOPropertyProductNameKey.
    private func productName(_ service: io_registry_entry_t) -> String? {
        guard let characteristics = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "Device Characteristics" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) else { return nil }
        // CF_RETURNS_RETAINED is declared, so the returned value is owned and
        // must not be taken again as Unmanaged.
        guard let table = characteristics as? [String: Any],
              let raw = table["Product Name"] as? String else { return nil }
        let name = raw.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func registryName(_ service: io_registry_entry_t) -> String? {
        var buffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        guard IORegistryEntryGetName(service, &buffer) == KERN_SUCCESS else { return nil }
        let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        let name = String(decoding: bytes, as: UTF8.self)
        return name.isEmpty ? nil : name
    }
    #endif
}
