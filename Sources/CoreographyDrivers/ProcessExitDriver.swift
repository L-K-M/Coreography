import Foundation

/// One exit of a watched process. `status` is the wait-status word the
/// kernel shared, nil when only the exit itself was observable.
public struct ExitEvent: Equatable, Sendable {
    public let pid: Int32
    public let status: Int32?

    public init(pid: Int32, status: Int32?) {
        self.pid = pid
        self.status = status
    }
}

public protocol ProcessExitWatching: Sendable {
    /// Replaces the watched set; a pid reports nothing until it is watched.
    mutating func watch(_ pids: Set<Int32>)
    /// Every exit since the last drain.
    func drain() -> [ExitEvent]
}

/// All observed pids on one kqueue. `NOTE_EXIT` on any pid needs no
/// privilege; the kernel adds `NOTE_EXITSTATUS` with the wait-status word
/// only where the same rights as signalling hold (the same user, the
/// parent, or root), so other users' exits still arrive without a status.
public struct ProcessExitDriver: ProcessExitWatching {
    #if os(macOS)
    private let queue: Int32
    #endif
    private var watched: Set<Int32> = []

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

    public mutating func watch(_ pids: Set<Int32>) {
        #if os(macOS)
        var changes = watched.subtracting(pids).map {
            kevent(ident: UInt($0), filter: Int16(EVFILT_PROC), flags: UInt16(EV_DELETE), fflags: 0, data: 0, udata: nil)
        }
        changes += pids.subtracting(watched).map {
            kevent(ident: UInt($0), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD),
                   fflags: UInt32(NOTE_EXIT | NOTE_EXITSTATUS), data: 0, udata: nil)
        }
        watched = pids
        guard !changes.isEmpty else { return }
        changes.withUnsafeBufferPointer { kevent(queue, $0.baseAddress, Int32($0.count), nil, 0, nil) }
        // An add can fail for a pid that already exited; the next sample
        // leaves it out, and the failed note is never retried.
        #else
        watched = pids
        #endif
    }

    public func drain() -> [ExitEvent] {
        #if os(macOS)
        var events = [kevent](repeating: kevent(), count: 64)
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        var found: [ExitEvent] = []
        while true {
            let count = kevent(queue, nil, 0, &events, Int32(events.count), &timeout)
            guard count > 0 else { return found }
            found += events[..<Int(count)].map {
                ExitEvent(pid: Int32($0.ident), status: $0.fflags & UInt32(NOTE_EXITSTATUS) != 0 ? Int32($0.data) : nil)
            }
            if count < Int32(events.count) { return found }
        }
        #else
        return []
        #endif
    }
}
