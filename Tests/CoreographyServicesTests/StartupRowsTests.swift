import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class StartupRowsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testItemsJoinToTheirRunningProcessesAndAppsHidingAppleByDefault() throws {
        let inventory = StartupInventory(
            takenAt: epoch, items: [
                item("com.example.sync", program: "/opt/sync/syncd"),
                item("com.example.idle", program: "/opt/idle/idled"),
                item("com.apple.thing", program: "/usr/libexec/thing", apple: true)
            ],
            unreadableDefinitions: 0, stateProblem: nil
        )
        var ledger = AppLedger(capacity: 10)
        ledger.record(try processes(at: 0), logicalCPUCount: 4)
        ledger.record(try processes(at: 2), logicalCPUCount: 4)

        let rows = StartupRows.rows(inventory, processes: try processes(at: 2), ledger: ledger, now: epoch.addingTimeInterval(2), visibility: .thirdParty)
        XCTAssertEqual(rows.map(\.item.label), ["com.example.sync", "com.example.idle"], "Apple items are hidden by default")
        let sync = try XCTUnwrap(rows.first)
        XCTAssertEqual(sync.processCount, 2)
        XCTAssertEqual(sync.cpuPercentOfMachine ?? 0, 30, accuracy: 1e-9)
        XCTAssertEqual(sync.memoryFootprintBytes, 2048)
        // 30% of 4 cores for 2 s across both instances.
        XCTAssertEqual(sync.appCPUSecondsLastHour ?? 0, 2.4, accuracy: 1e-9)
        XCTAssertEqual(rows.last?.processCount, 0)
        XCTAssertNil(rows.last?.cpuPercentOfMachine, "not running is not zero use")

        let all = StartupRows.rows(inventory, processes: nil, ledger: ledger, now: epoch, visibility: .all)
        XCTAssertEqual(all.count, 3)
    }

    private func item(_ label: String, program: String, apple: Bool = false) -> StartupItem {
        StartupItem(
            label: label, kind: apple ? .systemDaemon : .userAgent, plistPath: "/x/\(label).plist", program: program,
            runsAtLoad: true, keepsAlive: false, state: .enabled, isApple: apple
        )
    }

    private func processes(at second: TimeInterval) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: UInt64(second * 1e9), wallTime: epoch.addingTimeInterval(second))
        let rows = try [(10, 20.0), (11, 10.0)].map { pid, cpu in
            ProcessReading(
                id: try ProcessIdentity(pid: Int32(pid), startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501,
                name: "syncd", stamp: stamp, cpuPercentOfMachine: try .measured(cpu), memoryFootprintBytes: try .measured(1024),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                executablePath: "/opt/sync/syncd", responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(2), enumerationTruncated: false,
            processes: rows, issues: [], continuity: .continuous
        )
    }
}
