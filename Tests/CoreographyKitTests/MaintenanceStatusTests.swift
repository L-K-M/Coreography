import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class MaintenanceStatusTests: XCTestCase {
    // Real `tmutil status` output during a backup.
    private static let copying = """
        Backup session status:
        {
            BackupPhase = Copying;
            ClientID = "com.apple.backupd";
            DateOfStateChange = "2026-10-18 10:55:21 +0000";
            DestinationID = "8C2A0E7D-0000-4000-8000-000000000000";
            Percent = "0.4231";
            Progress =     {
                Percent = "0.4231";
                TimeRemaining = 312;
                "_raw_Percent" = "0.42";
                bytes = 123456;
                files = 123;
                totalBytes = 123456789;
                totalFiles = 12345;
            };
            Running = 1;
            Stopping = 0;
        }
        """

    func testParsesARunningBackupWithItsPhaseAndProgress() {
        XCTAssertEqual(
            TimeMachineStatusParser.parse(Self.copying),
            .backingUp(BackupProgress(phase: "Copying", fraction: 0.4231, remainingSeconds: 312))
        )
    }

    func testUnknownProgressIsAbsentRatherThanZero() {
        let finding = """
            Backup session status:
            {
                BackupPhase = FindingChanges;
                Percent = "-1";
                Running = 1;
            }
            """
        XCTAssertEqual(
            TimeMachineStatusParser.parse(finding),
            .backingUp(BackupProgress(phase: "FindingChanges", fraction: nil, remainingSeconds: nil))
        )
    }

    /// tmutil's output is parsed, not trusted: an absurd estimate is unknown, not a crash.
    func testAnOutOfRangeEstimateIsUnknown() {
        let absurd = """
            Backup session status:
            {
                BackupPhase = Copying;
                Progress = { TimeRemaining = "1e300"; };
                Running = 1;
            }
            """
        XCTAssertEqual(
            TimeMachineStatusParser.parse(absurd),
            .backingUp(BackupProgress(phase: "Copying", fraction: nil, remainingSeconds: nil))
        )
    }

    func testIdleAndUnrecognisedStatus() {
        let idle = """
            Backup session status:
            {
                ClientID = "com.apple.backupd";
                Percent = "-1";
                Running = 0;
            }
            """
        XCTAssertEqual(TimeMachineStatusParser.parse(idle), .idle)
        XCTAssertEqual(TimeMachineStatusParser.parse("No such command"), .unavailable("tmutil printed an unrecognised status"))
        XCTAssertEqual(
            TimeMachineStatusParser.parse("Backup session status:\n{\n    ClientID = x;\n}"),
            .unavailable("tmutil did not say whether a backup is running"),
            "a status without Running is not idle"
        )
    }

    func testSpotlightReportsOnlyWhetherTheDiskIsIndexed() {
        XCTAssertEqual(SpotlightStatusParser.parse("/:\n\tIndexing enabled. \n"), .enabled)
        XCTAssertEqual(SpotlightStatusParser.parse("/:\n\tIndexing disabled.\n"), .disabled)
        XCTAssertEqual(SpotlightStatusParser.parse("/:\n\tIndexing and searching disabled.\n"), .disabled)
        XCTAssertEqual(SpotlightStatusParser.parse("/:\n\tIndexing and searching enabled.\n"), .enabled, "the enabled form of the same wording")
        XCTAssertEqual(SpotlightStatusParser.parse("/:\n\tError: unknown indexing state.\n"), .unavailable("mdutil printed an unrecognised status"))
    }

    func testFailedOrCutOffToolsAreUnavailableNotIdle() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let timedOut = await MaintenanceStatusProvider(driver: Tools(
            timeMachine: .success(RawToolStatus(text: "", timedOut: true, exitStatus: 9)),
            spotlight: .success(RawToolStatus(text: "/:\n\tIndexing enabled.", timedOut: false, exitStatus: 0))
        )).load(now: now)
        XCTAssertEqual(timedOut, MaintenanceStatus(readAt: now, timeMachine: .unavailable("tmutil hit its time limit"), spotlight: .enabled))

        let failed = await MaintenanceStatusProvider(driver: Tools(
            timeMachine: .failure(.unavailable("tmutil needs macOS")),
            spotlight: .success(RawToolStatus(text: "/:\n\tIndexing enabled.", timedOut: false, exitStatus: 1))
        )).load(now: now)
        XCTAssertEqual(failed.timeMachine, .unavailable("tmutil needs macOS"))
        XCTAssertEqual(failed.spotlight, .unavailable("mdutil exited with status 1"))
    }
}

private struct Tools: MaintenanceStatusReading {
    let timeMachine: Result<RawToolStatus, MaintenanceStatusError>
    let spotlight: Result<RawToolStatus, MaintenanceStatusError>

    func timeMachineStatus() async throws -> RawToolStatus { try timeMachine.get() }

    func spotlightStatus() async throws -> RawToolStatus { try spotlight.get() }
}
