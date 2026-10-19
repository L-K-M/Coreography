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
    /// TCP and UDP bytes in and out; 0 in an interval without network coverage.
    public let networkBytes: Double
    /// Some member was unreadable, so the CPU and disk figures are lower bounds.
    public let isLowerBound: Bool

    public init(app: String, cpuSeconds: Double, diskBytes: Double, networkBytes: Double = 0, isLowerBound: Bool) {
        self.app = app
        self.cpuSeconds = cpuSeconds
        self.diskBytes = diskBytes
        self.networkBytes = networkBytes
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
    /// Per-process network was read for this interval, so absent apps moved nothing.
    public let coversNetwork: Bool
    public let entries: [LedgerEntry]

    public init(start: Date, end: Date, cores: Double, coversNetwork: Bool = false, entries: [LedgerEntry]) {
        self.start = start
        self.end = end
        self.cores = cores
        self.coversNetwork = coversNetwork
        self.entries = entries
    }
}

/// One metric over one Day- or Month-tier bucket. Only readings with
/// values count, so a bucket with none is absent: a gap, not a zero.
public struct HistoryRollup: Equatable, Sendable {
    public let metric: HistoryMetric
    /// The bucket's start.
    public let time: Date
    public let minimum: Double
    public let maximum: Double
    public let mean: Double
    public let count: Int

    public init(metric: HistoryMetric, time: Date, minimum: Double, maximum: Double, mean: Double, count: Int) {
        self.metric = metric
        self.time = time
        self.minimum = minimum
        self.maximum = maximum
        self.mean = mean
        self.count = count
    }
}

/// One app's totals over one local calendar day, from the ledger
/// (plan: Month tier, per-app daily totals). Energy and network join when
/// per-app sources for them exist.
public struct AppDayTotal: Equatable, Sendable {
    /// Local midnight starting the day.
    public let day: Date
    public let app: String
    public let cpuSeconds: Double
    public let diskBytes: Double
    /// Bytes in and out over the day's network-covered intervals.
    public let networkBytes: Double
    /// Some interval counted only readable members.
    public let isLowerBound: Bool

    public init(day: Date, app: String, cpuSeconds: Double, diskBytes: Double, networkBytes: Double = 0, isLowerBound: Bool) {
        self.day = day
        self.app = app
        self.cpuSeconds = cpuSeconds
        self.diskBytes = diskBytes
        self.networkBytes = networkBytes
        self.isLowerBound = isLowerBound
    }
}

/// Which rollup tier a query reads.
public enum RollupTier: Sendable {
    /// 10 s buckets.
    case day
    /// 1 min buckets.
    case month

    var table: String { self == .day ? "day_samples" : "month_samples" }
    public var bucket: TimeInterval { self == .day ? HistoryStore.dayBucket : HistoryStore.monthBucket }
}

/// How long each tier keeps its data.
public struct RetentionPlan: Equatable, Sendable {
    /// 1 s readings and the app ledger.
    public let recent: TimeInterval
    /// 10 s buckets.
    public let day: TimeInterval
    /// 1 min buckets and per-app daily totals.
    public let month: TimeInterval

    public init(recent: TimeInterval, day: TimeInterval, month: TimeInterval = HistoryStore.monthRetention) {
        self.recent = recent
        self.day = day
        self.month = month
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
/// ledger_intervals(t_end, t_start, cores, network)           primary key t_end
/// ledger_entries(t_end, app, cpu_seconds, disk_bytes, lower_bound, network_bytes)  primary key (t_end, app)
/// apps(id, name)                                             names interned, swept hourly
/// day_samples(metric, t, minimum, maximum, total, count)     10 s buckets, 7 days
/// month_samples(metric, t, minimum, maximum, total, count)   1 min buckets, 30 days
/// app_days(day, app, cpu_seconds, disk_bytes, lower_bound, network_bytes)  per app and local day, 30 days
/// ```
public actor HistoryStore {
    /// The plan's defaults: six hours at 1 s, and the Day tier (10 s,
    /// keeping minimum, maximum and mean) for 7 days.
    public static let retention: TimeInterval = 6 * 3600
    public static let dayRetention: TimeInterval = 7 * 86_400
    public static let dayBucket: TimeInterval = 10
    public static let monthRetention: TimeInterval = 30 * 86_400
    public static let monthBucket: TimeInterval = 60
    /// Hard size cap; the oldest rows go first when it is exceeded.
    public static let maximumBytes: Int64 = 256 * 1024 * 1024
    static let schemaVersion = 5
    /// Columns added after their tables shipped: (table, column, definition).
    private static let addedColumns = [
        ("ledger_intervals", "network", "INTEGER NOT NULL DEFAULT 0"),
        ("ledger_entries", "network_bytes", "REAL NOT NULL DEFAULT 0"),
        ("app_days", "network_bytes", "REAL NOT NULL DEFAULT 0")
    ]
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
    private var plan = RetentionPlan(recent: HistoryStore.retention, day: HistoryStore.dayRetention)
    /// Days are local calendar days; tests fix the time zone.
    private let calendar: Calendar
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

    init(directory: URL, maximumBytes: Int64, calendar: Calendar = .current) throws {
        self.maximumBytes = maximumBytes
        self.calendar = calendar
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: Self.directoryPermissions]
            )
            try FileManager.default.setAttributes([.posixPermissions: Self.directoryPermissions], ofItemAtPath: directory.path)
            fileURL = directory.appendingPathComponent(Self.fileName)
            connection = try SQLiteConnection(path: fileURL.path)
            // A newer build's store keeps its label and rows; this build cannot read its schema.
            let version = try Self.userVersion(connection)
            guard version <= Self.schemaVersion else {
                throw HistoryStoreError.storage(
                    "History was written by a newer Coreography (schema \(version)); update Coreography to keep recording"
                )
            }
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
                ) WITHOUT ROWID;
                CREATE TABLE IF NOT EXISTS day_samples(
                    metric INTEGER NOT NULL, t REAL NOT NULL, minimum REAL NOT NULL, maximum REAL NOT NULL,
                    total REAL NOT NULL, count INTEGER NOT NULL,
                    PRIMARY KEY(metric, t)
                ) WITHOUT ROWID;
                CREATE TABLE IF NOT EXISTS month_samples(
                    metric INTEGER NOT NULL, t REAL NOT NULL, minimum REAL NOT NULL, maximum REAL NOT NULL,
                    total REAL NOT NULL, count INTEGER NOT NULL,
                    PRIMARY KEY(metric, t)
                ) WITHOUT ROWID;
                CREATE TABLE IF NOT EXISTS app_days(
                    day REAL NOT NULL, app INTEGER NOT NULL, cpu_seconds REAL NOT NULL,
                    disk_bytes REAL NOT NULL, lower_bound INTEGER NOT NULL,
                    PRIMARY KEY(day, app)
                ) WITHOUT ROWID
                """)
            try Self.addMissingColumns(connection)
            if version != Self.schemaVersion { try connection.execute("PRAGMA user_version=\(Self.schemaVersion)") }
            for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: fileURL.path + suffix) {
                try FileManager.default.setAttributes([.posixPermissions: Self.filePermissions], ofItemAtPath: fileURL.path + suffix)
            }
            Self.excludeFromBackups(directory)
        } catch let error as SQLiteError {
            throw HistoryStoreError.storage(error.message)
        } catch let error as HistoryStoreError {
            throw error
        } catch {
            throw HistoryStoreError.storage("\(error)")
        }
    }

    /// Older stores gain new columns in place; their earlier rows read the defaults.
    private static func addMissingColumns(_ connection: SQLiteConnection) throws {
        for (table, column, definition) in addedColumns {
            let existing = try connection.query("PRAGMA table_info(\(table))").compactMap { row -> String? in
                guard row.count > 1, case .text(let name) = row[1] else { return nil }
                return name
            }
            guard !existing.contains(column) else { continue }
            try connection.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
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
            try rollUp(samples, into: .day)
            try rollUp(samples, into: .month)
            try prune(before: now.addingTimeInterval(-plan.recent))
            try pruneDay(before: now.addingTimeInterval(-plan.day))
            try pruneMonth(before: now.addingTimeInterval(-plan.month))
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

    /// Takes effect with the next write, which prunes to the new plan.
    public func setRetention(_ plan: RetentionPlan) {
        self.plan = plan
    }

    /// Bytes the stored history occupies, freed pages excluded.
    public func size() throws -> Int64 {
        try storage { try liveBytes() }
    }

    /// Buckets of one tier starting in the window, oldest first.
    public func rollups(
        _ metric: HistoryMetric, tier: RollupTier = .day, from start: Date, to end: Date
    ) throws -> [HistoryRollup] {
        try storage {
            try connection.query(
                "SELECT t, minimum, maximum, total, count FROM \(tier.table) WHERE metric = ? AND t BETWEEN ? AND ? ORDER BY t",
                [.integer(Int64(metric.rawValue)), .real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
            ).compactMap { row in
                guard case .real(let time) = row[0], case .real(let minimum) = row[1], case .real(let maximum) = row[2],
                      case .real(let total) = row[3], case .integer(let count) = row[4], count > 0 else { return nil }
                return HistoryRollup(
                    metric: metric, time: Date(timeIntervalSince1970: time), minimum: minimum, maximum: maximum,
                    mean: total / Double(count), count: Int(count)
                )
            }
        }
    }

    /// Per-app totals for the local days starting in the window, oldest day first.
    public func appDays(from start: Date, to end: Date) throws -> [AppDayTotal] {
        try storage {
            try connection.query("""
                SELECT d.day, a.name, d.cpu_seconds, d.disk_bytes, d.lower_bound, d.network_bytes
                FROM app_days d JOIN apps a ON a.id = d.app
                WHERE d.day BETWEEN ? AND ? ORDER BY d.day, a.name
                """, [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]).compactMap { row in
                guard case .real(let day) = row[0], case .text(let app) = row[1], case .real(let cpu) = row[2],
                      case .real(let disk) = row[3], case .integer(let lowerBound) = row[4], case .real(let network) = row[5] else { return nil }
                return AppDayTotal(
                    day: Date(timeIntervalSince1970: day), app: app, cpuSeconds: cpu, diskBytes: disk,
                    networkBytes: network, isLowerBound: lowerBound != 0
                )
            }
        }
    }

    /// Ledger intervals ending in the window, oldest first, entries by app name.
    public func ledger(from start: Date, to end: Date) throws -> [LedgerInterval] {
        try storage {
            let window: [SQLiteValue] = [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
            let entryRows = try connection.query("""
                SELECT e.t_end, a.name, e.cpu_seconds, e.disk_bytes, e.lower_bound, e.network_bytes
                FROM ledger_entries e JOIN apps a ON a.id = e.app
                WHERE e.t_end BETWEEN ? AND ? ORDER BY e.t_end, a.name
                """, window)
            var entries: [Double: [LedgerEntry]] = [:]
            for row in entryRows {
                guard case .real(let end) = row[0], case .text(let app) = row[1], case .real(let cpu) = row[2],
                      case .real(let disk) = row[3], case .integer(let lowerBound) = row[4], case .real(let network) = row[5] else { continue }
                entries[end, default: []].append(
                    LedgerEntry(app: app, cpuSeconds: cpu, diskBytes: disk, networkBytes: network, isLowerBound: lowerBound != 0)
                )
            }

            return try connection.query(
                "SELECT t_end, t_start, cores, network FROM ledger_intervals WHERE t_end BETWEEN ? AND ? ORDER BY t_end", window
            ).compactMap { row in
                guard case .real(let end) = row[0], case .real(let start) = row[1], case .real(let cores) = row[2],
                      case .integer(let network) = row[3] else {
                    return nil
                }
                return LedgerInterval(
                    start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end),
                    cores: cores, coversNetwork: network != 0, entries: entries[end] ?? []
                )
            }
        }
    }

    /// One-click deletion (plan: retention and deletion).
    public func deleteAll() throws {
        try storage {
            try connection.transaction {
                for table in ["samples", "ledger_entries", "ledger_intervals", "app_days", "apps", "day_samples", "month_samples"] {
                    try connection.execute("DELETE FROM \(table)")
                }
            }
        }
        appIDs.removeAll()
    }

    /// Fold a batch into one tier's buckets, combining with what earlier
    /// batches put in the same bucket. Readings without values are left out.
    private func rollUp(_ samples: [HistorySample], into tier: RollupTier) throws {
        struct Key: Hashable { let metric: Int; let bucket: Double }
        var buckets: [Key: (minimum: Double, maximum: Double, total: Double, count: Int64)] = [:]
        for sample in samples {
            guard let value = sample.value else { continue }
            let bucket = (sample.time.timeIntervalSince1970 / tier.bucket).rounded(.down) * tier.bucket
            let key = Key(metric: sample.metric.rawValue, bucket: bucket)
            if let current = buckets[key] {
                buckets[key] = (min(current.minimum, value), max(current.maximum, value), current.total + value, current.count + 1)
            } else {
                buckets[key] = (value, value, value, 1)
            }
        }
        try connection.run("""
            INSERT INTO \(tier.table)(metric, t, minimum, maximum, total, count) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(metric, t) DO UPDATE SET
                minimum = min(minimum, excluded.minimum), maximum = max(maximum, excluded.maximum),
                total = total + excluded.total, count = count + excluded.count
            """, rows: buckets.map { key, value in
                [.integer(Int64(key.metric)), .real(key.bucket), .real(value.minimum), .real(value.maximum),
                 .real(value.total), .integer(value.count)]
            })
    }

    /// A replaced interval drops its earlier entries, so an app idle in the
    /// new version does not keep the old figures; its day totals lose them too.
    private func insert(_ ledger: [LedgerInterval]) throws {
        guard !ledger.isEmpty else { return }
        let ends = ledger.map { [SQLiteValue.real($0.end.timeIntervalSince1970)] }
        try removeFromDays(ends)
        try connection.run(
            "INSERT OR REPLACE INTO ledger_intervals(t_end, t_start, cores, network) VALUES (?, ?, ?, ?)",
            rows: ledger.map {
                [.real($0.end.timeIntervalSince1970), .real($0.start.timeIntervalSince1970), .real($0.cores),
                 .integer($0.coversNetwork ? 1 : 0)]
            }
        )
        try connection.run("DELETE FROM ledger_entries WHERE t_end = ?", rows: ends)

        var rows: [[SQLiteValue]] = []
        for interval in ledger {
            for entry in interval.entries {
                rows.append([
                    .real(interval.end.timeIntervalSince1970), .integer(try appID(entry.app)),
                    .real(entry.cpuSeconds), .real(entry.diskBytes), .integer(entry.isLowerBound ? 1 : 0),
                    .real(entry.networkBytes)
                ])
            }
        }
        try connection.run(
            "INSERT OR REPLACE INTO ledger_entries(t_end, app, cpu_seconds, disk_bytes, lower_bound, network_bytes) VALUES (?, ?, ?, ?, ?, ?)",
            rows: rows
        )
        try connection.run("""
            INSERT INTO app_days(day, app, cpu_seconds, disk_bytes, lower_bound, network_bytes) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(day, app) DO UPDATE SET
                cpu_seconds = cpu_seconds + excluded.cpu_seconds, disk_bytes = disk_bytes + excluded.disk_bytes,
                lower_bound = max(lower_bound, excluded.lower_bound), network_bytes = network_bytes + excluded.network_bytes
            """, rows: rows.map { row in
                guard case .real(let end) = row[0] else { return row }
                return [.real(day(of: end))] + row.dropFirst()
            })
    }

    /// Subtract intervals about to be replaced from their days.
    private func removeFromDays(_ ends: [[SQLiteValue]]) throws {
        for end in ends {
            guard case .real(let time)? = end.first else { continue }
            let old = try connection.query("SELECT app, cpu_seconds, disk_bytes, network_bytes FROM ledger_entries WHERE t_end = ?", end)
            try connection.run(
                "UPDATE app_days SET cpu_seconds = cpu_seconds - ?, disk_bytes = disk_bytes - ?, network_bytes = network_bytes - ? WHERE day = ? AND app = ?",
                rows: old.map { [$0[1], $0[2], $0[3], .real(day(of: time)), $0[0]] }
            )
        }
        // An app idle in the replacement keeps no empty row.
        try connection.execute("DELETE FROM app_days WHERE cpu_seconds <= 1e-9 AND disk_bytes <= 1e-9 AND network_bytes <= 1e-9")
    }

    /// Local midnight of the day containing `time`.
    private func day(of time: Double) -> Double {
        calendar.startOfDay(for: Date(timeIntervalSince1970: time)).timeIntervalSince1970
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
        try connection.execute(
            "DELETE FROM apps WHERE id NOT IN (SELECT app FROM ledger_entries) AND id NOT IN (SELECT app FROM app_days)"
        )
        lastNameSweep = now
        appIDs.removeAll()
    }

    /// Retention deletes, run on every write; each must seek its table's key.
    /// Sample tables lead with the metric, so they delete one metric at a time.
    enum Prune {
        static let recentSamples = "DELETE FROM samples WHERE metric = ? AND t < ?"
        static let ledgerIntervals = "DELETE FROM ledger_intervals WHERE t_end < ?"
        static let ledgerEntries = "DELETE FROM ledger_entries WHERE t_end < ?"
        static let daySamples = "DELETE FROM day_samples WHERE metric = ? AND t < ?"
        static let monthSamples = "DELETE FROM month_samples WHERE metric = ? AND t < ?"
        static let appDays = "DELETE FROM app_days WHERE day < ?"
        static let all = [recentSamples, ledgerIntervals, ledgerEntries, daySamples, monthSamples, appDays]

        /// One row per metric for the sample tables' deletes.
        static func perMetric(before cutoff: Date) -> [[SQLiteValue]] {
            HistoryMetric.allCases.map { [.integer(Int64($0.rawValue)), .real(cutoff.timeIntervalSince1970)] }
        }
    }

    private func pruneDay(before cutoff: Date) throws {
        try connection.run(Prune.daySamples, rows: Prune.perMetric(before: cutoff))
    }

    /// A day's totals stay until all of the day is older than the cutoff.
    private func pruneMonth(before cutoff: Date) throws {
        try connection.run(Prune.monthSamples, rows: Prune.perMetric(before: cutoff))
        try connection.run(Prune.appDays, rows: [[.real(day(of: cutoff.timeIntervalSince1970))]])
    }

    /// The Recent tables only: the Day tier keeps its own, longer retention.
    private func prune(before cutoff: Date) throws {
        let time: [[SQLiteValue]] = [[.real(cutoff.timeIntervalSince1970)]]
        try connection.run(Prune.recentSamples, rows: Prune.perMetric(before: cutoff))
        try connection.run(Prune.ledgerIntervals, rows: time)
        try connection.run(Prune.ledgerEntries, rows: time)
    }

    private static func userVersion(_ connection: SQLiteConnection) throws -> Int {
        guard case .integer(let version)? = try connection.query("PRAGMA user_version").first?.first else { return 0 }
        return Int(version)
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
            try pruneDay(before: cutoff)
            try pruneMonth(before: cutoff)
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
            SELECT time FROM (
                SELECT t AS time FROM samples UNION ALL SELECT t_end AS time FROM ledger_intervals
                UNION ALL SELECT t AS time FROM day_samples UNION ALL SELECT t AS time FROM month_samples
            )
            ORDER BY time LIMIT 1 OFFSET (
                (SELECT COUNT(*) FROM samples) + (SELECT COUNT(*) FROM ledger_intervals)
                + (SELECT COUNT(*) FROM day_samples) + (SELECT COUNT(*) FROM month_samples)
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
