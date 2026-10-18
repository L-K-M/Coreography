import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class ProcessNetworkTests: XCTestCase {
    private let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date(timeIntervalSince1970: 1_700_000_000))

    func testRowsJoinByPIDAndNameAndIdleProcessesReadZero() throws {
        let processes = try snapshot([
            (10, "Safari", "/Applications/Safari.app/Contents/MacOS/Safari", nil),
            (11, "com.apple.WebKit.WebContent", "/System/Library/Frameworks/WebKit.framework/WebContent", 10),
            (12, "Mail", "/Applications/Mail.app/Contents/MacOS/Mail", nil),
            (13, "reused", "/usr/bin/reused", nil)
        ])
        let traffic = try trafficSnapshot([
            (10, "Safari", 1_000, 10), (11, "com.apple.WebK", 3_000, 30), (13, "previous", 500, 5)
        ])
        let rows = ProcessGroups.rows(
            in: processes, matching: "", sortedBy: .network, grouping: .app, facts: ProcessFacts(traffic: traffic)
        )
        let safari = try XCTUnwrap(rows.first { $0.name == "Safari" })
        XCTAssertEqual(safari.networkReceivedBytesPerSecond.numericValue, 4_000, "the helper's short name matches its full name")
        XCTAssertEqual(safari.networkSentBytesPerSecond.numericValue, 40)
        XCTAssertEqual(rows.first?.name, "Safari", "sorted by network")

        let mail = try XCTUnwrap(rows.first { $0.name == "Mail" })
        XCTAssertEqual(mail.networkReceivedBytesPerSecond.numericValue, 0, "no open socket is a measured zero")
        let reused = try XCTUnwrap(rows.first { $0.name == "reused" })
        XCTAssertEqual(reused.networkReceivedBytesPerSecond.availability, .collecting, "another process's bytes are not borrowed")

        let unread = ProcessGroups.rows(in: processes, matching: "", sortedBy: .cpu, grouping: .flat)
        XCTAssertTrue(unread.allSatisfy { $0.networkReceivedBytesPerSecond.availability == .collecting })
    }

    func testUnavailableTrafficIsUnsupportedWithItsReason() throws {
        let processes = try snapshot([(10, "Safari", nil, nil)])
        let traffic = ProcessTrafficSnapshot(
            stamp: stamp, processes: [], unattributedReceivedBytesPerSecond: .unsupported(),
            unattributedSentBytesPerSecond: .unsupported(), unavailableReason: "Per-process network needs macOS"
        )
        let rates = ProcessNetwork.rates(for: processes.processes[0], in: traffic)
        XCTAssertEqual(rates.received.availability, .unsupported)
        XCTAssertEqual(rates.received.reason, "Per-process network needs macOS")
    }

    // MARK: Fixtures

    private func trafficSnapshot(_ rows: [(Int32, String, Double, Double)]) throws -> CapturedTraffic {
        ProcessTrafficSnapshot(
            stamp: stamp,
            processes: try rows.map { pid, name, received, sent in
                ProcessTrafficReading(
                    uniqueID: UInt64(pid) + 1000, pid: pid, name: name,
                    receivedBytesPerSecond: try .measured(received), sentBytesPerSecond: try .measured(sent)
                )
            },
            unattributedReceivedBytesPerSecond: try .measured(0), unattributedSentBytesPerSecond: try .measured(0),
            unavailableReason: nil
        )
    }

    private func snapshot(_ rows: [(Int32, String, String?, Int32?)]) throws -> CapturedProcesses {
        let processes = try rows.map { pid, name, path, responsible in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501, name: name,
                stamp: stamp, cpuPercentOfMachine: try .measured(0), memoryFootprintBytes: try .measured(1),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                executablePath: path, responsiblePID: responsible
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(processes.count)), enumerationTruncated: false,
            processes: processes, issues: [], continuity: .continuous
        )
    }
}
