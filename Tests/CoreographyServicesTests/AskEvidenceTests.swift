import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class AskEvidenceTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plan: answers link to the processes and time ranges used as evidence.
    func testToolCallsNameTheirProcessesAppsAndRanges() throws {
        XCTAssertEqual(AskEvidence.from(tool: "get_process_details", input: ["pid": 42], result: "{}"), [.process(pid: 42)])

        let top = #"{"rows":[{"app":"Safari","value":3,"unit":"s","isLowerBound":false},"#
            + #"{"app":"Mail","value":1,"unit":"s","isLowerBound":false}],"#
            + #""coveredStart":"2023-11-14T22:13:20Z","coveredEnd":"2023-11-14T22:23:20Z"}"#
        XCTAssertEqual(AskEvidence.from(tool: "get_top_processes", input: [:], result: top), [
            .range(epoch...epoch.addingTimeInterval(600)), .app("Safari"), .app("Mail")
        ])

        let history = #"{"points":[{"time":"2023-11-14T22:13:20Z","value":1,"segment":0},"#
            + #"{"time":"2023-11-14T22:14:20Z","value":2,"segment":0}]}"#
        XCTAssertEqual(AskEvidence.from(tool: "get_metric_history", input: [:], result: history), [
            .range(epoch...epoch.addingTimeInterval(60))
        ])

        XCTAssertEqual(AskEvidence.from(tool: "get_top_processes", input: [:], result: #"{"rows":[]}"#), [],
                       "nothing covered is no range")
        XCTAssertEqual(AskEvidence.from(tool: "get_system_summary", input: [:], result: "{}"), [])
    }

    func testAPIDMatchesOnlyAProcessStartedByTheAnswer() throws {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: epoch)
        func process(start: UInt64) throws -> ProcessReading {
            ProcessReading(
                id: try ProcessIdentity(pid: 42, startSeconds: start, startMicroseconds: 0), parentPID: 1, uid: 501,
                name: "tool", stamp: stamp, cpuPercentOfMachine: .collecting(), memoryFootprintBytes: .collecting(),
                diskReadBytesPerSecond: .collecting(), diskWriteBytesPerSecond: .collecting(), executablePath: nil, responsiblePID: nil
            )
        }
        func snapshot(_ processes: [ProcessReading]) throws -> CapturedProcesses {
            ProcessSnapshot(stamp: stamp, collectorPID: 1, enumeration: try .measured(1), enumerationTruncated: false,
                            processes: processes, issues: [], continuity: .continuous)
        }
        let askedAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertNotNil(AskEvidence.process(42, in: try snapshot([process(start: 900)]), askedAt: askedAt))
        XCTAssertNil(AskEvidence.process(42, in: try snapshot([process(start: 1_100)]), askedAt: askedAt),
                     "a PID reused after the answer names another process")
    }
}
