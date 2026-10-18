import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class ProcessGroupsTests: XCTestCase {
    func testResponsibleHelpersFoldIntoTheirAppWithMeasuredTotals() throws {
        let rows = try ProcessGroups.rows(
            in: snapshot([safari, webContent(responsible: 100), standaloneDaemon]),
            matching: "", sortedBy: .cpu, grouping: .app
        )

        XCTAssertEqual(rows.map(\.name), ["Safari", "mds"])
        let group = try XCTUnwrap(rows.first)
        XCTAssertNil(group.process)
        XCTAssertEqual(group.memberCount, 2)
        XCTAssertEqual(group.cpuPercentOfMachine.availability, .measured)
        XCTAssertEqual(group.cpuPercentOfMachine.numericValue, 30)
        XCTAssertEqual(group.diskReadBytesPerSecond.numericValue, 2048)
        XCTAssertEqual(group.memoryFootprintBytes.availability, .estimated)
        XCTAssertEqual(group.memoryFootprintBytes.numericValue, 2 * 1_048_576)
        XCTAssertEqual(group.children?.map(\.name), ["com.apple.WebKit.WebContent", "Safari"])
        XCTAssertEqual(group.children?.map(\.groupingMethod), [.responsibleProcess, .appBundle])

        let daemon = try XCTUnwrap(rows.last)
        XCTAssertNil(daemon.children)
        XCTAssertEqual(daemon.groupingMethod, .standalone)
    }

    func testFlatRowsScopeByTheirAppSoTheLedgerFindsThem() throws {
        let processes = try snapshot([safari, webContent(responsible: 100), standaloneDaemon])
        let flat = ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpu, grouping: .flat)
        let helper = try XCTUnwrap(flat.first { $0.name == "com.apple.WebKit.WebContent" })
        XCTAssertEqual(helper.appName, "Safari", "the ledger records Safari, not each helper")
        XCTAssertEqual(flat.first { $0.name == "mds" }?.appName, "mds")

        var ledger = AppLedger(capacity: 4)
        ledger.record(processes, logicalCPUCount: 4)
        ledger.record(try snapshot(processes.processes, at: 2), logicalCPUCount: 4)
        XCTAssertFalse(ledger.series(for: helper.appName).cpu.isEmpty, "scoping from a flat row finds the app's series")
        XCTAssertGreaterThan(ledger.series(for: helper.appName).cpu.last?.value ?? 0, 0)
    }

    func testNestedHelperBundlesFoldIntoTheOutermostApp() throws {
        let main = try process(pid: 10, name: "Google Chrome", cpu: 1,
                               path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        let helper = try process(
            pid: 11, name: "Google Chrome Helper (Renderer)", cpu: 2,
            path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/"
                + "Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        )
        let rows = try ProcessGroups.rows(in: snapshot([main, helper]), matching: "", sortedBy: .name, grouping: .app)
        XCTAssertEqual(rows.map(\.name), ["Google Chrome"])
        XCTAssertEqual(rows.first?.memberCount, 2)
        XCTAssertEqual(rows.first?.children?.map(\.groupingMethod), [.appBundle, .appBundle])
    }

    func testReusedResponsiblePIDDoesNotClaimAnOlderProcess() throws {
        // PID 100 now names a process that started after the helper; it cannot own it.
        let younger = try process(pid: 100, name: "Newcomer", cpu: 1, start: 50)
        let helper = try webContent(responsible: 100)
        let rows = try ProcessGroups.rows(in: snapshot([younger, helper]), matching: "", sortedBy: .name, grouping: .app)
        XCTAssertEqual(rows.map(\.name), ["com.apple.WebKit.WebContent", "Newcomer"])
        XCTAssertEqual(rows.first?.groupingMethod, .standalone)
    }

    func testBundlelessResponsibleProcessCannotCombineUnrelatedApps() throws {
        let launchd = try process(pid: 1, name: "launchd", cpu: 0, start: 1, path: "/sbin/launchd")
        let browser = try process(
            pid: 100, name: "Safari", cpu: 10, path: "/Applications/Safari.app/Contents/MacOS/Safari", responsible: 1
        )
        let editor = try process(
            pid: 150, name: "Editor", cpu: 3, path: "/Applications/Editor.app/Contents/MacOS/Editor", responsible: 1
        )
        let rows = try ProcessGroups.rows(
            in: snapshot([launchd, browser, editor, webContent(responsible: 1)]),
            matching: "", sortedBy: .name, grouping: .app
        )

        XCTAssertEqual(Set(rows.map(\.name)), ["launchd", "Safari", "Editor", "com.apple.WebKit.WebContent"])
        XCTAssertTrue(rows.allSatisfy { $0.children == nil && $0.memberCount == 1 })
        XCTAssertEqual(rows.first { $0.process?.id.pid == 100 }?.groupingMethod, .appBundle)
        XCTAssertEqual(rows.first { $0.process?.id.pid == 150 }?.groupingMethod, .appBundle)
        XCTAssertEqual(rows.first { $0.process?.id.pid == 200 }?.groupingMethod, .standalone)
        XCTAssertEqual(rows.reduce(0) { $0 + ($1.cpuPercentOfMachine.numericValue ?? 0) }, 33)
    }

    func testUnreadableMembersMakeAnExplicitLowerBound() throws {
        let restricted = try process(pid: 200, name: "com.apple.WebKit.WebContent", cpu: nil, start: 20, responsible: 100)
        let rows = try ProcessGroups.rows(in: snapshot([safari, restricted]), matching: "", sortedBy: .cpu, grouping: .app)
        let cpu = try XCTUnwrap(rows.first?.cpuPercentOfMachine)
        XCTAssertEqual(cpu.availability, .estimated)
        XCTAssertEqual(cpu.numericValue, 10)
        XCTAssertEqual(cpu.method, "Lower bound: 1 of 2 members readable")

        let none = ProcessGroups.total([try .restricted(reason: "EPERM"), .collecting()], overlap: nil)
        XCTAssertEqual(none.availability, .collecting)
        XCTAssertNil(none.numericValue)
    }

    func testFilterKeepsWholeGroupTotalsButShowsMatchingMembers() throws {
        let processes = try [safari, webContent(responsible: 100), standaloneDaemon]
        let helperOnly = try ProcessGroups.rows(
            in: snapshot(processes), matching: " WebContent ", sortedBy: .cpu, grouping: .app
        )
        XCTAssertEqual(helperOnly.map(\.name), ["Safari"])
        XCTAssertEqual(helperOnly.first?.children?.map(\.name), ["com.apple.WebKit.WebContent"])
        XCTAssertEqual(helperOnly.first?.cpuPercentOfMachine.numericValue, 30)

        let byApp = try ProcessGroups.rows(in: snapshot(processes), matching: "safari", sortedBy: .cpu, grouping: .app)
        XCTAssertEqual(byApp.first?.children?.count, 2)

        let flat = try ProcessGroups.rows(in: snapshot(processes), matching: "", sortedBy: .cpu, grouping: .flat)
        XCTAssertEqual(flat.map(\.name), ["com.apple.WebKit.WebContent", "Safari", "mds"])
        XCTAssertTrue(flat.allSatisfy { $0.children == nil && $0.groupingMethod == nil })
    }

    func testContributorsRankAppsPerSubsystemAndSkipIdleOrUnreadableApps() throws {
        let idle = try process(pid: 400, name: "Idle", cpu: 0, path: "/Applications/Idle.app/Contents/MacOS/Idle")
        let unreadable = try process(pid: 500, name: "Hidden", cpu: nil)
        let contributors = Contributors.snapshot(
            from: try snapshot([safari, webContent(responsible: 100), standaloneDaemon, idle, unreadable])
        )
        XCTAssertEqual(contributors.time, Self.stamp.wallTime)
        XCTAssertEqual(contributors.cpu.map(\.name), ["Safari", "mds"])
        XCTAssertEqual(contributors.cpu.map(\.value), [30, 5])
        XCTAssertEqual(contributors.cpu.map(\.isEstimate), [false, false])
        // Footprint sums are estimates; ties break by name.
        XCTAssertEqual(contributors.memory.map(\.name), ["Safari", "Hidden", "Idle"])
        XCTAssertEqual(contributors.memory.first?.isEstimate, true)
        XCTAssertEqual(contributors.disk.first?.value, 2048)
        XCTAssertEqual(contributors.disk.count, Contributors.limit)
    }

    private static let clock = UUID(uuidString: "0D3C1E39-58E6-4A35-8F2B-8B8C3D1E8E11")!
    private static let stamp = SampleStamp(
        clockID: clock, monotonicNanoseconds: 1, wallTime: Date(timeIntervalSince1970: 1_700_000_000)
    )

    private var safari: ObservedProcess {
        get throws {
            try process(pid: 100, name: "Safari", cpu: 10, start: 10,
                        path: "/Applications/Safari.app/Contents/MacOS/Safari")
        }
    }

    private var standaloneDaemon: ObservedProcess {
        get throws { try process(pid: 300, name: "mds", cpu: 5, path: "/System/Library/Frameworks/mds") }
    }

    private func webContent(responsible: Int32) throws -> ObservedProcess {
        try process(
            pid: 200, name: "com.apple.WebKit.WebContent", cpu: 20, start: 20,
            path: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/"
                + "com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
            responsible: responsible
        )
    }

    private func process(
        pid: Int32, name: String, cpu: Double?, start: UInt64 = 10,
        path: String? = nil, responsible: Int32? = nil
    ) throws -> ObservedProcess {
        let source = MetricSource(provider: "processes", driver: "libproc")
        return ProcessReading(
            id: try ProcessIdentity(pid: pid, startSeconds: start, startMicroseconds: 0),
            parentPID: 1, uid: 501, name: name, stamp: Self.stamp,
            cpuPercentOfMachine: try cpu.map { try .measured($0, source: source) }
                ?? .restricted(reason: "EPERM", source: source),
            memoryFootprintBytes: try .measured(1_048_576, source: source),
            diskReadBytesPerSecond: try .measured(1024, source: source),
            diskWriteBytesPerSecond: try .measured(0, source: source),
            executablePath: path, responsiblePID: responsible
        )
    }

    private func snapshot(_ processes: [ObservedProcess], at second: TimeInterval = 0) throws -> CapturedProcesses {
        let stamp = SampleStamp(
            clockID: Self.stamp.clockID, monotonicNanoseconds: Self.stamp.monotonicNanoseconds + UInt64(second * 1e9),
            wallTime: Self.stamp.wallTime.addingTimeInterval(second)
        )
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(processes.count)),
            enumerationTruncated: false, processes: processes, issues: [], continuity: .continuous
        )
    }
}
