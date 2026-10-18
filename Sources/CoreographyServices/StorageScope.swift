import Foundation
import CoreographyKit

public typealias CapturedDisks = DiskSnapshot
public typealias CapturedStorageID = StorageDeviceID
public typealias CapturedStorageDevice = DiskDeviceReading
public typealias CapturedVolumes = VolumeList
public typealias CapturedVolume = VolumeCapacity

public enum StorageScope: Hashable, Sendable {
    case automatic
    case device(CapturedStorageID)
}

public struct DiskTableReading: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let deviceName: String?
    public let status: String?
    public let read: DashboardReading?
    public let written: DashboardReading?
}
