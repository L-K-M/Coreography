import Foundation
import CoreographyKit

/// The unit a session metric is recorded in.
public enum SessionUnit: String, Codable, Sendable {
    case percentOfMachine = "% of machine"
    case percent = "%"
    case bytes
    case bytesPerSecond = "bytes/s"
    case watts = "W"
    case celsius = "°C"
}

/// One metric over a recorded session (plan P19: minimum, maximum and
/// average, and a 95th percentile only from retained raw samples).
public struct SessionMetricSummary: Codable, Identifiable, Sendable {
    public var id: String { metric }
    public let metric: String
    public let unit: SessionUnit
    public let minimum: Double
    public let maximum: Double
    public let mean: Double
    /// Nearest-rank 95th percentile of every raw reading.
    public let percentile95: Double
    public let samples: Int
}

/// One reading of a session, by seconds from its start, for overlays.
public struct SessionPoint: Codable, Sendable {
    public let offset: TimeInterval
    public let value: Double
}

/// A frozen, named recording: its report and its raw series.
public struct RecordedSession: Codable, Identifiable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let name: String
    public let start: Date
    public let end: Date
    public let summaries: [SessionMetricSummary]
    /// Apps by CPU-seconds over the whole session, from every ledger interval recorded.
    public let topApps: [AppRangeTotal]
    /// Raw readings per metric, for comparing sessions side by side.
    public let series: [String: [SessionPoint]]
}

/// A session being recorded: every tick's readings and ledger intervals,
/// kept apart from the live hour so a long session loses nothing.
struct SessionRecording: Sendable {
    /// Series a session records, with their units.
    static let metrics: [(HistoryMetric, SessionUnit)] = [
        (.cpu, .percentOfMachine), (.memoryUsed, .bytes), (.gpuBusy, .percent), (.systemPower, .watts),
        (.hottestCelsius, .celsius), (.networkReceived, .bytesPerSecond), (.networkSent, .bytesPerSecond),
        (.diskRead, .bytesPerSecond), (.diskWritten, .bytesPerSecond)
    ]
    static let topAppLimit = 10

    let id = UUID()
    let name: String
    let start: Date
    private var values: [HistoryMetric: [SessionPoint]] = [:]
    private var ledger: [LedgerInterval] = []

    init(name: String, start: Date) {
        self.name = name
        self.start = start
    }

    /// Readings without values are skipped: a gap is not a zero.
    mutating func record(_ samples: [HistorySample]) {
        for sample in samples {
            guard let value = sample.value, Self.metrics.contains(where: { $0.0 == sample.metric }) else { continue }
            values[sample.metric, default: []].append(SessionPoint(offset: sample.time.timeIntervalSince(start), value: value))
        }
    }

    mutating func record(_ interval: LedgerInterval) { ledger.append(interval) }

    func finish(at end: Date) -> RecordedSession {
        let summaries = Self.metrics.compactMap { metric, unit in
            Self.summary(values[metric] ?? [], metric: "\(metric)", unit: unit)
        }
        let apps = AppLedger(stored: ledger).totals(in: start...max(start, end)).apps
            .sorted { $0.cpuSeconds > $1.cpuSeconds }
        return RecordedSession(
            schemaVersion: RecordedSession.schemaVersion, id: id, name: name, start: start, end: end,
            summaries: summaries, topApps: Array(apps.prefix(Self.topAppLimit)),
            series: Dictionary(uniqueKeysWithValues: values.map { ("\($0.key)", $0.value) })
        )
    }

    static func summary(_ points: [SessionPoint], metric: String, unit: SessionUnit) -> SessionMetricSummary? {
        guard !points.isEmpty else { return nil }
        let sorted = points.map(\.value).sorted()
        let rank = Int((0.95 * Double(sorted.count)).rounded(.up)) - 1
        return SessionMetricSummary(
            metric: metric, unit: unit, minimum: sorted[0], maximum: sorted[sorted.count - 1],
            mean: sorted.reduce(0, +) / Double(sorted.count), percentile95: sorted[max(rank, 0)], samples: sorted.count
        )
    }
}

/// Saves and reads sessions through the Kit store; the document is JSON.
struct SessionArchive: Sendable {
    private let store: SessionStore

    init(store: SessionStore) { self.store = store }

    static func makeDefault() -> SessionArchive? {
        (try? SessionStore()).map(SessionArchive.init)
    }

    func save(_ session: RecordedSession) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try await store.save(try encoder.encode(session), id: session.id)
    }

    /// Newest first; unreadable documents are skipped.
    func all() async -> [RecordedSession] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var sessions: [RecordedSession] = []
        for id in await store.list() {
            guard let data = try? await store.load(id),
                  let session = try? decoder.decode(RecordedSession.self, from: data) else { continue }
            sessions.append(session)
        }
        return sessions.sorted { $0.start > $1.start }
    }

    func delete(_ id: UUID) async throws { try await store.delete(id) }
}
