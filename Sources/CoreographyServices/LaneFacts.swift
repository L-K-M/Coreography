import Foundation
import CoreographyKit

/// One static fact, or the source of one reading, behind a lane (plan: the
/// inspector for a lane or device shows static facts and the data sources
/// behind each reading).
public struct LaneFact: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case fact, source }

    /// The fact's place in its lane's list: labels can repeat, such as two volumes named "Untitled".
    public let id: Int
    public let kind: Kind
    public let label: String
    public let value: String

    init(id: Int = 0, kind: Kind, label: String, value: String) {
        self.id = id
        self.kind = kind
        self.label = label
        self.value = value
    }
}

/// Facts from the displayed frames, so a held window describes what it shows.
///
/// ```text
/// CPU lane:  Chip  Apple M4 · Logical CPUs  10 · Core tiers  4 P, 6 E
///            CPU   measured · cpu · Mach · HOST_CPU_LOAD_INFO
/// ```
enum LaneFacts {
    struct Inputs {
        var system: CapturedSystemFacts?
        var host: CapturedSnapshot?
        var gpu: CapturedGPU?
        var network: CapturedNetwork?
        var disks: CapturedDisks?
        var volumes: CapturedVolumes?
        var power: CapturedPower?
        var sensors: CapturedSensors?
        var silicon: CapturedSilicon?
    }

    static func facts(_ lane: LaneKind, _ inputs: Inputs) -> [LaneFact] {
        unnumbered(lane, inputs).enumerated().map {
            LaneFact(id: $0.offset, kind: $0.element.kind, label: $0.element.label, value: $0.element.value)
        }
    }

    private static func unnumbered(_ lane: LaneKind, _ inputs: Inputs) -> [LaneFact] {
        switch lane {
        case .cpu:
            let tiers = inputs.silicon?.cpuTiers ?? []
            return [
                fact("Chip", inputs.system?.chip), fact("Model", inputs.system?.model),
                fact("Logical CPUs", inputs.host.map { "\($0.inventory.logicalCPUCount)" }),
                fact("Core tiers", tiers.isEmpty ? nil : tiers.map { "\($0.cores) \($0.kind.rawValue)" }.joined(separator: ", "))
            ].compactMap { $0 } + sources(
                [("CPU", inputs.host?.cpuPercentOfMachine), ("Kernel share", inputs.host?.cpuSystemPercentOfMachine)]
                    + tiers.map { ("\($0.kind.rawValue) frequency", $0.frequencyMHz) }
            )
        case .memory:
            return [
                fact("Physical memory", inputs.host.map { bytes(Double($0.inventory.physicalMemoryBytes)) })
            ].compactMap { $0 } + sources([
                ("Memory used", inputs.host?.memoryUsedBytes), ("Pressure", inputs.host?.memory.pressure),
                ("Swap used", inputs.host?.memory.swapUsedBytes)
            ])
        case .gpu:
            let devices = inputs.gpu?.devices ?? []
            return devices.enumerated().map { LaneFact(kind: .fact, label: devices.count == 1 ? "GPU" : "GPU \($0.offset + 1)", value: $0.element.name) }
                + sources([("GPUs", inputs.gpu?.enumeration), ("Utilization", devices.first?.utilizationPercent)])
        case .disk:
            let devices = inputs.disks?.devices ?? []
            let volumes = inputs.volumes?.volumes ?? []
            return devices.enumerated().map {
                LaneFact(kind: .fact, label: devices.count == 1 ? "Storage device" : "Storage device \($0.offset + 1)", value: $0.element.name)
            }
                + volumes.map { LaneFact(kind: .fact, label: "Volume \($0.name)", value: bytes(Double($0.totalBytes))) }
                + sources([("Storage devices", inputs.disks?.enumeration), ("Disk read", devices.first?.readBytesPerSecond)])
        case .network:
            let interfaces = inputs.network?.interfaces ?? []
            return [
                fact("Primary interface", inputs.network?.primaryInterface?.name),
                fact("Interfaces", interfaces.isEmpty ? nil : interfaces.map(\.id.name).joined(separator: ", "))
            ].compactMap { $0 } + sources([("Interfaces", inputs.network?.enumeration), ("Primary", inputs.network?.primaryIssue)])
        case .power:
            return [
                fact("Adapter rating", inputs.power?.adapterRatingWatts.numericValue.map { "\(Int($0.rounded())) W" }),
                fact("Battery health", inputs.power?.batteryHealthPercent.numericValue.map { "\(Int($0.rounded()))%" }),
                fact("Battery cycles", inputs.power?.batteryCycleCount.numericValue.map { "\(Int($0))" })
            ].compactMap { $0 } + sources([
                ("Battery", inputs.power?.batteryChargePercent), ("Power source draw", inputs.power?.systemPowerWatts),
                ("System power rail", inputs.sensors?.systemPowerWatts)
            ])
        case .thermal:
            return [
                fact("Temperature sensors", inputs.sensors.map { "\($0.plausibleTemperatureCount)" }),
                fact("Fans", inputs.sensors.map { "\($0.fans.count)" })
            ].compactMap { $0 } + sources([
                ("Sensors", inputs.sensors?.source), ("Hottest", inputs.sensors?.hottest?.celsius),
                ("Thermal pressure", inputs.host?.thermalPressure)
            ])
        }
    }

    private static func fact(_ label: String, _ value: String?) -> LaneFact? {
        value.map { LaneFact(kind: .fact, label: label, value: $0) }
    }

    /// Example: "measured · cpu · Mach · HOST_CPU_LOAD_INFO", or the reason a reading is missing.
    private static func sources(_ readings: [(String, MetricReading?)]) -> [LaneFact] {
        readings.compactMap { label, reading in
            guard let reading else { return nil }
            let origin = [reading.source?.provider, reading.source?.driver, reading.source?.channel].compactMap { $0 }
            let detail = reading.reason.map { [$0] } ?? reading.method.map { [$0] } ?? []
            return LaneFact(kind: .source, label: label, value: ([reading.availability.rawValue] + origin + detail).joined(separator: " · "))
        }
    }

    private static func bytes(_ value: Double) -> String {
        Int64(value).formatted(.byteCount(style: .memory))
    }
}

extension DashboardModel {
    /// The inspector shows a lane's page in place of a selected process,
    /// so asking for one lets go of the process.
    public func showLaneFacts(_ lane: LaneKind) {
        selectedProcessRow = nil
        inspectedLane = lane
    }

    /// What the inspector shows for a lane: static facts and the source of each reading.
    public func laneFacts(_ lane: LaneKind) -> [LaneFact] {
        LaneFacts.facts(lane, LaneFacts.Inputs(
            system: systemFacts(), host: displayedFrame, gpu: displayedGPUFrame,
            network: displayedNetworkFrame, disks: displayedDiskFrame,
            volumes: volumes, power: displayedPowerFrame, sensors: displayedSensorFrame, silicon: displayedSiliconFrame
        ))
    }
}
