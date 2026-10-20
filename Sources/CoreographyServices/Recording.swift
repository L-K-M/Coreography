import Foundation
import CoreographyKit

/// A frozen copy of a time range (plan: recordings, saved as a portable
/// `.coreotrace` package that opens in Coreography for scrubbing, replay
/// and comparison). It is JSON with a documented schema:
///
/// ```text
/// schemaVersion  2
/// name, start, end, appNames ("redacted" or "named"), savedAt
/// host, network, disks, gpu, power, sensors   frames as the window holds them
/// ledger         per-app intervals, so range reports work in replay
/// markers        time and label of every marker in the range
/// stored         when the range reaches before the first live frame: the
///                tier read, every metric's raw stored series keyed by the
///                metric's on-disk code, and the stored ledger intervals
/// ```
/// Redacted recordings number apps in CPU order, the same name for the same
/// app throughout, so replayed reports still rank correctly.
/// Version 2 added `stored`; version 1 files carry the live part only.
public enum Recording {
    public static let schemaVersion = 2
    public static let fileExtension = "coreotrace"
    /// A recording holds live data plus its stored part; anything this large is not one.
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
        /// The stored part of a range reaching before the first live frame;
        /// absent in version 1 recordings and in ranges inside live data.
        let stored: Stored?
    }

    /// What the stored tiers said about the part of the range before live
    /// history: every metric's raw stored series, so replay rebuilds the
    /// same `StoredHistory` a live load reduced.
    struct Stored: Codable, Equatable, Sendable {
        /// Which stored tier the series came from, so replay weights buckets
        /// right. Under `recent` an entry is a reading (`time`, `value`
        /// absent for a gap); under `day` or `month` a bucket (`time`,
        /// `minimum`, `maximum`, `mean`, `count`).
        let tier: StoredTier
        /// Every stored metric's raw series, keyed by its on-disk code.
        let series: [String: [StoredPoint]]
        /// The stored app ledger over the earlier part.
        let ledger: [Interval]
    }

    public enum Failure: Error, Equatable, Sendable {
        case tooLarge
        case unreadable(String)
        /// The document could not be serialized; the detail is the encoder's.
        case uncodable(String)
        case newerSchema(Int)
        case invalidRange
        /// The part of the range before live data has no stored history; the
        /// reason says why (not recorded, still loading or kept less far back).
        case missingHistory(String)

        public var message: String {
            switch self {
            case .tooLarge: "The file is larger than any recording"
            case .unreadable(let detail): "The recording could not be read: \(detail)"
            case .uncodable(let detail): "The recording could not be written: \(detail)"
            case .newerSchema(let version): "The recording uses a newer format (\(version)); update Coreography"
            case .invalidRange: "The recording's time range is invalid"
            case .missingHistory(let reason): reason
            }
        }
    }

    static func make(
        name: String, range: ClosedRange<Date>, frames: DashboardFrames, ledger: AppLedger,
        stored: StoredHistory.RawData? = nil, markers: [TimelineMarker], naming: ExportNaming, now: Date = Date()
    ) -> Document {
        func inRange<Frame>(_ frames: [Frame], _ time: (Frame) -> Date) -> [Frame] {
            frames.filter { range.contains(time($0)) }
        }
        let intervals = ledger.storedIntervals(in: range)
        // Replay totals the stored ledger up to the first live interval, the
        // same bound reports use, so the saved intervals end there too.
        let storedBound = intervals.first?.start ?? .distantFuture
        let storedIntervals = (stored?.ledger ?? []).filter { interval in
            let middle = interval.start.addingTimeInterval(interval.end.timeIntervalSince(interval.start) / 2)
            return range.contains(middle) && interval.end <= storedBound
        }
        // One ranking covers both parts, so an app keeps its placeholder across the seam.
        let rename = naming == .named ? [:] : placeholders(intervals + storedIntervals)
        func renamed(_ interval: LedgerInterval) -> Interval {
            Interval(
                start: interval.start, end: interval.end, cores: interval.cores, coversNetwork: interval.coversNetwork,
                coversEnergy: interval.coversEnergy,
                entries: interval.entries.map {
                    Entry(app: rename[$0.app] ?? $0.app, cpuSeconds: $0.cpuSeconds, diskBytes: $0.diskBytes,
                          networkBytes: $0.networkBytes, energyJoules: $0.energyJoules, isLowerBound: $0.isLowerBound)
                }
            )
        }
        // Each stored series ends where its own live lane begins, as lanes
        // and reports cut them; a family without frames keeps its series whole.
        func liveBoundary(_ metric: HistoryMetric) -> Date {
            switch metric {
            case .gpuBusy: frames.gpu.first?.stamp.wallTime ?? .distantFuture
            case .hottestCelsius: frames.sensors.first?.stamp.wallTime ?? .distantFuture
            case .networkReceived, .networkSent: frames.network.first?.stamp.wallTime ?? .distantFuture
            case .diskRead, .diskWritten: frames.disks.first?.stamp.wallTime ?? .distantFuture
            case .batteryCharge: frames.power.first?.stamp.wallTime ?? .distantFuture
            default: frames.host.first?.stamp.wallTime ?? .distantFuture
            }
        }
        // A range inside live data yields an empty section and stays unwritten.
        let section = stored.flatMap { raw -> Stored? in
            let stored = Stored(
                tier: raw.tier,
                series: Dictionary(uniqueKeysWithValues: raw.series.compactMap { metric, _ in
                    let points = raw.points(metric, in: range, before: liveBoundary(metric))
                    return points.isEmpty ? nil : (metric.recordingKey, points)
                }),
                ledger: storedIntervals.map(renamed)
            )
            return stored.series.isEmpty && stored.ledger.isEmpty ? nil : stored
        }
        return Document(
            schemaVersion: schemaVersion, name: name, savedAt: now, start: range.lowerBound, end: range.upperBound,
            appNames: naming,
            host: inRange(frames.host) { $0.stamp.wallTime }, network: inRange(frames.network) { $0.stamp.wallTime },
            disks: inRange(frames.disks) { $0.stamp.wallTime }, gpu: inRange(frames.gpu) { $0.stamp.wallTime },
            power: inRange(frames.power) { $0.stamp.wallTime }, sensors: inRange(frames.sensors) { $0.stamp.wallTime },
            ledger: intervals.map(renamed),
            // A person's marker names can identify work; a redacted recording keeps their times only.
            markers: markers.filter { range.contains($0.time) }.map {
                Marker(time: $0.time, label: naming == .named || $0.kind != .note ? $0.label : "Marker", kind: $0.kind)
            },
            stored: section
        )
    }

    public static func encode(_ document: Document) throws(Failure) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw .uncodable("\(error)")
        }
        // A stored part can push a long range past the cap; refuse rather than trim.
        guard data.count <= maximumBytes else { throw .tooLarge }
        return data
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

extension HistoryMetric {
    /// The recording key: the on-disk code as text, so a renamed case or a
    /// reordered enum never orphans a saved file.
    var recordingKey: String { String(rawValue) }

    init?(recordingKey: String) {
        guard let code = Int(recordingKey) else { return nil }
        self.init(rawValue: code)
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
