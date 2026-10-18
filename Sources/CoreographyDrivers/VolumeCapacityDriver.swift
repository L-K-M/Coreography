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

public enum RawVolumeKind: String, Codable, Equatable, Sendable {
    case `internal`, external, network
}

/// One mounted, visible volume (plan: per-volume capacity in the Disk lane).
public struct RawVolume: Equatable, Sendable {
    public let path: String
    public let name: String
    public let kind: RawVolumeKind
    public let isStartup: Bool
    public let capacity: RawVolumeCapacity

    public init(path: String, name: String, kind: RawVolumeKind, isStartup: Bool, capacity: RawVolumeCapacity) {
        self.path = path
        self.name = name
        self.kind = kind
        self.isStartup = isStartup
        self.capacity = capacity
    }
}

public enum VolumeCapacityError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case unavailable(String)
}

public protocol VolumeCapacityReading: Sendable {
    func startupVolume() async -> Result<RawVolumeCapacity, VolumeCapacityError>
    /// Every visible mounted volume with a readable size.
    func mountedVolumes() async -> Result<[RawVolume], VolumeCapacityError>
}

extension VolumeCapacityReading {
    public func mountedVolumes() async -> Result<[RawVolume], VolumeCapacityError> { .failure(.unsupportedPlatform) }
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

    public func mountedVolumes() async -> Result<[RawVolume], VolumeCapacityError> {
        #if os(macOS)
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey
        ]
        // Hidden volumes are the system's own (VM, Preboot, Update); Finder does not show them either.
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return .failure(.unavailable("Mounted volumes could not be listed"))
        }
        return .success(urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return VolumeDecoder.volume(
                path: url.path, name: values.volumeLocalizedName, total: values.volumeTotalCapacity,
                important: values.volumeAvailableCapacityForImportantUsage, available: values.volumeAvailableCapacity,
                isInternal: values.volumeIsInternal, isLocal: values.volumeIsLocal, isRoot: values.volumeIsRootFileSystem
            )
        })
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }
}

/// Turns resource values into a volume, or nothing when its size is unknown.
enum VolumeDecoder {
    static func volume(
        path: String, name: String?, total: Int?, important: Int64?, available: Int?,
        isInternal: Bool?, isLocal: Bool?, isRoot: Bool?
    ) -> RawVolume? {
        guard let total, total > 0 else { return nil }
        // Important-use space counts purgeable files, as Finder does; some volumes only report plain space.
        guard let free = important ?? available.map(Int64.init), free >= 0 else { return nil }
        let kind: RawVolumeKind = isLocal == false ? .network : (isInternal == true ? .internal : .external)
        let fallback = (path as NSString).lastPathComponent
        return RawVolume(
            path: path, name: name.flatMap { $0.isEmpty ? nil : $0 } ?? (fallback.isEmpty ? path : fallback),
            kind: kind, isStartup: isRoot == true,
            capacity: RawVolumeCapacity(totalBytes: Int64(total), availableBytes: min(free, Int64(total)))
        )
    }
}
