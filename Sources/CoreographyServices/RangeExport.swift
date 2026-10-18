import Foundation
import CoreographyKit

/// Export of one selected range (plan MVP: CSV and JSON of a range).
///
/// JSON keeps every reading with its availability, provenance and reason.
/// CSV flattens one row per host sample; a missing reading is an empty
/// cell, never zero.
/// Whether an export names the user's apps (plan: exports redact
/// identifiers for sharing). Interfaces, storage drivers and sensor keys
/// describe the Mac, not the person, and stay.
public enum ExportNaming: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Apps become "App 1", "App 2", … in CPU order: safe to share.
    case redacted
    case named

    public var id: Self { self }
}

public enum RangeExport {
    /// Version 2 added `appNames`, saying whether names were redacted.
    public static let schemaVersion = 2

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
        public let appNames: ExportNaming
        public let apps: [AppRangeTotal]
    }

    private static let csvColumns = [
        "time", "cpu_percent_of_machine", "memory_used_bytes", "memory_pressure_level",
        "swap_used_bytes", "thermal_pressure_level", "gpu_busy_percent", "hottest_sensor", "hottest_celsius",
        "system_power_watts"
    ]
    /// A companion sample counts for a host row only within this distance.
    private static let pairingTolerance: TimeInterval = 1.5

    /// - Parameter apps: in CPU order, so redacted labels follow the ranking.
    static func document(
        range: ClosedRange<Date>, model frames: DashboardFrames, apps: [AppRangeTotal], naming: ExportNaming
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
            appNames: naming,
            apps: naming == .named ? apps : apps.enumerated().map { index, app in
                AppRangeTotal(
                    name: "App \(index + 1)", cpuSeconds: app.cpuSeconds, diskBytes: app.diskBytes,
                    networkBytes: app.networkBytes, isLowerBound: app.isLowerBound
                )
            }
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
            func cell(_ value: Double?) -> String { value.map { String($0) } ?? "" }
            // The sensor key travels with its reading: the hottest sensor can change between rows.
            let hottest = sensors?.hottest
            let cells = [
                timeFormat.string(from: time),
                cell(frame.cpuPercentOfMachine.numericValue), cell(frame.memoryUsedBytes.numericValue),
                cell(frame.memory.pressure.numericValue), cell(frame.memory.swapUsedBytes.numericValue),
                cell(frame.thermalPressure.numericValue), cell(gpu?.devices.first?.utilizationPercent.numericValue),
                hottest?.celsius.numericValue == nil ? "" : (hottest?.key ?? ""),
                cell(hottest?.celsius.numericValue), cell(system)
            ]
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Frames are in time order, so a binary search finds the closest pairing.
    private static func nearest<Frame>(_ frames: [Frame], to time: Date, _ stamp: (Frame) -> Date) -> Frame? {
        var low = 0
        var high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if stamp(frames[middle]) < time { low = middle + 1 } else { high = middle }
        }
        let candidates = [low - 1, low].filter { frames.indices.contains($0) }.map { frames[$0] }
        let candidate = candidates.min { abs(stamp($0).timeIntervalSince(time)) < abs(stamp($1).timeIntervalSince(time)) }
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
