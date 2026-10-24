import Foundation
import CoreographyDrivers

/// Watches every observed pid for exits on one kqueue: a pid's exit status
/// reaches `drain` only when the process was already watched, so the caller
/// drains first, then watches the new sample's set. A wait status arrives
/// only where the watcher may signal the process; the same pid reused and
/// exited again keeps the earlier exit's status, which belongs to the ghost
/// the status joins.
public struct ProcessExitWatcher: Sendable {
    private var driver: any ProcessExitWatching

    /// Nil where the kqueue driver is unavailable.
    public init?() {
        guard let driver = ProcessExitDriver() else { return nil }
        self.driver = driver
    }

    init(driver: any ProcessExitWatching) { self.driver = driver }

    public mutating func watch(_ pids: Set<Int32>) { driver.watch(pids) }

    /// Exits since the last call as pid → wait status; an exited pid without
    /// an entry means the kernel shared only the exit itself.
    public func drain() -> [Int32: Int32] {
        Dictionary(driver.drain().compactMap { event in event.status.map { (event.pid, $0) } }) { first, _ in first }
    }
}
