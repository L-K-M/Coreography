import Foundation

/// One exit of a watched process. `status` is the wait-status word the
/// kernel shared, nil when only the exit itself was observable.
public struct ExitEvent: Equatable, Sendable {
    public let process: HelperProcessIdentity
    public let status: Int32?

    public init(process: HelperProcessIdentity, status: Int32?) {
        self.process = process
        self.status = status
    }
}

public protocol ProcessExitWatching: Sendable {
    /// Replaces the watched identities; reused PIDs require a new registration.
    mutating func watch(_ processes: Set<HelperProcessIdentity>)
    /// Every exit since the last drain.
    func drain() -> [ExitEvent]
}

/// Owns one kqueue; the lock serializes registration and draining. If
/// status access is denied, register for the exit alone instead.
public final class ProcessExitDriver: ProcessExitWatching, @unchecked Sendable {
    #if os(macOS)
    private let queue: Int32
    private let lock = NSLock()
    private static let batchSize = 64
    private var watched: [Int32: HelperProcessIdentity] = [:]
    #endif

    /// Nil where kqueue is unavailable or the platform lacks it.
    public init?() {
        #if os(macOS)
        let queue = kqueue()
        guard queue >= 0 else { return nil }
        self.queue = queue
        #else
        return nil
        #endif
    }

    deinit {
        #if os(macOS)
        Darwin.close(queue)
        #endif
    }

    public func watch(_ processes: Set<HelperProcessIdentity>) {
        #if os(macOS)
        lock.lock()
        defer { lock.unlock() }
        let processes = processes.filter { $0.pid > 0 }
        for process in watched.values.filter({ !processes.contains($0) }) {
            _ = change(process.pid, flags: UInt16(EV_DELETE), notes: 0)
            watched.removeValue(forKey: process.pid)
        }
        for process in processes where watched[process.pid] == nil {
            guard ProcessIdentityCheck.matches(process.pid, process.startSeconds, process.startMicroseconds) else { continue }
            let flags = UInt16(EV_ADD | EV_ONESHOT)
            let result = change(process.pid, flags: flags, notes: UInt32(NOTE_EXIT) | UInt32(NOTE_EXITSTATUS))
            guard result == 0 || (result == EPERM && change(process.pid, flags: flags, notes: UInt32(NOTE_EXIT)) == 0) else { continue }
            // Bracket registration so a reused PID cannot acquire the old identity.
            guard ProcessIdentityCheck.matches(process.pid, process.startSeconds, process.startMicroseconds) else {
                _ = change(process.pid, flags: UInt16(EV_DELETE), notes: 0)
                continue
            }
            watched[process.pid] = process
        }
        #endif
    }

    public func drain() -> [ExitEvent] {
        #if os(macOS)
        lock.lock()
        defer { lock.unlock() }
        var events = [kevent64_s](repeating: .init(), count: Self.batchSize)
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        var found: [ExitEvent] = []
        while true {
            let count = kevent64(queue, nil, 0, &events, Int32(events.count), 0, &timeout)
            guard count > 0 else { return found }
            for event in events.prefix(Int(count)) where event.fflags & UInt32(NOTE_EXIT) != 0 {
                guard let pid = Int32(exactly: event.ident) else { continue }
                guard let process = watched.removeValue(forKey: pid) else { continue }
                let status = event.fflags & UInt32(NOTE_EXITSTATUS) != 0 ? Int32(exactly: event.data) : nil
                found.append(ExitEvent(process: process, status: status))
            }
            if count < Int32(events.count) { return found }
        }
        #else
        return []
        #endif
    }

    #if os(macOS)
    /// Receipts keep registration errors out of the exit event stream.
    private func change(_ pid: Int32, flags: UInt16, notes: UInt32) -> Int32 {
        var event = kevent64_s()
        event.ident = UInt64(pid)
        event.filter = Int16(EVFILT_PROC)
        event.flags = flags | UInt16(EV_RECEIPT)
        event.fflags = notes
        var receipt = kevent64_s()
        let result = kevent64(queue, &event, 1, &receipt, 1, 0, nil)
        guard result == 1 else { return result < 0 ? errno : EIO }
        return Int32(clamping: receipt.data)
    }
    #endif
}
