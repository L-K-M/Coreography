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

/// One app's activity over one process interval.
public struct LedgerEntry: Equatable, Sendable {
    public let app: String
    public let cpuSeconds: Double
    public let diskBytes: Double
    /// Some member was unreadable, so the figures are lower bounds.
    public let isLowerBound: Bool

    public init(app: String, cpuSeconds: Double, diskBytes: Double, isLowerBound: Bool) {
        self.app = app
        self.cpuSeconds = cpuSeconds
        self.diskBytes = diskBytes
        self.isLowerBound = isLowerBound
    }
}

/// One process interval of the observed-app ledger. An interval without
/// entries was observed idle, which differs from not being observed.
public struct LedgerInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date
    /// Logical CPUs when recorded; 0 when unknown.
    public let cores: Double
    public let entries: [LedgerEntry]

    public init(start: Date, end: Date, cores: Double, entries: [LedgerEntry]) {
        self.start = start
        self.end = end
        self.cores = cores
        self.entries = entries
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
/// samples(metric, t, value, availability)                   primary key (metric, t)
/// ledger_intervals(t_end, t_start, cores)                    primary key t_end
/// ledger_entries(t_end, app, cpu_seconds, disk_bytes, lower_bound)  primary key (t_end, app)
/// apps(id, name)                                             names interned, swept hourly
/// ```
public actor HistoryStore {
    public static let retention: TimeInterval = 6 * 3600
    /// Hard size cap; the oldest rows go first when it is exceeded.
    public static let maximumBytes: Int64 = 256 * 1024 * 1024
    private static let schemaVersion = 2
    /// App names outlive their last interval by at most this long.
    private static let nameSweepInterval: TimeInterval = 3600
    private static let fileName = "history.sqlite"
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600
    // Stable on-disk codes for availability.
    private static let availabilityCodes: [MetricAvailability: Int64] = [
        .measured: 0, .estimated: 1, .collecting: 2, .unavailable: 3, .restricted: 4, .unsupported: 5, .gap: 6
    ]

    public let fileURL: URL
    private let connection: SQLiteConnection
    private let maximumBytes: Int64
    private var appIDs: [String: Int64] = [:]
    private var lastNameSweep: Date?

    /// The default location: Application Support, owned by this user.
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coreography/History", isDirectory: true)
    }

    public init(directory: URL = HistoryStore.defaultDirectory) throws {
        try self.init(directory: directory, maximumBytes: Self.maximumBytes)
    }

    init(directory: URL, maximumBytes: Int64) throws {
        self.maximumBytes = maximumBytes
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
                ) WITHOUT ROWID;
                CREATE TABLE IF NOT EXISTS apps(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE);
                CREATE TABLE IF NOT EXISTS ledger_intervals(
                    t_end REAL PRIMARY KEY, t_start REAL NOT NULL, cores REAL NOT NULL
                ) WITHOUT ROWID;
                CREATE TABLE IF NOT EXISTS ledger_entries(
                    t_end REAL NOT NULL, app INTEGER NOT NULL, cpu_seconds REAL NOT NULL,
                    disk_bytes REAL NOT NULL, lower_bound INTEGER NOT NULL,
                    PRIMARY KEY(t_end, app)
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
    /// A repeated (metric, time) or ledger interval end replaces the earlier one.
    public func append(_ samples: [HistorySample], ledger: [LedgerInterval] = [], now: Date = Date()) throws {
        guard !samples.isEmpty || !ledger.isEmpty else { return }
        do {
            try storage { try write(samples, ledger: ledger, now: now) }
        } catch {
            // Interned ids and a name sweep from a rolled-back batch never happened.
            appIDs.removeAll()
            lastNameSweep = nil
            throw error
        }
    }

    private func write(_ samples: [HistorySample], ledger: [LedgerInterval], now: Date) throws {
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
            try insert(ledger)
            try prune(before: now.addingTimeInterval(-Self.retention))
            try enforceSizeCap()
            try sweepNames(now: now)
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

    /// Ledger intervals ending in the window, oldest first, entries by app name.
    public func ledger(from start: Date, to end: Date) throws -> [LedgerInterval] {
        try storage {
            let window: [SQLiteValue] = [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
            let entryRows = try connection.query("""
                SELECT e.t_end, a.name, e.cpu_seconds, e.disk_bytes, e.lower_bound
                FROM ledger_entries e JOIN apps a ON a.id = e.app
                WHERE e.t_end BETWEEN ? AND ? ORDER BY e.t_end, a.name
                """, window)
            var entries: [Double: [LedgerEntry]] = [:]
            for row in entryRows {
                guard case .real(let end) = row[0], case .text(let app) = row[1], case .real(let cpu) = row[2],
                      case .real(let disk) = row[3], case .integer(let lowerBound) = row[4] else { continue }
                entries[end, default: []].append(
                    LedgerEntry(app: app, cpuSeconds: cpu, diskBytes: disk, isLowerBound: lowerBound != 0)
                )
            }

            return try connection.query(
                "SELECT t_end, t_start, cores FROM ledger_intervals WHERE t_end BETWEEN ? AND ? ORDER BY t_end", window
            ).compactMap { row in
                guard case .real(let end) = row[0], case .real(let start) = row[1], case .real(let cores) = row[2] else {
                    return nil
                }
                return LedgerInterval(
                    start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end),
                    cores: cores, entries: entries[end] ?? []
                )
            }
        }
    }

    /// One-click deletion (plan: retention and deletion).
    public func deleteAll() throws {
        try storage {
            try connection.transaction {
                for table in ["samples", "ledger_entries", "ledger_intervals", "apps"] {
                    try connection.execute("DELETE FROM \(table)")
                }
            }
        }
        appIDs.removeAll()
    }

    /// A replaced interval drops its earlier entries, so an app idle in the
    /// new version does not keep the old figures.
    private func insert(_ ledger: [LedgerInterval]) throws {
        guard !ledger.isEmpty else { return }
        let ends = ledger.map { [SQLiteValue.real($0.end.timeIntervalSince1970)] }
        try connection.run(
            "INSERT OR REPLACE INTO ledger_intervals(t_end, t_start, cores) VALUES (?, ?, ?)",
            rows: ledger.map { [.real($0.end.timeIntervalSince1970), .real($0.start.timeIntervalSince1970), .real($0.cores)] }
        )
        try connection.run("DELETE FROM ledger_entries WHERE t_end = ?", rows: ends)

        var rows: [[SQLiteValue]] = []
        for interval in ledger {
            for entry in interval.entries {
                rows.append([
                    .real(interval.end.timeIntervalSince1970), .integer(try appID(entry.app)),
                    .real(entry.cpuSeconds), .real(entry.diskBytes), .integer(entry.isLowerBound ? 1 : 0)
                ])
            }
        }
        try connection.run(
            "INSERT OR REPLACE INTO ledger_entries(t_end, app, cpu_seconds, disk_bytes, lower_bound) VALUES (?, ?, ?, ?, ?)",
            rows: rows
        )
    }

    /// Interned names still on disk.
    func storedAppNames() throws -> [String] {
        try storage {
            try connection.query("SELECT name FROM apps ORDER BY name").compactMap {
                guard case .text(let name)? = $0.first else { return nil }
                return name
            }
        }
    }

    private func appID(_ name: String) throws -> Int64 {
        if let cached = appIDs[name] { return cached }
        try connection.run("INSERT OR IGNORE INTO apps(name) VALUES (?)", rows: [[.text(name)]])
        guard case .integer(let id)? = try connection.query("SELECT id FROM apps WHERE name = ?", [.text(name)]).first?.first else {
            throw HistoryStoreError.storage("Could not intern an app name")
        }
        appIDs[name] = id
        return id
    }

    /// Names whose every interval has aged out leave too, so the store holds
    /// no identifier longer than its retention plus the sweep interval.
    private func sweepNames(now: Date) throws {
        if let lastNameSweep, now.timeIntervalSince(lastNameSweep) < Self.nameSweepInterval { return }
        try connection.execute("DELETE FROM apps WHERE id NOT IN (SELECT app FROM ledger_entries)")
        lastNameSweep = now
        appIDs.removeAll()
    }

    private func prune(before cutoff: Date) throws {
        let time: [[SQLiteValue]] = [[.real(cutoff.timeIntervalSince1970)]]
        try connection.run("DELETE FROM samples WHERE t < ?", rows: time)
        try connection.run("DELETE FROM ledger_intervals WHERE t_end < ?", rows: time)
        try connection.run("DELETE FROM ledger_entries WHERE t_end < ?", rows: time)
    }

    /// Over the cap, drop the oldest tenth of history until live data fits
    /// in nine tenths of it, so pruning runs rarely rather than on every
    /// batch. Freed pages are reused space, not history, so they don't count.
    private func enforceSizeCap() throws {
        guard try liveBytes() > maximumBytes else { return }
        let target = maximumBytes / 10 * 9
        while try liveBytes() > target {
            guard let cutoff = try oldestTenthCutoff() else { return }
            let before = try totalChanges()
            try prune(before: cutoff)
            // Too few rows to split into tenths: stop rather than spin.
            guard try totalChanges() > before else { return }
        }
    }

    private func liveBytes() throws -> Int64 {
        try (pragma("page_count") - pragma("freelist_count")) * pragma("page_size")
    }

    private func pragma(_ name: String) throws -> Int64 {
        guard case .integer(let value)? = try connection.query("PRAGMA \(name)").first?.first else { return 0 }
        return value
    }

    private func totalChanges() throws -> Int64 {
        guard case .integer(let value)? = try connection.query("SELECT total_changes()").first?.first else { return 0 }
        return value
    }

    /// The time before which the oldest tenth of stored rows lies, samples
    /// and ledger intervals together, so either alone stays under the cap.
    private func oldestTenthCutoff() throws -> Date? {
        let rows = try connection.query("""
            SELECT time FROM (SELECT t AS time FROM samples UNION ALL SELECT t_end AS time FROM ledger_intervals)
            ORDER BY time LIMIT 1 OFFSET (
                (SELECT COUNT(*) FROM samples) + (SELECT COUNT(*) FROM ledger_intervals)
            ) / 10
            """)
        guard case .real(let time)? = rows.first?.first else { return nil }
        return Date(timeIntervalSince1970: time)
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
