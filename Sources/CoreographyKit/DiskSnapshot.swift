import Foundation

public struct StorageDeviceID: Hashable, Codable, Sendable {
    public let registryEntryID: UInt64

    public init(registryEntryID: UInt64) throws {
        guard registryEntryID > 0 else { throw StorageIdentityError.invalidRegistryEntry }
        self.registryEntryID = registryEntryID
    }

    private enum CodingKeys: String, CodingKey { case registryEntryID }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(registryEntryID: values.decode(UInt64.self, forKey: .registryEntryID))
    }
}

enum StorageIdentityError: Error { case invalidRegistryEntry }

public struct DiskDeviceReading: Identifiable, Codable, Sendable {
    public let id: StorageDeviceID
    public let name: String
    public let stamp: SampleStamp
    public let readBytesPerSecond: MetricReading
    public let writtenBytesPerSecond: MetricReading
}

public struct DiskCollectionIssue: Codable, Sendable {
    public let registryEntryID: UInt64?
    public let reading: MetricReading
}

public struct DiskSnapshot: Identifiable, Codable, Sendable {
    public let id: UUID
    public let stamp: SampleStamp
    public let enumeration: MetricReading
    public let enumerationTruncated: Bool
    public let devices: [DiskDeviceReading]
    public let issues: [DiskCollectionIssue]
    public let continuity: SamplingContinuity
}
