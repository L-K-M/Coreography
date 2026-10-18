import Foundation
import CoreographyDrivers

public typealias SystemInventory = HostInventory

public enum SamplingContinuity: String, Codable, Sendable {
    case continuous
    case interrupted
}

public struct SystemSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let stamp: SampleStamp
    public let inventory: SystemInventory
    public let cpuPercentOfMachine: MetricReading
    public let memoryUsedBytes: MetricReading
    public let cpuSource: String
    public let memorySource: String
    public let continuity: SamplingContinuity

    init(
        stamp: SampleStamp, inventory: SystemInventory,
        cpuPercentOfMachine: MetricReading, memoryUsedBytes: MetricReading,
        continuity: SamplingContinuity
    ) {
        self.id = UUID()
        self.stamp = stamp
        self.inventory = inventory
        self.cpuPercentOfMachine = cpuPercentOfMachine
        self.memoryUsedBytes = memoryUsedBytes
        self.cpuSource = "Mach CPU tick counters; percent of the whole machine"
        self.memorySource = "Mach VM composition; bytes; excludes cached files"
        self.continuity = continuity
    }
}
