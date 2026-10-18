import Foundation
import CoreographyKit

/// Coreography's own resource use beside the plan's published budget (P21).
public struct SelfCost: Sendable {
    /// Plan budget: under 1% of one core with the window open at 1 s sampling.
    public static let cpuBudgetPercentOfOneCore = 1.0
    /// Plan budget: under 150 MB footprint.
    public static let footprintBudgetBytes = 150_000_000.0
    /// Plan budget: under 5 wakeups per second beyond the sampling rate.
    public static let wakeupBudgetBeyondSampling = 5.0
    /// The window samples once a second, so one wakeup a second is the sampling itself.
    static let samplingWakeupsPerSecond = 1.0

    public let cpuPercentOfOneCore: MetricReading
    public let footprintBytes: MetricReading
    public let wakeupsPerSecond: MetricReading

    public var cpuOverBudget: Bool { (cpuPercentOfOneCore.numericValue ?? 0) > Self.cpuBudgetPercentOfOneCore }
    public var footprintOverBudget: Bool { (footprintBytes.numericValue ?? 0) > Self.footprintBudgetBytes }
    public var wakeupsOverBudget: Bool {
        (wakeupsPerSecond.numericValue ?? 0) - Self.samplingWakeupsPerSecond > Self.wakeupBudgetBeyondSampling
    }

    /// The collector's own process row, converted from whole-machine CPU
    /// share to the budget's one-core scale.
    static func measure(in processes: CapturedProcesses?, logicalCPUCount: Int?) -> SelfCost? {
        guard let processes,
              let own = processes.processes.first(where: { $0.id.pid == processes.collectorPID }) else { return nil }
        let cpu: MetricReading
        if let share = own.cpuPercentOfMachine.numericValue, let count = logicalCPUCount, count > 0 {
            cpu = (try? .measured(share * Double(count), source: own.cpuPercentOfMachine.source))
                ?? .gap(reason: "Non-finite CPU share")
        } else if own.cpuPercentOfMachine.numericValue != nil {
            cpu = .gap(reason: "Logical CPU count unknown")
        } else {
            cpu = own.cpuPercentOfMachine
        }
        return SelfCost(cpuPercentOfOneCore: cpu, footprintBytes: own.memoryFootprintBytes, wakeupsPerSecond: own.wakeupsPerSecond)
    }
}
