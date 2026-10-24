import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class ResponsivenessMonitorTests: XCTestCase {
    private func reading(_ pid: Int32, startSeconds: UInt64 = 100) throws -> ProcessReading {
        ProcessReading(
            id: try ProcessIdentity(pid: pid, startSeconds: startSeconds, startMicroseconds: 0),
            parentPID: 0, uid: 501, name: "App\(pid)",
            stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date()),
            cpuPercentOfMachine: .collecting(), memoryFootprintBytes: .collecting(),
            diskReadBytesPerSecond: .collecting(), diskWriteBytesPerSecond: .collecting(),
            executablePath: nil, responsiblePID: nil
        )
    }

    func testMarkingNeedsConsecutiveUnresponsiveSamples() throws {
        let probe = StubProbe([95: true])
        var monitor = ResponsivenessMonitor(probe: probe)
        let app = try reading(95)

        monitor.record([app])
        XCTAssertTrue(monitor.notResponding.isEmpty, "one spike never marks a process")

        monitor.record([app])
        XCTAssertEqual(monitor.notResponding, [app.id], "the second unresponsive sample marks it")

        monitor.record([app])
        XCTAssertEqual(monitor.notResponding, [app.id])

        probe.set(95, false)
        monitor.record([app])
        XCTAssertTrue(monitor.notResponding.isEmpty, "one responsive answer clears the mark")
    }

    func testUnjudgeableAndRecycledProcessesAreNeverMarked() throws {
        let probe = StubProbe([96: true])
        var monitor = ResponsivenessMonitor(probe: probe)
        let daemon = try reading(12)
        let hung = try reading(96)

        monitor.record([daemon, hung])
        monitor.record([daemon, hung])
        XCTAssertEqual(monitor.notResponding, [hung.id], "a process the probe cannot judge stays unmarked")

        // The pid under a new start time is a new process: its streak restarts.
        let recycled = try reading(96, startSeconds: 200)
        monitor.record([daemon, recycled])
        XCTAssertTrue(monitor.notResponding.isEmpty, "a reused pid's mark does not transfer")
    }

    func testResetClearsStreaksSoEnablingAgainRecounts() throws {
        let probe = StubProbe([95: true])
        var monitor = ResponsivenessMonitor(probe: probe)
        let app = try reading(95)

        monitor.record([app])
        monitor.reset()
        monitor.record([app])
        XCTAssertTrue(monitor.notResponding.isEmpty, "a reset drops the kept streak")
        monitor.record([app])
        XCTAssertEqual(monitor.notResponding, [app.id])
    }
}

private final class StubProbe: ResponsivenessProbing, @unchecked Sendable {
    private var answers: [Int32: Bool?]
    init(_ answers: [Int32: Bool?]) { self.answers = answers }
    func set(_ pid: Int32, _ answer: Bool?) { answers[pid] = answer }
    func unresponsive(_ pid: Int32) -> Bool? { answers[pid] ?? nil }
}
