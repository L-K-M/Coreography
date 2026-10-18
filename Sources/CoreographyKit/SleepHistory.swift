import Foundation
import CoreographyDrivers

public enum PowerEventKind: String, Codable, Sendable {
    case sleep, wake, darkWake
}

public enum PowerEventSource: String, Codable, Sendable {
    case ac, battery
}

/// One logged power transition. The reason is what the log recorded:
/// evidence, not a proven culprit.
public struct PowerEvent: Codable, Equatable, Sendable {
    public let time: Date
    public let kind: PowerEventKind
    public let reason: String?
    public let powerSource: PowerEventSource?
    public let batteryPercent: Int?
}

/// From a Sleep record to the next full Wake; dark wakes stay inside it.
/// Battery change over sleep is kept apart from awake app activity.
public struct SleepPeriod: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let sleepReason: String?
    public let wakeReason: String?
    public let darkWakes: Int
    /// Charge at wake minus charge at sleep, when both were logged.
    public let batteryChangePercent: Int?
}

public struct SleepHistory: Sendable {
    public enum Coverage: Equatable, Sendable {
        case complete
        /// Why some records may be missing.
        case partial(String)
    }

    public let importedAt: Date
    /// The first and last log records read, of any kind.
    public let coveredFrom: Date?
    public let coveredTo: Date?
    public let coverage: Coverage
    /// Oldest first.
    public let events: [PowerEvent]
    public let periods: [SleepPeriod]
}

public enum SleepHistoryError: Error, Equatable, Sendable {
    case unavailable(String)
}

/// Imports sleep and wake records off the sampling path, on request
/// (plan: a bounded background provider run after wake).
public struct SleepHistoryProvider: Sendable {
    private let driver: any PowerLogReading

    public init() { self.init(driver: PowerLogDriver()) }

    init(driver: any PowerLogReading) { self.driver = driver }

    public func load(now: Date = Date()) async throws -> SleepHistory {
        let raw: RawPowerLog
        do {
            raw = try await driver.read()
        } catch PowerLogError.unavailable(let reason) {
            throw SleepHistoryError.unavailable(reason)
        }

        let log = PowerLogParser.parse(raw.text)
        guard raw.exitStatus == 0 || log.firstRecord != nil else {
            throw SleepHistoryError.unavailable("pmset exited with status \(raw.exitStatus) and no records")
        }

        var gaps: [String] = []
        if raw.truncated { gaps.append("older records exceeded the import cap") }
        if raw.timedOut { gaps.append("pmset hit its time limit, so newer records may be missing") }
        if raw.exitStatus != 0 { gaps.append("pmset exited with status \(raw.exitStatus)") }
        return SleepHistory(
            importedAt: now, coveredFrom: log.firstRecord, coveredTo: log.lastRecord,
            coverage: gaps.isEmpty ? .complete : .partial(gaps.joined(separator: "; ")),
            events: log.events, periods: Self.periods(log.events)
        )
    }

    /// Sleep opens a period, dark wakes count inside it, a full Wake closes it.
    /// A period still open when the log ends has no wake to report and is left out.
    static func periods(_ events: [PowerEvent]) -> [SleepPeriod] {
        var periods: [SleepPeriod] = []
        var opened: PowerEvent?
        var darkWakes = 0
        for event in events {
            switch event.kind {
            case .sleep:
                guard opened == nil else { continue }
                opened = event
                darkWakes = 0
            case .darkWake:
                if opened != nil { darkWakes += 1 }
            case .wake:
                guard let start = opened else { continue }
                let change = event.batteryPercent.flatMap { end in start.batteryPercent.map { end - $0 } }
                periods.append(SleepPeriod(
                    start: start.time, end: event.time, sleepReason: start.reason, wakeReason: event.reason,
                    darkWakes: darkWakes, batteryChangePercent: change
                ))
                opened = nil
            }
        }
        return periods
    }
}

/// Parses `pmset -g log` records; every other line is skipped.
///
/// ```text
/// 2026-10-17 23:41:07 +0200 Sleep               <TAB>Entering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:81%) 3 secs
/// 2026-10-18 03:12:40 +0200 DarkWake            <TAB>DarkWake from Deep Idle [CDN] : due to RTC/Maintenance Using BATT (Charge:80%) 45 secs
/// 2026-10-18 07:02:15 +0200 Wake                <TAB>DarkWake to FullWake from Deep Idle [CDNVA] : due to UserActivity Assertion Using BATT (Charge:74%)
/// ```
enum PowerLogParser {
    struct Log: Equatable {
        let events: [PowerEvent]
        let firstRecord: Date?
        let lastRecord: Date?
    }

    private static let timestampLength = "yyyy-MM-dd HH:mm:ss +zzzz".count
    private static let kinds: [String: PowerEventKind] = ["Sleep": .sleep, "Wake": .wake, "DarkWake": .darkWake]
    /// Reasons are log text, not instructions; long ones are cut.
    private static let maximumReasonLength = 160

    static func parse(_ text: String) -> Log {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let lines = text.split(whereSeparator: \.isNewline)

        // Coverage spans every dated record, not only sleep and wake.
        let firstRecord = lines.lazy.compactMap { timestamp($0, formatter) }.first
        let lastRecord = lines.reversed().lazy.compactMap { timestamp($0, formatter) }.first
        let events = lines.compactMap { event($0, formatter) }
        return Log(events: events, firstRecord: firstRecord, lastRecord: lastRecord)
    }

    private static func timestamp(_ line: Substring, _ formatter: DateFormatter) -> Date? {
        guard line.count > timestampLength, line.first?.isNumber == true else { return nil }
        return formatter.date(from: String(line.prefix(timestampLength)))
    }

    private static func event(_ line: Substring, _ formatter: DateFormatter) -> PowerEvent? {
        let rest = line.dropFirst(timestampLength).drop(while: { $0 == " " })
        // The domain column is padded and ends at a tab; two spaces stand in for it.
        guard let end = rest.firstIndex(of: "\t") ?? rest.range(of: "  ")?.lowerBound,
              let kind = kinds[rest[..<end].trimmingCharacters(in: .whitespaces)],
              let time = timestamp(line, formatter) else { return nil }

        let message = rest[end...].trimmingCharacters(in: .whitespaces)
        return PowerEvent(
            time: time, kind: kind, reason: reason(message), powerSource: source(message),
            batteryPercent: charge(message)
        )
    }

    /// "due to 'Clamshell Sleep':TCP…" gives "Clamshell Sleep";
    /// "due to EC.LidOpen/Lid Open Using BATT" gives "EC.LidOpen/Lid Open".
    private static func reason(_ message: String) -> String? {
        guard let start = message.range(of: "due to ")?.upperBound else { return nil }
        var text = message[start...]
        if let using = text.range(of: " Using ") { text = text[..<using.lowerBound] }
        if text.first == "'", let close = text.dropFirst().firstIndex(of: "'") {
            text = text[text.index(after: text.startIndex)..<close]
        }
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":")))
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumReasonLength))
    }

    private static func source(_ message: String) -> PowerEventSource? {
        let lowered = message.lowercased()
        if lowered.contains(" using ac") { return .ac }
        if lowered.contains(" using batt") { return .battery }
        return nil
    }

    private static func charge(_ message: String) -> Int? {
        guard let start = message.range(of: "(Charge:")?.upperBound,
              let end = message[start...].firstIndex(of: "%") else { return nil }
        return Int(message[start..<end])
    }
}
