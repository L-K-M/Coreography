import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class ProcessFilterTests: XCTestCase {
    func testParsesPredicatesTokensAndUnits() {
        let filter = ProcessFilter.parse("safari cpu:>10 mem:>=1.5GB disk:<5MB/s pid:42 user:me #apps #third-party", currentUser: 501)
        XCTAssertEqual(filter.terms, [
            .text("safari"), .cpu(.greater(10)), .memory(.greaterOrEqual(1.5e9)), .disk(.less(5e6)),
            .pid(42), .user(501), .token(.apps), .token(.thirdParty)
        ])
        XCTAssertTrue(filter.issues.isEmpty)
        XCTAssertEqual(ProcessFilter.parse("cpu:25%").terms, [.cpu(.greaterOrEqual(25))], "a bare number means at least")
        XCTAssertEqual(ProcessFilter.parse("user:root").terms, [.user(0)])
    }

    func testUnsupportedAndUnreadableTermsAreReportedNotDropped() {
        let filter = ProcessFilter.parse("#not-responding #bogus cpu:lots user:nobody")
        XCTAssertTrue(filter.terms.isEmpty)
        XCTAssertEqual(filter.issues, [
            "Ignored #not-responding: needs the helper's responsiveness check", "Unknown token #bogus",
            "Unreadable cpu:lots; try cpu:>10", "Unknown user nobody; use a UID, me or root"
        ])
    }

    func testMatchingIsConjunctiveAndUnknownIsNotZero() throws {
        let busy = try process(name: "Xcode", cpu: 40, uid: 501, path: "/Applications/Xcode.app/Contents/MacOS/Xcode")
        let unreadable = try process(name: "Daemon", cpu: nil, uid: 0, path: "/usr/libexec/daemon")

        XCTAssertTrue(ProcessFilter.parse("xcode cpu:>10 #apps #mine #third-party", currentUser: 501).matches(busy, isNew: false, currentUser: 501))
        XCTAssertFalse(ProcessFilter.parse("xcode cpu:>50").matches(busy, isNew: false))
        // An unreadable CPU reading is unknown: it satisfies neither cpu:<5 nor cpu:>5.
        XCTAssertFalse(ProcessFilter.parse("cpu:<5").matches(unreadable, isNew: false))
        XCTAssertFalse(ProcessFilter.parse("cpu:>5").matches(unreadable, isNew: false))
        XCTAssertTrue(ProcessFilter.parse("#root").matches(unreadable, isNew: false))
        XCTAssertFalse(ProcessFilter.parse("#third-party").matches(unreadable, isNew: false))
        XCTAssertTrue(ProcessFilter.parse("#new").matches(busy, isNew: true))
        XCTAssertFalse(ProcessFilter.parse("#new").matches(busy, isNew: false))
    }

    func testListeningAndPortLookupNeedConnectionDataAndMatchTheirProcesses() throws {
        let server = try process(name: "nginx", cpu: 1, uid: 501, path: "/opt/nginx", pid: 80)
        let client = try process(name: "curl", cpu: 1, uid: 501, path: "/usr/bin/curl", pid: 81)
        let sockets = ProcessFacts(sockets: SocketFacts(ConnectionSnapshot(
            takenAt: Date(), connections: [
                ConnectionReading(
                    process: server.id, processName: "nginx", descriptor: 3, transport: .tcp, state: .listen,
                    local: ConnectionEndpoint(address: "0.0.0.0", port: 8080), remote: nil
                ),
                ConnectionReading(
                    process: client.id, processName: "curl", descriptor: 4, transport: .tcp, state: .established,
                    local: ConnectionEndpoint(address: "10.0.0.2", port: 50000), remote: ConnectionEndpoint(address: "1.1.1.1", port: 443)
                )
            ],
            restrictedProcesses: 0, truncatedProcesses: 0, failedProcesses: 0, unavailableReason: nil
        )))

        let listening = ProcessFilter.parse("#listening")
        XCTAssertTrue(listening.usesSockets)
        XCTAssertTrue(listening.matches(server, isNew: false, facts: sockets))
        XCTAssertFalse(listening.matches(client, isNew: false, facts: sockets))
        XCTAssertFalse(listening.matches(server, isNew: false), "without connection data nothing is listening")

        // Reverse lookup by port, local or remote.
        XCTAssertEqual(ProcessFilter.parse("port:8080").terms, [.port(8080)])
        XCTAssertTrue(ProcessFilter.parse("port:8080").matches(server, isNew: false, facts: sockets))
        XCTAssertTrue(ProcessFilter.parse("port:443").matches(client, isNew: false, facts: sockets))
        XCTAssertFalse(ProcessFilter.parse("port:443").matches(server, isNew: false, facts: sockets))
        XCTAssertEqual(ProcessFilter.parse("port:http").issues, ["Unreadable port:http; try port:443"])
        XCTAssertEqual(ProcessFilter.parse("port:0").issues, ["Unreadable port:0; try port:443"])
    }

    func testPreventingSleepMatchesAssertionHoldersOnlyOnceAssertionsAreRead() throws {
        let player = try process(name: "Music", cpu: 1, uid: 501, path: "/Applications/Music.app/Contents/MacOS/Music", pid: 90)
        let idle = try process(name: "Notes", cpu: 0, uid: 501, path: "/Applications/Notes.app/Contents/MacOS/Notes", pid: 91)
        let filter = ProcessFilter.parse("#preventing-sleep")
        XCTAssertTrue(filter.usesAssertions)
        XCTAssertTrue(filter.issues.isEmpty)
        let facts = ProcessFacts(sleepPreventers: [90])
        XCTAssertTrue(filter.matches(player, isNew: false, facts: facts))
        XCTAssertFalse(filter.matches(idle, isNew: false, facts: facts))
        XCTAssertFalse(filter.matches(player, isNew: false), "no assertion data, no match")
    }

    func testGroupsShowAllMembersOnlyForAppNameText() throws {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date())
        let host = try process(name: "Safari", cpu: 1, uid: 501, path: "/Applications/Safari.app/Contents/MacOS/Safari", pid: 10)
        let helper = try process(name: "Safari Helper", cpu: 30, uid: 501, path: "/Applications/Safari.app/Contents/Helpers/H.app/Contents/MacOS/H", pid: 11)
        let snapshot = ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(2), enumerationTruncated: false,
            processes: [host, helper], issues: [], continuity: .continuous
        )
        let byName = ProcessGroups.rows(in: snapshot, matching: "safari", sortedBy: .cpu, grouping: .app)
        XCTAssertEqual(byName.first?.children?.count, 2)
        let busy = ProcessGroups.rows(in: snapshot, matching: "safari cpu:>10", sortedBy: .cpu, grouping: .app)
        XCTAssertEqual(busy.first?.children?.map(\.name), ["Safari Helper"])
    }

    func testAppTextWithPredicatesKeepsMembersNamedOtherwise() throws {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date())
        let host = try process(name: "Safari", cpu: 1, uid: 501, path: "/Applications/Safari.app/Contents/MacOS/Safari", pid: 10)
        let content = try process(name: "com.apple.WebKit.WebContent", cpu: 45, uid: 501, path: nil, pid: 11, responsible: 10)
        let snapshot = ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(2), enumerationTruncated: false,
            processes: [host, content], issues: [], continuity: .continuous
        )
        let busy = ProcessGroups.rows(in: snapshot, matching: "safari cpu:>10", sortedBy: .cpu, grouping: .app)
        XCTAssertEqual(busy.first?.children?.map(\.name), ["com.apple.WebKit.WebContent"], "the app's name counts for its members")
        XCTAssertTrue(ProcessGroups.rows(in: snapshot, matching: "chrome cpu:>10", sortedBy: .cpu, grouping: .app).isEmpty)
    }

    func testNonFiniteBoundsAreReportedNotApplied() {
        let filter = ProcessFilter.parse("cpu:>nan mem:>=inf disk:1e400")
        XCTAssertTrue(filter.terms.isEmpty)
        XCTAssertEqual(filter.issues.count, 3)
    }

    func testUsrLocalIsThirdParty() throws {
        let brew = try process(name: "brew", cpu: 1, uid: 501, path: "/usr/local/bin/brew")
        let system = try process(name: "xpcproxy", cpu: 1, uid: 0, path: "/usr/libexec/xpcproxy")
        XCTAssertTrue(ProcessFilter.parse("#third-party").matches(brew, isNew: false))
        XCTAssertFalse(ProcessFilter.parse("#third-party").matches(system, isNew: false))
    }

    private func process(
        name: String, cpu: Double?, uid: UInt32, path: String?, pid: Int32 = 7, responsible: Int32? = nil
    ) throws -> ObservedProcess {
        ProcessReading(
            id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: uid, name: name,
            stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date()),
            cpuPercentOfMachine: try cpu.map { try .measured($0) } ?? .restricted(reason: "EPERM"),
            memoryFootprintBytes: try .measured(1e9), diskReadBytesPerSecond: try .measured(0),
            diskWriteBytesPerSecond: try .measured(0), executablePath: path, responsiblePID: responsible
        )
    }
}
