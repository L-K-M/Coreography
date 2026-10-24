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

        driver.watch([child.processIdentifier])
        try input.fileHandleForWriting.write(contentsOf: Data("finish\n".utf8))
        child.waitUntilExit()
        let deadline = Date().addingTimeInterval(5)
        var events: [ExitEvent] = []
        repeat {
            events += driver.drain()
            if !events.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < deadline
        XCTAssertEqual(events, [ExitEvent(pid: child.processIdentifier, status: 42 << 8)])
        XCTAssertTrue(driver.drain().isEmpty, "each exit is delivered once")
    }
    #endif

    private final class StubWatcher: ProcessExitWatching, @unchecked Sendable {
        var watched: Set<Int32> = []
        var events: [ExitEvent] = []
        func watch(_ pids: Set<Int32>) { watched = pids }
        func drain() -> [ExitEvent] { defer { events = [] }; return events }
    }

    func testWatchReplacesTheWatchedSet() {
        let stub = StubWatcher()
        var watcher = ProcessExitWatcher(driver: stub)
        watcher.watch([1, 2])
        XCTAssertEqual(stub.watched, [1, 2])
        watcher.watch([2, 3])
        XCTAssertEqual(stub.watched, [2, 3])
    }

    func testDrainReturnsStatusesAndDropsStatuslessExits() {
        let stub = StubWatcher()
        stub.events = [ExitEvent(pid: 9, status: 1 << 8), ExitEvent(pid: 4, status: nil)]
        let watcher = ProcessExitWatcher(driver: stub)
        XCTAssertEqual(watcher.drain(), [9: 1 << 8], "exits without a shared status leave no entry")
    }

    func testAReusedPidKeepsTheEarlierExitsStatus() {
        let stub = StubWatcher()
        // pid 9 exited twice between drains; the first status is the ghost's.
        stub.events = [ExitEvent(pid: 9, status: 1 << 8), ExitEvent(pid: 9, status: 9)]
        let watcher = ProcessExitWatcher(driver: stub)
        XCTAssertEqual(watcher.drain(), [9: 1 << 8])
    }
}
