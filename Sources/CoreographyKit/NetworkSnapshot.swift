import Foundation
import CoreographyDrivers

public typealias InterfaceLinkState = NetworkLinkState
public typealias PrimaryInterfaceFamily = PrimaryNetworkFamily

public struct NetworkInterfaceID: Hashable, Codable, Sendable {
    public let index: UInt32
    public let name: String

    public init(index: UInt32, name: String) throws {
        guard index > 0, !name.isEmpty, !name.utf8.contains(0) else {
            throw NetworkIdentityError.invalidInterface
        }
        self.index = index
        self.name = name
    }

    private enum CodingKeys: String, CodingKey { case index, name }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            index: values.decode(UInt32.self, forKey: .index),
            name: values.decode(String.self, forKey: .name)
        )
    }
}

enum NetworkIdentityError: Error { case invalidInterface }

public struct NetworkInterfaceReading: Identifiable, Codable, Sendable {
    public let id: NetworkInterfaceID
    public let stamp: SampleStamp
    public let linkState: InterfaceLinkState
    public let receivedBytesPerSecond: MetricReading
    public let sentBytesPerSecond: MetricReading
}

public struct NetworkCollectionIssue: Codable, Sendable {
    public let index: UInt32
    public let reading: MetricReading
}

public struct NetworkSnapshot: Identifiable, Codable, Sendable {
    public let id: UUID
    public let stamp: SampleStamp
    public let enumeration: MetricReading
    public let enumerationTruncated: Bool
    public let interfaces: [NetworkInterfaceReading]
    public let issues: [NetworkCollectionIssue]
    public let primaryInterface: NetworkInterfaceID?
    public let primaryFamily: PrimaryInterfaceFamily?
    public let primaryIssue: MetricReading?
    public let continuity: SamplingContinuity
}
