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
        let filter = ProcessFilter.parse("#listening #bogus cpu:lots user:nobody")
        XCTAssertTrue(filter.terms.isEmpty)
        XCTAssertEqual(filter.issues, [
            "Ignored #listening: needs the Connections data source", "Unknown token #bogus",
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

    private func process(
        name: String, cpu: Double?, uid: UInt32, path: String?, pid: Int32 = 7
    ) throws -> ObservedProcess {
        ProcessReading(
            id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: uid, name: name,
            stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date()),
            cpuPercentOfMachine: try cpu.map { try .measured($0) } ?? .restricted(reason: "EPERM"),
            memoryFootprintBytes: try .measured(1e9), diskReadBytesPerSecond: try .measured(0),
            diskWriteBytesPerSecond: try .measured(0), executablePath: path, responsiblePID: nil
        )
    }
}
