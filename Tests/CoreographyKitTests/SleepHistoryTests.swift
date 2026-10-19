import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class SleepHistoryTests: XCTestCase {
    // Real records use a padded domain column ending in a tab.
    private static let log = """
        Time stamp                Domain              Message                                                                         Duration  Delay
        ==========                ======              =======                                                                         ========  =====
        2026-10-17 23:40:58 +0200 Assertions          \tPID 412(powerd) Released PreventUserIdleSystemSleep "Playing audio" 00:12:03
        2026-10-17 23:41:07 +0200 Sleep               \tEntering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:81%) 3 secs
        2026-10-18 03:12:40 +0200 DarkWake            \tDarkWake from Deep Idle [CDN] : due to RTC/Maintenance Using BATT (Charge:80%) 45 secs
        2026-10-18 03:13:25 +0200 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:80%) 2 secs
        2026-10-18 05:00:00 +0200 Wake Requests       \t[*process=powerd request=Maintenance deltaSecs=7200]
        2026-10-18 07:02:15 +0200 Wake                \tDarkWake to FullWake from Deep Idle [CDNVA] : due to EC.LidOpen/Lid Open Using BATT (Charge:74%)
        2026-10-18 07:02:16 +0200 Kernel Client Acks  \tDelays to Wake notifications: [AppleUSB driver is slow(msg: SetState to 2)(1200 ms)]
        """

    func testParsesSleepWakeAndDarkWakeRecordsOnly() throws {
        let log = PowerLogParser.parse(Self.log)
        XCTAssertEqual(log.events.map(\.kind), [.sleep, .darkWake, .sleep, .wake], "Wake Requests and acks are not wakes")

        let sleep = try XCTUnwrap(log.events.first)
        XCTAssertEqual(sleep.reason, "Clamshell Sleep")
        XCTAssertEqual(sleep.powerSource, .battery)
        XCTAssertEqual(sleep.batteryPercent, 81)
        XCTAssertEqual(sleep.time, date("2026-10-17T21:41:07Z"))
        XCTAssertEqual(log.events[1].reason, "RTC/Maintenance")
        XCTAssertEqual(log.events.last?.reason, "EC.LidOpen/Lid Open")

        // Coverage spans every dated record, headers excluded.
        XCTAssertEqual(log.firstRecord, date("2026-10-17T21:40:58Z"))
        XCTAssertEqual(log.lastRecord, date("2026-10-18T05:02:16Z"))
    }

    func testAcceptsSpacePaddedColumnsAndMissingDetails() {
        let log = PowerLogParser.parse("""
            2026-10-18 09:00:00 -0700 Sleep                Entering Sleep state due to 'Idle Sleep' Using AC
            2026-10-18 09:30:00 -0700 Wake                 Wake from Normal Sleep [CDNVA]
            2026-10-18 09:3
            """)
        XCTAssertEqual(log.events.map(\.kind), [.sleep, .wake])
        XCTAssertEqual(log.events.first?.powerSource, .ac)
        XCTAssertNil(log.events.first?.batteryPercent)
        XCTAssertNil(log.events.last?.reason)
        XCTAssertEqual(log.lastRecord, date("2026-10-18T16:30:00Z"), "a cut line is not a record")
    }

    func testPeriodsSpanDarkWakesAndReportBatteryChangeOverSleep() {
        let periods = SleepHistoryProvider.periods(PowerLogParser.parse(Self.log).events)
        XCTAssertEqual(periods, [SleepPeriod(
            start: date("2026-10-17T21:41:07Z"), end: date("2026-10-18T05:02:15Z"),
            sleepReason: "Clamshell Sleep", wakeReason: "EC.LidOpen/Lid Open", darkWakes: 1, batteryChangePercent: -7
        )])

        // A wake without a logged sleep, or a sleep still open, makes no period.
        let open = PowerLogParser.parse("""
            2026-10-18 07:00:00 +0000 Wake                \tWake from Deep Idle : due to UserActivity
            2026-10-18 08:00:00 +0000 Sleep               \tEntering Sleep state due to 'Idle Sleep'
            """)
        XCTAssertTrue(SleepHistoryProvider.periods(open.events).isEmpty)
    }

    func testCapsReportPartialCoverage() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let complete = try await SleepHistoryProvider(driver: ScriptedPowerLog(.success(raw(Self.log)))).load(now: now)
        XCTAssertEqual(complete.coverage, .complete)
        XCTAssertEqual(complete.importedAt, now)
        XCTAssertEqual(complete.periods.count, 1)

        let capped = try await SleepHistoryProvider(
            driver: ScriptedPowerLog(.success(raw(Self.log, truncated: true, timedOut: true)))
        ).load()
        guard case .partial(let reason) = capped.coverage else { return XCTFail("expected partial coverage") }
        XCTAssertTrue(reason.contains("import cap") && reason.contains("time limit"))

        let failed = SleepHistoryProvider(driver: ScriptedPowerLog(.success(raw("pmset: error", exitStatus: 1))))
        await assertUnavailable(failed)
        let missing = SleepHistoryProvider(driver: ScriptedPowerLog(.failure(.unavailable("no pmset"))))
        await assertUnavailable(missing)
    }

    // MARK: Fixtures

    private func assertUnavailable(_ provider: SleepHistoryProvider, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await provider.load()
            XCTFail("expected unavailable", file: file, line: line)
        } catch {
            guard case .unavailable = error as? SleepHistoryError else {
                return XCTFail("unexpected \(error)", file: file, line: line)
            }
        }
    }

    private func raw(_ text: String, truncated: Bool = false, timedOut: Bool = false, exitStatus: Int32 = 0) -> RawPowerLog {
        RawPowerLog(text: text, truncated: truncated, timedOut: timedOut, exitStatus: exitStatus)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }
}

private struct ScriptedPowerLog: PowerLogReading {
    let result: Result<RawPowerLog, PowerLogError>

    init(_ result: Result<RawPowerLog, PowerLogError>) { self.result = result }

    func read() async throws -> RawPowerLog { try result.get() }
}
