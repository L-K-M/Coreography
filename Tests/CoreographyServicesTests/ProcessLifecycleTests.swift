import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class ProcessLifecycleTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testNewRowsGhostsAndExpiry() throws {
        var lifecycle = ProcessLifecycle()
        lifecycle.record(try snapshot(at: 0, pids: [1, 2]))
        XCTAssertFalse(lifecycle.isNew(try identity(1), at: epoch), "present at launch is not new")

        lifecycle.record(try snapshot(at: 2, pids: [1, 3]))
        XCTAssertTrue(lifecycle.isNew(try identity(3), at: epoch.addingTimeInterval(2)))
        XCTAssertFalse(lifecycle.isNew(try identity(3), at: epoch.addingTimeInterval(13)))
        XCTAssertEqual(lifecycle.exited.map(\.identity.pid), [2])
        XCTAssertEqual(lifecycle.exited.first?.lastSeen, epoch, "the ghost keeps its last observation")

        lifecycle.record(try snapshot(at: 31, pids: [1, 3]))
        XCTAssertTrue(lifecycle.exited.isEmpty, "ghosts expire after 30 s")
    }

    func testSleepIsNotMistakenForExits() throws {
        var lifecycle = ProcessLifecycle()
        lifecycle.record(try snapshot(at: 0, pids: [1, 2]))
        lifecycle.record(try snapshot(at: 3600, pids: [1], continuity: .interrupted))
        XCTAssertTrue(lifecycle.exited.isEmpty)
    }

    func testTruncatedListIsNotMistakenForExits() throws {
        var lifecycle = ProcessLifecycle()
        lifecycle.record(try snapshot(at: 0, pids: [1, 2]))
        lifecycle.record(try snapshot(at: 1, pids: [1], truncated: true))
        XCTAssertTrue(lifecycle.exited.isEmpty, "a truncated list omits live processes")

        lifecycle.record(try snapshot(at: 2, pids: [1, 2]))
        XCTAssertTrue(lifecycle.exited.isEmpty)
        XCTAssertFalse(lifecycle.isNew(try identity(2), at: epoch.addingTimeInterval(2)), "left out is not new again")

        lifecycle.record(try snapshot(at: 3, pids: [1]))
        XCTAssertEqual(lifecycle.exited.map(\.identity.pid), [2])
    }

    func testReappearingProcessIsNotAGhost() throws {
        var lifecycle = ProcessLifecycle()
        lifecycle.record(try snapshot(at: 0, pids: [1, 2]))
        lifecycle.record(try snapshot(at: 1, pids: [1]))
        lifecycle.record(try snapshot(at: 2, pids: [1, 2]))
        XCTAssertTrue(lifecycle.exited.isEmpty, "a process seen again is alive")

        lifecycle.record(try snapshot(at: 3, pids: [1]))
        XCTAssertEqual(lifecycle.exited.map(\.identity.pid), [2], "one ghost per identity")
    }

    private func identity(_ pid: Int32) throws -> ProcessIdentity {
        try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0)
    }

    private func snapshot(
        at second: TimeInterval, pids: [Int32], continuity: SamplingContinuity = .continuous, truncated: Bool = false
    ) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: epoch.addingTimeInterval(second))
        let processes = try pids.map { pid in
            ProcessReading(
                id: try identity(pid), parentPID: 1, uid: 501, name: "P\(pid)", stamp: stamp,
                cpuPercentOfMachine: .collecting(), memoryFootprintBytes: .collecting(),
                diskReadBytesPerSecond: .collecting(), diskWriteBytesPerSecond: .collecting(),
                executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(pids.count)), enumerationTruncated: truncated,
            processes: processes, issues: [], continuity: continuity
        )
    }
}
