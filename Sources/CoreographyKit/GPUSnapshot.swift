import Foundation

public struct GPUDeviceID: Hashable, Codable, Sendable {
    public let registryEntryID: UInt64

    public init(registryEntryID: UInt64) throws {
        guard registryEntryID > 0 else { throw GPUIdentityError.invalidRegistryEntry }
        self.registryEntryID = registryEntryID
    }

    private enum CodingKeys: String, CodingKey { case registryEntryID }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(registryEntryID: values.decode(UInt64.self, forKey: .registryEntryID))
    }
}

enum GPUIdentityError: Error { case invalidRegistryEntry }

/// Driver-reported gauges for one GPU. Device utilization is busy time,
/// not per-app GPU time; memory is unified system memory in use by the GPU.
public struct GPUDeviceReading: Identifiable, Codable, Sendable {
    public let id: GPUDeviceID
    public let name: String
    public let utilizationPercent: MetricReading
    public let rendererPercent: MetricReading
    public let tilerPercent: MetricReading
    public let inUseMemoryBytes: MetricReading
}

public struct GPUCollectionIssue: Codable, Sendable {
    public let reading: MetricReading
}

public struct GPUSnapshot: Identifiable, Codable, Sendable {
    public let id: UUID
    public let stamp: SampleStamp
    public let enumeration: MetricReading
    public let enumerationTruncated: Bool
    public let devices: [GPUDeviceReading]
    public let issues: [GPUCollectionIssue]
    public let continuity: SamplingContinuity
}
