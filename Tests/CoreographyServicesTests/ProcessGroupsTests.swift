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
        XCTAssertTrue(game.cpuPowerWatts.method?.contains("Lower bound") ?? false, "the method says what is missing")

        // An app none of whose members has an energy counter is unknown, not 0 W, and sorts last.
        let tool = try process(pid: 13, name: "Tool", cpu: 1, path: "/Applications/Tool.app/Contents/MacOS/Tool", power: nil)
        let toolHelper = try process(pid: 14, name: "Tool Helper", cpu: 1, path: "/Applications/Tool.app/Contents/MacOS/Tool Helper", power: nil)
        let apps = try ProcessGroups.rows(in: snapshot([main, helper, editor, tool, toolHelper]), matching: "", sortedBy: .power, grouping: .app)
        XCTAssertEqual(apps.last?.name, "Tool")
        XCTAssertNil(apps.last?.cpuPowerWatts.numericValue)
        XCTAssertEqual(apps.last?.cpuPowerWatts.availability, .unsupported)

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

    /// Plan: the GPU detail's per-app GPU time and the power detail's
    /// per-app modeled energy, named like the other lanes' top apps.
    func testContributorsRankGPUTimeAndModeledPower() throws {
        let game = try process(pid: 600, name: "Game", cpu: 1, path: "/Applications/Game.app/Contents/MacOS/Game", gpu: 40, power: 2)
        let tool = try process(pid: 700, name: "tool", cpu: 1, path: "/usr/local/bin/tool", gpu: 0, power: nil)
        let contributors = Contributors.snapshot(from: try snapshot([game, tool]))
        XCTAssertEqual(contributors.gpu.map(\.name), ["Game"], "no GPU time is no contributor")
        XCTAssertEqual(contributors.gpu.first?.value, 40)
        XCTAssertEqual(contributors.power.map(\.name), ["Game"], "no energy counter is no contributor")
        XCTAssertEqual(contributors.power.first?.isEstimate, true, "modeled energy is an estimate")
    }

    /// Plan: app icons beside app rows. A helper outside the bundle does not hide it.
    /// Plan: an opt-in ports column. An app lists the ports its members
    /// listen on; a connection out is not a listening port.
    func testARowListsThePortsItsMembersListenOn() throws {
        let helper = try webContent(responsible: 100)
        let processes = try snapshot([safari, helper, standaloneDaemon])
        let socket = { (process: ObservedProcess, state: TCPState, port: UInt16) in
            ConnectionReading(
                process: process.id, processName: process.name, descriptor: 3, transport: .tcp, state: state,
                local: ConnectionEndpoint(address: "0.0.0.0", port: port),
                remote: state == .listen ? nil : ConnectionEndpoint(address: "1.1.1.1", port: 443)
            )
        }
        let connections = ConnectionSnapshot(
            takenAt: Date(), connections: [
                socket(processes.processes[0], .listen, 8080), socket(processes.processes[1], .listen, 5000),
                socket(processes.processes[1], .established, 50000)
            ],
            restrictedProcesses: 0, truncatedProcesses: 0, failedProcesses: 0, unavailableReason: nil
        )
        let rows = ProcessGroups.rows(
            in: processes, matching: "", sortedBy: .cpu, grouping: .app, facts: ProcessFacts(sockets: SocketFacts(connections))
        )
        XCTAssertEqual(rows.first { $0.name == "Safari" }?.listeningPorts, [5000, 8080])
        XCTAssertEqual(rows.first { $0.name == "mds" }?.listeningPorts, [], "read and listening on nothing")

        let unread = ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpu, grouping: .app)
        XCTAssertNil(unread.first { $0.name == "Safari" }?.listeningPorts, "no connection data is not no ports")

        // Another user's process was never read, so it has no answer rather than none;
        // a socket still binding (port 0) is no port.
        let other = try process(pid: 400, name: "postgres", cpu: nil, path: "/usr/local/bin/postgres", uid: 0)
        let mine = try process(pid: 500, name: "server", cpu: 1, path: "/usr/local/bin/server")
        let mixed = try snapshot([other, mine])
        let binding = ConnectionSnapshot(
            takenAt: Date(), connections: [socket(mine, .listen, 0)],
            restrictedProcesses: 1, truncatedProcesses: 0, failedProcesses: 0, unavailableReason: nil
        )
        let read = ProcessGroups.rows(
            in: mixed, matching: "", sortedBy: .cpu, grouping: .flat, facts: ProcessFacts(sockets: SocketFacts(binding))
        )
        XCTAssertNil(read.first { $0.name == "postgres" }?.listeningPorts)
        XCTAssertEqual(read.first { $0.name == "server" }?.listeningPorts, [])
    }

    func testARowFindsTheAppBundleOfItsFirstMemberInOne() throws {
        let processes = try snapshot([safari, webContent(responsible: 100), standaloneDaemon])
        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpu, grouping: .app)
        XCTAssertEqual(rows.first { $0.name == "Safari" }?.appBundlePath, "/Applications/Safari.app")
        XCTAssertNil(rows.first { $0.name == "mds" }?.appBundlePath)
    }

    /// The outermost bundle wins, in any case: volumes are usually case-insensitive.
    func testTheIconBundleIsTheOutermostInAnyCase() throws {
        let old = try process(pid: 600, name: "Old", cpu: 1, path: "/Applications/Old.APP/Contents/MacOS/Old")
        let plugIn = try process(pid: 700, name: "Bar", cpu: 1, path: "/Applications/Foo.app/Contents/PlugIns/Bar.app/Contents/MacOS/Bar")
        let rows = ProcessGroups.rows(in: try snapshot([old, plugIn]), matching: "", sortedBy: .cpu, grouping: .flat)
        XCTAssertEqual(rows.first { $0.name == "Old" }?.appBundlePath, "/Applications/Old.APP")
        XCTAssertEqual(rows.first { $0.name == "Bar" }?.appBundlePath, "/Applications/Foo.app")
        XCTAssertTrue(ProcessFilter.parse("#apps", currentUser: 501).matches(old, isNew: false, currentUser: 501))
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

    /// Plan: an opt-in threads column, and the header's thread total.
    func testGroupsSumThreadsAndUnreadCountsStayUnknown() throws {
        let processes = try snapshot([
            try process(pid: 100, name: "Safari", cpu: 9, path: "/Applications/Safari.app/Contents/MacOS/Safari", threads: 20),
            try process(pid: 101, name: "helper", cpu: 1, path: "/Applications/Safari.app/Contents/MacOS/helper", threads: 5),
            try process(pid: 200, name: "mds", cpu: 1, path: "/usr/sbin/mds", threads: 40),
            try process(pid: 300, name: "locked", cpu: nil, path: "/usr/sbin/locked", threads: nil)
        ])
        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .threads, grouping: .app)
        XCTAssertEqual(rows.map(\.name), ["mds", "Safari", "locked"], "most threads first, unread last")
        XCTAssertEqual(rows[1].threadCount.numericValue, 25, "an app sums its processes")
        XCTAssertEqual(rows[2].threadCount.availability, .restricted, "an unread count is not zero")

        let total = processes.threadTotal
        XCTAssertEqual(total.threads, 65)
        XCTAssertEqual(total.unread, 1)
    }

    /// Plan: an opt-in architecture column. An app lists what its members run.
    func testAnAppListsItsMembersArchitecturesAndRosettaFindsTranslatedOnes() throws {
        let processes = try snapshot([
            try process(pid: 100, name: "Safari", cpu: 9, path: "/Applications/Safari.app/Contents/MacOS/Safari",
                        architecture: .appleSilicon),
            try process(pid: 101, name: "plugin", cpu: 1, path: "/Applications/Safari.app/Contents/MacOS/plugin",
                        architecture: .intelTranslated),
            try process(pid: 200, name: "mds", cpu: 1, path: "/usr/sbin/mds")
        ])
        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpu, grouping: .app)
        XCTAssertEqual(rows.first { $0.name == "Safari" }?.architectures, [.appleSilicon, .intelTranslated])
        XCTAssertEqual(rows.first { $0.name == "mds" }?.architectures, [], "an unread architecture is not guessed")

        let translated = ProcessGroups.rows(in: processes, matching: "#rosetta", sortedBy: .cpu, grouping: .flat)
        XCTAssertEqual(translated.map(\.name), ["plugin"])
    }

    /// Plan: an opt-in signing column. An app lists each signer of its programs.
    func testAnAppListsTheSignersOfItsPrograms() throws {
        let safari = "/Applications/Safari.app/Contents/MacOS/Safari"
        let plugin = "/Applications/Safari.app/Contents/MacOS/plugin"
        let processes = try snapshot([
            try process(pid: 100, name: "Safari", cpu: 9, path: safari),
            try process(pid: 101, name: "plugin", cpu: 1, path: plugin),
            try process(pid: 200, name: "mds", cpu: 1, path: "/usr/sbin/mds")
        ])
        let facts = ProcessFacts(signers: [safari: .apple, plugin: .developer(team: "ABCDE12345")])
        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpu, grouping: .app, facts: facts)
        XCTAssertEqual(rows.first { $0.name == "Safari" }?.signers, [.apple, .developer(team: "ABCDE12345")])
        XCTAssertEqual(rows.first { $0.name == "mds" }?.signers, [], "not yet checked")
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

        // With account names, groups read as people do; a UID without one keeps its number.
        let named = ProcessGroups.rows(
            in: processes, matching: "", sortedBy: .cpu, grouping: .user,
            facts: ProcessFacts(accountNames: [0: "root", 501: "alice"]), currentUser: 501
        )
        XCTAssertEqual(named.map(\.name), ["You, alice", "root", "UID 502"])
        let byName = ProcessGroups.rows(
            in: processes, matching: "alice", sortedBy: .cpu, grouping: .user,
            facts: ProcessFacts(accountNames: [501: "alice"]), currentUser: 501
        )
        XCTAssertEqual(byName.map(\.name), ["You, alice"], "free text finds a group by its account name")
        let byNumber = ProcessGroups.rows(
            in: processes, matching: "501", sortedBy: .cpu, grouping: .user,
            facts: ProcessFacts(accountNames: [501: "alice"]), currentUser: 501
        )
        XCTAssertEqual(byNumber.map(\.name), ["You, alice"], "and still by its UID")

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
        parent: UInt32 = 1, uid: UInt32 = 501, threads: Double? = 1, architecture: ProcessArchitecture? = nil
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
            threadCount: try threads.map { try .measured($0, source: source) } ?? .restricted(reason: "EPERM", source: source),
            architecture: architecture,
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
