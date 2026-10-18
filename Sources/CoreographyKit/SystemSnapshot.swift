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
    /// The kernel's share of the whole machine; user and nice time make up
    /// the rest of `cpuPercentOfMachine`. Absent in recordings made before it.
    public let cpuSystemPercentOfMachine: MetricReading?
    public let memoryUsedBytes: MetricReading
    public let memory: MemoryDetail
    /// Measured `ThermalPressureLevel` ordinal.
    public let thermalPressure: MetricReading
    public let cpuSource: String
    public let memorySource: String
    public let continuity: SamplingContinuity

    init(
        stamp: SampleStamp, inventory: SystemInventory,
        cpuPercentOfMachine: MetricReading, cpuSystemPercentOfMachine: MetricReading? = nil, memoryUsedBytes: MetricReading,
        memory: MemoryDetail, thermalPressure: MetricReading, continuity: SamplingContinuity
    ) {
        self.id = UUID()
        self.stamp = stamp
        self.inventory = inventory
        self.cpuPercentOfMachine = cpuPercentOfMachine
        self.cpuSystemPercentOfMachine = cpuSystemPercentOfMachine
        self.memoryUsedBytes = memoryUsedBytes
        self.memory = memory
        self.thermalPressure = thermalPressure
        self.cpuSource = "Mach CPU tick counters; percent of the whole machine"
        self.memorySource = "Mach VM composition; bytes; excludes cached files"
        self.continuity = continuity
    }
}
