import Foundation

/// The startup volume's size and the space available for important use
/// (what Finder shows as available, purgeable space included).
public struct RawVolumeCapacity: Equatable, Sendable {
    public let totalBytes: Int64
    public let availableBytes: Int64

    public init(totalBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }
}

public enum VolumeCapacityError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case unavailable(String)
}

public protocol VolumeCapacityReading: Sendable {
    func startupVolume() async -> Result<RawVolumeCapacity, VolumeCapacityError>
}

/// Reads capacity through public URL resource values; no privilege needed.
public struct VolumeCapacityDriver: VolumeCapacityReading {
    public init() {}

    public func startupVolume() async -> Result<RawVolumeCapacity, VolumeCapacityError> {
        #if os(macOS)
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: keys)
            guard let total = values.volumeTotalCapacity, total > 0,
                  let available = values.volumeAvailableCapacityForImportantUsage else {
                return .failure(.unavailable("The startup volume reports no capacity"))
            }
            return .success(RawVolumeCapacity(totalBytes: Int64(total), availableBytes: available))
        } catch {
            return .failure(.unavailable("The startup volume's capacity could not be read"))
        }
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }
}
