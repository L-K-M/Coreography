import Foundation
import CoreographyDrivers

/// A persisted system series. Codes are stored on disk and never reused.
public enum HistoryMetric: Int, CaseIterable, Sendable {
    case cpu = 1
    case memoryUsed = 2
    case memoryApp = 3
    case memoryWired = 4
    case memoryCompressed = 5
    case memoryCached = 6
    case memoryPressure = 7
    case swapUsed = 8
    case thermalPressure = 9
    case gpuBusy = 10
    case batteryCharge = 11
    case systemPower = 12
    case hottestCelsius = 13
    case networkReceived = 14
    case networkSent = 15
    case diskRead = 16
    case diskWritten = 17
}

/// One stored reading. A missing value keeps its availability, so a gap
/// on disk stays a gap when replayed.
public struct HistorySample: Equatable, Sendable {
    public let metric: HistoryMetric
    public let time: Date
    public let value: Double?
    public let availability: MetricAvailability

    public init(metric: HistoryMetric, time: Date, value: Double?, availability: MetricAvailability) {
        self.metric = metric
        self.time = time
        self.value = value
        self.availability = availability
    }
}

public enum HistoryStoreError: Error, Equatable, Sendable {
    case storage(String)
}

/// The on-disk Recent tier (plan: six hours at 1 s, SQLite in WAL mode,
/// a per-user 0700 directory with 0600 files, excluded from backups,
/// hard time and size caps, crash-safe retention).
///
/// ```text
/// samples(metric, t, value, availability)  primary key (metric, t)
/// ```
public actor HistoryStore {
    public static let retention: TimeInterval = 6 * 3600
    /// Hard size cap; the oldest rows go first when it is exceeded.
    public static let maximumBytes: Int64 = 256 * 1024 * 1024
    private static let schemaVersion = 1
    private static let fileName = "history.sqlite"
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600
    // Stable on-disk codes for availability.
    private static let availabilityCodes: [MetricAvailability: Int64] = [
        .measured: 0, .estimated: 1, .collecting: 2, .unavailable: 3, .restricted: 4, .unsupported: 5, .gap: 6
    ]

    public let fileURL: URL
    private let connection: SQLiteConnection

    /// The default location: Application Support, owned by this user.
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coreography/History", isDirectory: true)
    }

    public init(directory: URL = HistoryStore.defaultDirectory) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: Self.directoryPermissions]
            )
            try FileManager.default.setAttributes([.posixPermissions: Self.directoryPermissions], ofItemAtPath: directory.path)
            fileURL = directory.appendingPathComponent(Self.fileName)
            connection = try SQLiteConnection(path: fileURL.path)
            try connection.execute("PRAGMA journal_mode=WAL")
            try connection.execute("PRAGMA synchronous=NORMAL")
            try connection.execute("""
                CREATE TABLE IF NOT EXISTS samples(
                    metric INTEGER NOT NULL, t REAL NOT NULL, value REAL, availability INTEGER NOT NULL,
                    PRIMARY KEY(metric, t)
                ) WITHOUT ROWID
                """)
            try connection.execute("PRAGMA user_version=\(Self.schemaVersion)")
            for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: fileURL.path + suffix) {
                try FileManager.default.setAttributes([.posixPermissions: Self.filePermissions], ofItemAtPath: fileURL.path + suffix)
            }
            Self.excludeFromBackups(directory)
        } catch let error as SQLiteError {
            throw HistoryStoreError.storage(error.message)
        } catch {
            throw HistoryStoreError.storage("\(error)")
        }
    }

    /// Write a batch in one transaction, then enforce the time and size caps.
    /// A repeated (metric, time) replaces the earlier reading.
    public func append(_ samples: [HistorySample], now: Date = Date()) throws {
        guard !samples.isEmpty else { return }
        try storage {
            try connection.transaction {
                try connection.run(
                    "INSERT OR REPLACE INTO samples(metric, t, value, availability) VALUES (?, ?, ?, ?)",
                    rows: samples.map { sample in
                        [
                            .integer(Int64(sample.metric.rawValue)), .real(sample.time.timeIntervalSince1970),
                            sample.value.map(SQLiteValue.real) ?? .null,
                            .integer(Self.availabilityCodes[sample.availability] ?? Self.availabilityCodes[.unavailable]!)
                        ]
                    }
                )
                try prune(before: now.addingTimeInterval(-Self.retention))
                try enforceSizeCap()
            }
        }
    }

    public func samples(_ metric: HistoryMetric, from start: Date, to end: Date) throws -> [HistorySample] {
        try storage {
            try connection.query(
                "SELECT t, value, availability FROM samples WHERE metric = ? AND t BETWEEN ? AND ? ORDER BY t",
                [.integer(Int64(metric.rawValue)), .real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
            ).compactMap { row in
                guard case .real(let time) = row[0], case .integer(let code) = row[2],
                      let availability = Self.availabilityCodes.first(where: { $0.value == code })?.key else { return nil }
                let value: Double? = if case .real(let number) = row[1] { number } else { nil }
                return HistorySample(
                    metric: metric, time: Date(timeIntervalSince1970: time), value: value, availability: availability
                )
            }
        }
    }

    public func sampleCount() throws -> Int {
        try storage {
            guard case .integer(let count)? = try connection.query("SELECT COUNT(*) FROM samples").first?.first else { return 0 }
            return Int(count)
        }
    }

    /// One-click deletion (plan: retention and deletion).
    public func deleteAll() throws {
        try storage { try connection.transaction { try connection.execute("DELETE FROM samples") } }
    }

    private func prune(before cutoff: Date) throws {
        try connection.run("DELETE FROM samples WHERE t < ?", rows: [[.real(cutoff.timeIntervalSince1970)]])
    }

    /// Drop the oldest tenth of rows while the database exceeds its cap.
    private func enforceSizeCap() throws {
        func bytes() throws -> Int64 {
            let pages = try connection.query("PRAGMA page_count").first?.first
            let size = try connection.query("PRAGMA page_size").first?.first
            guard case .integer(let count)? = pages, case .integer(let pageSize)? = size else { return 0 }
            return count * pageSize
        }
        guard try bytes() > Self.maximumBytes else { return }
        try connection.execute("""
            DELETE FROM samples WHERE t < (SELECT t FROM samples ORDER BY t
            LIMIT 1 OFFSET (SELECT COUNT(*) / 10 FROM samples))
            """)
    }

    private func storage<Value>(_ body: () throws -> Value) throws -> Value {
        do { return try body() } catch let error as SQLiteError { throw HistoryStoreError.storage(error.message) }
    }

    /// Backup exclusion is not protection, and the UI does not claim otherwise.
    private static func excludeFromBackups(_ directory: URL) {
        #if os(macOS)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        #endif
    }
}
