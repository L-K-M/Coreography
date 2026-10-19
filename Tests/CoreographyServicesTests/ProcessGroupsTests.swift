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

    func testGPUAndPowerSumPerAppAndSort() throws {
        let main = try process(pid: 10, name: "Game", cpu: 1, path: "/Applications/Game.app/Contents/MacOS/Game",
                               gpu: 40, power: 1.5)
        let helper = try process(pid: 11, name: "Game Helper", cpu: 1,
                                 path: "/Applications/Game.app/Contents/MacOS/Game Helper", gpu: 20, power: nil)
        let editor = try process(pid: 12, name: "Editor", cpu: 5, gpu: 5, power: 2)

        let byGPU = try ProcessGroups.rows(in: snapshot([main, helper, editor]), matching: "", sortedBy: .gpu, grouping: .app)
        XCTAssertEqual(byGPU.map(\.name), ["Game", "Editor"])
        let game = try XCTUnwrap(byGPU.first)
        XCTAssertEqual(game.gpuMillisecondsPerSecond.numericValue, 60)
        XCTAssertEqual(game.gpuMillisecondsPerSecond.availability, .measured)
        XCTAssertEqual(game.cpuPowerWatts.numericValue, 1.5)
        XCTAssertEqual(game.cpuPowerWatts.availability, .estimated, "one member has no energy counter: a lower bound")

        let byPower = try ProcessGroups.rows(in: snapshot([main, helper, editor]), matching: "", sortedBy: .power, grouping: .flat)
        XCTAssertEqual(byPower.map(\.name), ["Editor", "Game", "Game Helper"], "unknown power sorts last")
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

    /// Plan: opt-in CPU time and start time columns, sortable.
    func testGroupsTotalCPUTimeAndStartWithTheirFirstMember() throws {
        let processes = try snapshot([safari, webContent(responsible: 100), standaloneDaemon])
        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpuTime, grouping: .app)
        let group = try XCTUnwrap(rows.first { $0.name == "Safari" })
        XCTAssertEqual(group.cpuTimeSeconds.numericValue, 30, "10 s and 20 s of CPU")
        XCTAssertEqual(group.started, Date(timeIntervalSince1970: 10), "the app's first process")
        XCTAssertEqual(rows.map(\.name), ["Safari", "mds"], "most CPU time first")

        let newest = ProcessGroups.rows(in: processes, matching: "", sortedBy: .started, grouping: .flat)
        XCTAssertEqual(newest.map(\.name), ["com.apple.WebKit.WebContent", "Safari", "mds"], "newest first, ties by PID")
    }

    /// Plan: grouping as a parent-child tree, each row with its own readings.
    func testTreeNestsChildrenUnderTheirObservedParent() throws {
        let launchd = try process(pid: 1, name: "launchd", cpu: 1, start: 1, parent: 0, uid: 0)
        let terminal = try process(pid: 50, name: "Terminal", cpu: 2, start: 5,
                                   path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
        let shell = try process(pid: 60, name: "zsh", cpu: 3, start: 6, responsible: 50, parent: 50)
        let job = try process(pid: 70, name: "python3", cpu: 40, start: 7, responsible: 50, parent: 60)
        // PID 90 started after PID 80, so it reuses the PID of 80's real parent.
        let orphan = try process(pid: 80, name: "orphan", cpu: 1, start: 8, parent: 90)
        let reused = try process(pid: 90, name: "reused", cpu: 1, start: 9)
        let processes = try snapshot([launchd, terminal, shell, job, orphan, reused])

        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpu, grouping: .tree)
        XCTAssertEqual(rows.map(\.name), ["launchd", "orphan"])
        let root = try XCTUnwrap(rows.first)
        XCTAssertEqual(root.kind, .process)
        XCTAssertEqual(root.cpuPercentOfMachine.numericValue, 1, "a parent shows its own use, not its subtree's")
        XCTAssertEqual(root.id, ProcessGroups.rowID(launchd), "selection survives a grouping change")
        XCTAssertEqual(root.children?.map(\.name), ["Terminal", "reused"])
        let python = try XCTUnwrap(root.children?.first?.children?.first?.children?.first)
        XCTAssertEqual(python.name, "python3")
        XCTAssertEqual(python.appName, "Terminal")
        XCTAssertNil(python.children)
        XCTAssertNil(rows.last?.children)

        let filtered = ProcessGroups.rows(in: processes, matching: "python", sortedBy: .cpu, grouping: .tree)
        XCTAssertEqual(filtered.map(\.name), ["launchd"], "a match keeps its ancestors")
        XCTAssertEqual(filtered.first?.children?.map(\.name), ["Terminal"])

        let scoped = ProcessGroups.scoped(rows, to: "Terminal")
        XCTAssertEqual(scoped.map(\.name), ["launchd"])
        XCTAssertEqual(scoped.first?.children?.map(\.name), ["Terminal"])
        XCTAssertEqual(scoped.first?.children?.first?.children?.first?.children?.map(\.name), ["python3"])

        let first = try process(pid: 20, name: "a", cpu: 1, start: 3, parent: 21)
        let second = try process(pid: 21, name: "b", cpu: 1, start: 3, parent: 20)
        let loop = ProcessGroups.rows(in: try snapshot([first, second]), matching: "", sortedBy: .name, grouping: .tree)
        XCTAssertEqual(loop.map(\.name), ["a"], "a parent loop lists each process once")
        XCTAssertEqual(loop.first?.children?.map(\.name), ["b"])
    }

    func testUserGroupsTotalEachUsersProcesses() throws {
        let daemon = try process(pid: 2, name: "configd", cpu: 4, start: 1, uid: 0)
        let guest = try process(pid: 400, name: "guest-tool", cpu: 1, uid: 502)
        let processes = try snapshot([safari, webContent(responsible: 100), daemon, guest])

        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpu, grouping: .user, currentUser: 501)
        XCTAssertEqual(rows.map(\.name), ["You, UID 501", "root", "UID 502"])
        XCTAssertEqual(rows.map(\.kind), [.user(501), .user(0), .user(502)])
        let mine = try XCTUnwrap(rows.first)
        XCTAssertNil(mine.process)
        XCTAssertEqual(mine.memberCount, 2)
        XCTAssertEqual(mine.cpuPercentOfMachine.numericValue, 30)
        XCTAssertEqual(mine.children?.map(\.name), ["com.apple.WebKit.WebContent", "Safari"])
        XCTAssertEqual(mine.children?.map(\.appName), ["Safari", "Safari"])
        XCTAssertEqual(rows.last?.children?.count, 1, "one process is still its user's group")

        let filtered = ProcessGroups.rows(in: processes, matching: "root", sortedBy: .cpu, grouping: .user, currentUser: 501)
        XCTAssertEqual(filtered.map(\.name), ["root"])
        XCTAssertEqual(filtered.first?.children?.map(\.name), ["configd"])

        let scoped = ProcessGroups.scoped(rows, to: "Safari")
        XCTAssertEqual(scoped.map(\.name), ["You, UID 501"])
        XCTAssertEqual(scoped.first?.children?.count, 2)
        XCTAssertEqual(ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpu, grouping: .app).first?.kind, .app)
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
        path: String? = nil, responsible: Int32? = nil, gpu: Double = 0, power: Double? = 0,
        parent: UInt32 = 1, uid: UInt32 = 501
    ) throws -> ObservedProcess {
        let source = MetricSource(provider: "processes", driver: "libproc")
        return ProcessReading(
            id: try ProcessIdentity(pid: pid, startSeconds: start, startMicroseconds: 0),
            parentPID: parent, uid: uid, name: name, stamp: Self.stamp,
            cpuPercentOfMachine: try cpu.map { try .measured($0, source: source) }
                ?? .restricted(reason: "EPERM", source: source),
            memoryFootprintBytes: try .measured(1_048_576, source: source),
            diskReadBytesPerSecond: try .measured(1024, source: source),
            diskWriteBytesPerSecond: try .measured(0, source: source),
            gpuMillisecondsPerSecond: try .measured(gpu, source: source),
            cpuPowerWatts: try power.map { try .estimated($0, method: "Energy model", source: source) }
                ?? .unsupported(reason: "No energy counter for this process", source: source),
            cpuTimeSeconds: try cpu.map { try .measured($0, source: source) } ?? .restricted(reason: "EPERM", source: source),
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
