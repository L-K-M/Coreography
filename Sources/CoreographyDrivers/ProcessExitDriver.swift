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

/// Owns one kqueue; the lock serializes registration and draining. If
/// status access is denied, register for the exit alone instead.
public final class ProcessExitDriver: ProcessExitWatching, @unchecked Sendable {
    #if os(macOS)
    private let queue: Int32
    private let lock = NSLock()
    private static let batchSize = 64
    private var watched: Set<Int32> = []
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

    public func watch(_ pids: Set<Int32>) {
        #if os(macOS)
        lock.lock()
        defer { lock.unlock() }
        let pids = pids.filter { $0 > 0 }
        for pid in watched.subtracting(pids) {
            _ = change(pid, flags: UInt16(EV_DELETE), notes: 0)
            watched.remove(pid)
        }
        for pid in pids.subtracting(watched) {
            let flags = UInt16(EV_ADD | EV_ONESHOT)
            let result = change(pid, flags: flags, notes: UInt32(NOTE_EXIT) | UInt32(NOTE_EXITSTATUS))
            if result == 0 || (result == EPERM && change(pid, flags: flags, notes: UInt32(NOTE_EXIT)) == 0) {
                watched.insert(pid)
            }
        }
        #endif
    }

    public func drain() -> [ExitEvent] {
        #if os(macOS)
        lock.lock()
        defer { lock.unlock() }
        var events: [Darwin.kevent] = .init(repeating: .init(), count: Self.batchSize)
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        var found: [ExitEvent] = []
        while true {
            let count = Darwin.kevent(queue, nil, 0, &events, Int32(events.count), &timeout)
            guard count > 0 else { return found }
            for event in events.prefix(Int(count)) where event.fflags & UInt32(NOTE_EXIT) != 0 {
                guard let pid = Int32(exactly: event.ident) else { continue }
                watched.remove(pid)
                let status = event.fflags & UInt32(NOTE_EXITSTATUS) != 0 ? Int32(exactly: event.data) : nil
                found.append(ExitEvent(pid: pid, status: status))
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
        var event = Darwin.kevent(
            ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: flags | UInt16(EV_RECEIPT),
            fflags: notes, data: 0, udata: nil
        )
        var receipt = Darwin.kevent()
        let result = Darwin.kevent(queue, &event, 1, &receipt, 1, nil)
        guard result == 1 else { return result < 0 ? errno : EIO }
        return Int32(clamping: receipt.data)
    }
    #endif
}
