import Foundation
import CoreographyKit

/// A frozen copy of a time range (plan: recordings, saved as a portable
/// `.coreotrace` package that opens in Coreography for scrubbing, replay
/// and comparison). It is JSON with a documented schema:
///
/// ```text
/// schemaVersion  1
/// name, start, end, appNames ("redacted" or "named"), savedAt
/// host, network, disks, gpu, power, sensors   frames as the window holds them
/// ledger         per-app intervals, so range reports work in replay
/// markers        time and label of every marker in the range
/// ```
/// Redacted recordings number apps in CPU order, the same name for the same
/// app throughout, so replayed reports still rank correctly.
public enum Recording {
    public static let schemaVersion = 1
    public static let fileExtension = "coreotrace"
    /// A recording holds at most the live hour; anything this large is not one.
    public static let maximumBytes = 256 * 1024 * 1024

    public struct Entry: Codable, Equatable, Sendable {
        public let app: String
        public let cpuSeconds: Double
        public let diskBytes: Double
        public let networkBytes: Double
        public let energyJoules: Double
        public let isLowerBound: Bool

        init(
            app: String, cpuSeconds: Double, diskBytes: Double, networkBytes: Double,
            energyJoules: Double = 0, isLowerBound: Bool
        ) {
            self.app = app
            self.cpuSeconds = cpuSeconds
            self.diskBytes = diskBytes
            self.networkBytes = networkBytes
            self.energyJoules = energyJoules
            self.isLowerBound = isLowerBound
        }

        private enum CodingKeys: String, CodingKey {
            case app, cpuSeconds, diskBytes, networkBytes, energyJoules, isLowerBound
        }

        /// Recordings saved before energy was kept have no `energyJoules`.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            app = try container.decode(String.self, forKey: .app)
            cpuSeconds = try container.decode(Double.self, forKey: .cpuSeconds)
            diskBytes = try container.decode(Double.self, forKey: .diskBytes)
            networkBytes = try container.decode(Double.self, forKey: .networkBytes)
            energyJoules = try container.decodeIfPresent(Double.self, forKey: .energyJoules) ?? 0
            isLowerBound = try container.decode(Bool.self, forKey: .isLowerBound)
        }
    }

    public struct Interval: Codable, Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let cores: Double
        public let coversNetwork: Bool
        public let coversEnergy: Bool
        public let entries: [Entry]

        init(start: Date, end: Date, cores: Double, coversNetwork: Bool, coversEnergy: Bool = false, entries: [Entry]) {
            self.start = start
            self.end = end
            self.cores = cores
            self.coversNetwork = coversNetwork
            self.coversEnergy = coversEnergy
            self.entries = entries
        }

        private enum CodingKeys: String, CodingKey {
            case start, end, cores, coversNetwork, coversEnergy, entries
        }

        /// Recordings saved before energy was kept have no `coversEnergy`.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            start = try container.decode(Date.self, forKey: .start)
            end = try container.decode(Date.self, forKey: .end)
            cores = try container.decode(Double.self, forKey: .cores)
            coversNetwork = try container.decode(Bool.self, forKey: .coversNetwork)
            coversEnergy = try container.decodeIfPresent(Bool.self, forKey: .coversEnergy) ?? false
            entries = try container.decode([Entry].self, forKey: .entries)
        }
    }

    public struct Marker: Codable, Equatable, Sendable {
        public let time: Date
        public let label: String
        /// Absent in recordings saved before kinds were kept.
        public var kind: MarkerKind?
    }

    public struct Document: Codable, Sendable {
        public let schemaVersion: Int
        public let name: String
        public let savedAt: Date
        public let start: Date
        public let end: Date
        public let appNames: ExportNaming
        public let host: [CapturedSnapshot]
        public let network: [CapturedNetwork]
        public let disks: [CapturedDisks]
        public let gpu: [CapturedGPU]
        public let power: [CapturedPower]
        public let sensors: [CapturedSensors]
        public let ledger: [Interval]
        public let markers: [Marker]
    }

    public enum Failure: Error, Equatable, Sendable {
        case tooLarge
        case unreadable(String)
        case newerSchema(Int)
        case invalidRange

        public var message: String {
            switch self {
            case .tooLarge: "The file is larger than any recording"
            case .unreadable(let detail): "The recording could not be read: \(detail)"
            case .newerSchema(let version): "The recording uses a newer format (\(version)); update Coreography"
            case .invalidRange: "The recording's time range is invalid"
            }
        }
    }

    static func make(
        name: String, range: ClosedRange<Date>, frames: DashboardFrames, ledger: AppLedger,
        markers: [TimelineMarker], naming: ExportNaming, now: Date = Date()
    ) -> Document {
        func inRange<Frame>(_ frames: [Frame], _ time: (Frame) -> Date) -> [Frame] {
            frames.filter { range.contains(time($0)) }
        }
        let intervals = ledger.storedIntervals(in: range)
        let rename = naming == .named ? [:] : placeholders(intervals)
        return Document(
            schemaVersion: schemaVersion, name: name, savedAt: now, start: range.lowerBound, end: range.upperBound,
            appNames: naming,
            host: inRange(frames.host) { $0.stamp.wallTime }, network: inRange(frames.network) { $0.stamp.wallTime },
            disks: inRange(frames.disks) { $0.stamp.wallTime }, gpu: inRange(frames.gpu) { $0.stamp.wallTime },
            power: inRange(frames.power) { $0.stamp.wallTime }, sensors: inRange(frames.sensors) { $0.stamp.wallTime },
            ledger: intervals.map { interval in
                Interval(
                    start: interval.start, end: interval.end, cores: interval.cores, coversNetwork: interval.coversNetwork,
                    coversEnergy: interval.coversEnergy,
                    entries: interval.entries.map {
                        Entry(app: rename[$0.app] ?? $0.app, cpuSeconds: $0.cpuSeconds, diskBytes: $0.diskBytes,
                              networkBytes: $0.networkBytes, energyJoules: $0.energyJoules, isLowerBound: $0.isLowerBound)
                    }
                )
            },
            // A person's marker names can identify work; a redacted recording keeps their times only.
            markers: markers.filter { range.contains($0.time) }.map {
                Marker(time: $0.time, label: naming == .named || $0.kind != .note ? $0.label : "Marker", kind: $0.kind)
            }
        )
    }

    public static func encode(_ document: Document) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws(Failure) -> Document {
        guard data.count <= maximumBytes else { throw .tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Read the version first, so a newer file says so instead of failing on a field.
        struct Version: Decodable { let schemaVersion: Int }
        guard let version = try? decoder.decode(Version.self, from: data) else {
            throw .unreadable("not a Coreography recording")
        }
        guard version.schemaVersion <= schemaVersion else { throw .newerSchema(version.schemaVersion) }
        let document: Document
        do {
            document = try decoder.decode(Document.self, from: data)
        } catch {
            throw .unreadable("\(error)")
        }
        guard document.start <= document.end else { throw .invalidRange }
        return document
    }

    /// "App 1", "App 2", … in descending total CPU-seconds.
    private static func placeholders(_ intervals: [LedgerInterval]) -> [String: String] {
        var cpu: [String: Double] = [:]
        for entry in intervals.flatMap(\.entries) { cpu[entry.app, default: 0] += entry.cpuSeconds }
        let ranked = cpu.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        return Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($0.element.key, "App \($0.offset + 1)") })
    }
}

extension AppLedger {
    /// Intervals whose midpoint lies in the range, in their stored form.
    func storedIntervals(in range: ClosedRange<Date>) -> [LedgerInterval] {
        intervals.filter { range.contains($0.start.addingTimeInterval($0.end.timeIntervalSince($0.start) / 2)) }.map { interval in
            LedgerInterval(
                start: interval.start, end: interval.end, cores: interval.cores, coversNetwork: interval.coversNetwork,
                coversEnergy: interval.coversEnergy,
                entries: interval.entries.map {
                    LedgerEntry(app: names[$0.app], cpuSeconds: $0.cpuSeconds, diskBytes: $0.diskBytes,
                                networkBytes: $0.networkBytes, energyJoules: $0.energyJoules, isLowerBound: $0.isLowerBound)
                }
            )
        }
    }
}

/// What the window says about an open recording.
public struct OpenRecording: Equatable, Sendable {
    public let name: String
    public let start: Date
    public let end: Date
    public let appNames: ExportNaming
}
