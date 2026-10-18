import Foundation
import CoreographyKit

/// Export of one selected range (plan MVP: CSV and JSON of a range).
///
/// JSON keeps every reading with its availability, provenance and reason.
/// CSV flattens one row per host sample; a missing reading is an empty
/// cell, never zero.
public enum RangeExport {
    public static let schemaVersion = 1

    public struct Document: Codable, Sendable {
        public let schemaVersion: Int
        public let start: Date
        public let end: Date
        public let host: [CapturedSnapshot]
        public let network: [CapturedNetwork]
        public let disks: [CapturedDisks]
        public let gpu: [CapturedGPU]
        public let power: [CapturedPower]
        public let sensors: [CapturedSensors]
        public let apps: [AppRangeTotal]
    }

    private static let csvColumns = [
        "time", "cpu_percent_of_machine", "memory_used_bytes", "memory_pressure_level",
        "swap_used_bytes", "thermal_pressure_level", "gpu_busy_percent", "hottest_celsius",
        "system_power_watts"
    ]
    /// A companion sample counts for a host row only within this distance.
    private static let pairingTolerance: TimeInterval = 1.5

    static func document(
        range: ClosedRange<Date>, model frames: DashboardFrames, apps: [AppRangeTotal]
    ) -> Document {
        func inRange<Frame>(_ frames: [Frame], _ time: (Frame) -> Date) -> [Frame] {
            frames.filter { range.contains(time($0)) }
        }
        return Document(
            schemaVersion: schemaVersion, start: range.lowerBound, end: range.upperBound,
            host: inRange(frames.host) { $0.stamp.wallTime },
            network: inRange(frames.network) { $0.stamp.wallTime },
            disks: inRange(frames.disks) { $0.stamp.wallTime },
            gpu: inRange(frames.gpu) { $0.stamp.wallTime },
            power: inRange(frames.power) { $0.stamp.wallTime },
            sensors: inRange(frames.sensors) { $0.stamp.wallTime },
            apps: apps
        )
    }

    public static func json(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func csv(_ document: Document) -> String {
        let timeFormat = ISO8601DateFormatter()
        var lines = [csvColumns.joined(separator: ",")]
        for frame in document.host {
            let time = frame.stamp.wallTime
            let gpu = nearest(document.gpu, to: time) { $0.stamp.wallTime }
            let sensors = nearest(document.sensors, to: time) { $0.stamp.wallTime }
            let power = nearest(document.power, to: time) { $0.stamp.wallTime }
            // Same qualified-source rule as the window: an SMC rail, else battery discharge.
            let system = sensors?.systemPowerWatts.numericValue ?? power?.systemPowerWatts.numericValue
            let cells: [Double?] = [
                frame.cpuPercentOfMachine.numericValue, frame.memoryUsedBytes.numericValue,
                frame.memory.pressure.numericValue, frame.memory.swapUsedBytes.numericValue,
                frame.thermalPressure.numericValue, gpu?.devices.first?.utilizationPercent.numericValue,
                sensors?.hottest?.celsius.numericValue, system
            ]
            lines.append(([timeFormat.string(from: time)] + cells.map { $0.map { String($0) } ?? "" })
                .joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func nearest<Frame>(_ frames: [Frame], to time: Date, _ stamp: (Frame) -> Date) -> Frame? {
        let candidate = frames.min { abs(stamp($0).timeIntervalSince(time)) < abs(stamp($1).timeIntervalSince(time)) }
        guard let candidate, abs(stamp(candidate).timeIntervalSince(time)) <= pairingTolerance else { return nil }
        return candidate
    }
}

/// The displayed frame sets a range export reads from.
struct DashboardFrames {
    let host: [CapturedSnapshot]
    let network: [CapturedNetwork]
    let disks: [CapturedDisks]
    let gpu: [CapturedGPU]
    let power: [CapturedPower]
    let sensors: [CapturedSensors]
}
