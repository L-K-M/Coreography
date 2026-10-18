import Foundation
import Dispatch

#if os(macOS)
import IOKit
import IOKit.ps
#endif

/// Reads battery, gas-gauge and adapter state through public IOKit power APIs.
public actor PowerSourceDriver: PowerSampleReading {
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.power-sampling")
    private let clockID = UUID()

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func read() async -> RawPowerSnapshot {
        #if os(macOS)
        let battery = readBattery()
        let gauge = readGauge()
        let adapter = PowerSourceDecoder.adapterWatts(
            IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        )
        #else
        let battery: Result<BatteryState, PowerDriverError> = .failure(.unsupportedPlatform)
        let gauge: Result<BatteryGauge, PowerDriverError> = .failure(.unsupportedPlatform)
        let adapter: Result<Double, PowerDriverError> = .failure(.unsupportedPlatform)
        #endif

        return RawPowerSnapshot(
            clockID: clockID, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            wallTime: Date(), battery: battery, gauge: gauge, adapterWatts: adapter
        )
    }

    #if os(macOS)
    private func readBattery() -> Result<BatteryState, PowerDriverError> {
        // Copy functions return +1 references; descriptions are borrowed from the blob.
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .failure(.unavailable(reason: "IOPSCopyPowerSourcesInfo returned nothing"))
        }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .failure(.unavailable(reason: "IOPSCopyPowerSourcesList returned nothing"))
        }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return PowerSourceDecoder.battery(descriptions)
    }

    private func readGauge() -> Result<BatteryGauge, PowerDriverError> {
        // IOServiceGetMatchingService consumes the matching dictionary.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return .failure(.noBattery) }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS,
              let table = properties?.takeRetainedValue() as? [String: Any] else {
            return .failure(.unavailable(reason: "AppleSmartBattery properties unavailable (\(status))"))
        }
        return PowerSourceDecoder.gauge(table)
    }
    #endif
}
