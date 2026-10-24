import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class ProcessExitWatcherTests: XCTestCase {
    #if os(macOS)
    func testNativeDriverReportsAChildExit() throws {
        let driver = try XCTUnwrap(ProcessExitDriver())
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "read value; exit 42"]
        let input = Pipe()
        child.standardInput = input
        try child.run()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }

        let sample = try XCTUnwrap(ProcessStatisticsDriver.identifiedCounters(pid: child.processIdentifier))
        let identity = HelperProcessIdentity(
            pid: sample.pid, startSeconds: sample.startSeconds, startMicroseconds: sample.startMicroseconds
        )
        driver.watch([identity])
        try input.fileHandleForWriting.write(contentsOf: Data("finish\n".utf8))
        child.waitUntilExit()
        let deadline = Date().addingTimeInterval(5)
        var events: [ExitEvent] = []
        repeat {
            events += driver.drain()
            if !events.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < deadline
        XCTAssertEqual(events, [ExitEvent(process: identity, status: 42 << 8)])
        XCTAssertTrue(driver.drain().isEmpty, "each exit is delivered once")
    }

    func testNativeDriverRejectsAMismatchedStartTime() throws {
        let driver = try XCTUnwrap(ProcessExitDriver())
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "read value; exit 3"]
        let input = Pipe()
        child.standardInput = input
        try child.run()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
        let sample = try XCTUnwrap(ProcessStatisticsDriver.identifiedCounters(pid: child.processIdentifier))
        driver.watch([HelperProcessIdentity(
            pid: sample.pid, startSeconds: sample.startSeconds + 1, startMicroseconds: sample.startMicroseconds
        )])
        try input.fileHandleForWriting.write(contentsOf: Data("finish\n".utf8))
        child.waitUntilExit()
        XCTAssertTrue(driver.drain().isEmpty, "the kernel watch must belong to the requested lifetime")
    }
    #endif

    private final class StubWatcher: ProcessExitWatching, @unchecked Sendable {
        var watched: Set<HelperProcessIdentity> = []
        var events: [ExitEvent] = []
        func watch(_ processes: Set<HelperProcessIdentity>) { watched = processes }
        func drain() -> [ExitEvent] { defer { events = [] }; return events }
    }

    func testWatchReplacesTheWatchedSet() throws {
        let stub = StubWatcher()
        var watcher = ProcessExitWatcher(driver: stub)
        watcher.watch([try identity(1), try identity(2)])
        XCTAssertEqual(stub.watched, [try identity(1).helperIdentity, try identity(2).helperIdentity])
        watcher.watch([try identity(2), try identity(3)])
        XCTAssertEqual(stub.watched, [try identity(2).helperIdentity, try identity(3).helperIdentity])
    }

    func testDrainReturnsStatusesAndDropsStatuslessExits() throws {
        let stub = StubWatcher()
        stub.events = [ExitEvent(process: try identity(9).helperIdentity, status: 1 << 8),
                       ExitEvent(process: try identity(4).helperIdentity, status: nil)]
        let watcher = ProcessExitWatcher(driver: stub)
        XCTAssertEqual(watcher.drain(), [try identity(9): 1 << 8], "exits without a shared status leave no entry")
    }

    func testDuplicateNotificationsKeepTheFirstStatus() throws {
        let stub = StubWatcher()
        // Duplicate notifications for one lifetime must not replace its status.
        stub.events = [ExitEvent(process: try identity(9).helperIdentity, status: 1 << 8),
                       ExitEvent(process: try identity(9).helperIdentity, status: 9)]
        let watcher = ProcessExitWatcher(driver: stub)
        XCTAssertEqual(watcher.drain(), [try identity(9): 1 << 8])
    }

    private func identity(_ pid: Int32) throws -> ProcessIdentity {
        try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0)
    }

    func testDifferentLifetimesOfOnePIDKeepSeparateStatuses() throws {
        let old = try identity(9)
        let new = try ProcessIdentity(pid: 9, startSeconds: 2, startMicroseconds: 0)
        let stub = StubWatcher()
        stub.events = [ExitEvent(process: old.helperIdentity, status: 1 << 8),
                       ExitEvent(process: new.helperIdentity, status: 9)]
        XCTAssertEqual(ProcessExitWatcher(driver: stub).drain(), [old: 1 << 8, new: 9])
    }
}
