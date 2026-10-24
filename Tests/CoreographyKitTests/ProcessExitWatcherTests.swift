import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class ProcessExitWatcherTests: XCTestCase {
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
