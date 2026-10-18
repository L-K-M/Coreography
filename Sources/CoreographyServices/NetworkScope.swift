import Foundation
import CoreographyKit

public typealias CapturedNetwork = NetworkSnapshot
public typealias CapturedInterfaceID = NetworkInterfaceID
public typealias CapturedInterface = NetworkInterfaceReading

public enum NetworkScope: Hashable, Sendable {
    case primary
    case interface(CapturedInterfaceID)
}

public struct NetworkTableReading: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let interfaceName: String?
    public let received: DashboardReading
    public let sent: DashboardReading
}
