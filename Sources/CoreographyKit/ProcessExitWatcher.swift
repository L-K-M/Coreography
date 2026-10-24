import Foundation
import CoreographyDrivers

/// Exit statuses retain the identity registered with the kernel, so a
/// later process reusing its PID cannot inherit them. Drain before watching
/// the next sample; statuses are available only with signalling rights.
public struct ProcessExitWatcher: Sendable {
    private var driver: any ProcessExitWatching

    /// Nil where the kqueue driver is unavailable.
    public init?() {
        guard let driver = ProcessExitDriver() else { return nil }
        self.driver = driver
    }

    init(driver: any ProcessExitWatching) { self.driver = driver }

    public mutating func watch(_ processes: Set<ProcessIdentity>) {
        driver.watch(Set(processes.map(\.helperIdentity)))
    }

    /// Exits since the last call as identity → wait status; an exited process without
    /// an entry means the kernel shared only the exit itself.
    public func drain() -> [ProcessIdentity: Int32] {
        Dictionary(driver.drain().compactMap { event -> (ProcessIdentity, Int32)? in
            guard let status = event.status,
                  let identity = try? ProcessIdentity(
                    pid: event.process.pid, startSeconds: event.process.startSeconds,
                    startMicroseconds: event.process.startMicroseconds
                  ) else { return nil }
            return (identity, status)
        }) { first, _ in first }
    }
}
