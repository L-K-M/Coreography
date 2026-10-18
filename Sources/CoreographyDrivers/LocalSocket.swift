import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Who is on the other end of a local socket, as the kernel reports it.
public struct PeerCredentials: Equatable, Sendable {
    public let uid: UInt32
    public let pid: Int32
}

public enum LocalSocketError: Error, Equatable, Sendable {
    case system(String, Int32)
    case pathTooLong
    case closed
    case lineTooLong
}

/// One connected Unix-domain stream carrying newline-delimited UTF-8 lines.
/// Reads wait in short polls, so `close()` from any thread ends them.
public final class LocalSocketConnection: @unchecked Sendable {
    /// A line longer than this is not a protocol message.
    public static let maximumLineBytes = 1 << 20
    fileprivate static let pollMilliseconds: Int32 = 250

    public let peer: PeerCredentials?
    private let descriptor: Int32
    private let lock = NSLock()
    private var buffer = Data()
    private var isClosed = false

    fileprivate init(descriptor: Int32) {
        self.descriptor = descriptor
        peer = Self.credentials(of: descriptor)
    }

    deinit { close() }

    /// The next line without its newline; nil once the peer has closed.
    public func readLine() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try self.readLineBlocking() })
            }
        }
    }

    public func write(_ line: String) throws {
        let data = Data((line + "\n").utf8)
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                if lock.withLock({ isClosed }) { throw LocalSocketError.closed }
                let sent = send(descriptor, raw.baseAddress! + offset, raw.count - offset, Self.sendFlags)
                if sent < 0 {
                    if errno == EINTR { continue }
                    throw LocalSocketError.system("send", errno)
                }
                offset += sent
            }
        }
    }

    public func close() {
        let first = lock.withLock { () -> Bool in
            guard !isClosed else { return false }
            isClosed = true
            return true
        }
        guard first else { return }
        shutdown(descriptor, Int32(SHUT_RDWR))
        _ = systemClose(descriptor)
    }

    private func readLineBlocking() throws -> String? {
        while true {
            if let newline = lock.withLock({ buffer.firstIndex(of: UInt8(ascii: "\n")) }) {
                let line = lock.withLock { () -> Data in
                    let line = buffer[buffer.startIndex..<newline]
                    buffer.removeSubrange(buffer.startIndex...newline)
                    return Data(line)
                }
                return String(decoding: line, as: UTF8.self)
            }
            if lock.withLock({ buffer.count }) > Self.maximumLineBytes { throw LocalSocketError.lineTooLong }
            if lock.withLock({ isClosed }) { return nil }

            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, Self.pollMilliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                throw LocalSocketError.system("poll", errno)
            }
            guard ready > 0 else { continue }

            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            let count = recv(descriptor, &chunk, chunk.count, 0)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                if lock.withLock({ isClosed }) { return nil }
                throw LocalSocketError.system("recv", errno)
            }
            guard count > 0 else { return nil }
            lock.withLock { buffer.append(contentsOf: chunk[0..<count]) }
        }
    }

    /// The kernel's record of the connecting process; nil when unavailable.
    private static func credentials(of descriptor: Int32) -> PeerCredentials? {
        #if os(macOS)
        var credentials = xucred()
        var length = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERCRED, &credentials, &length) == 0 else { return nil }
        var pid: pid_t = 0
        var pidLength = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidLength) == 0 else { return nil }
        return PeerCredentials(uid: credentials.cr_uid, pid: pid)
        #elseif canImport(Glibc)
        // struct ucred needs _GNU_SOURCE, which Swift does not see; same layout.
        struct LinuxCredentials { var pid: Int32 = 0; var uid: UInt32 = 0; var gid: UInt32 = 0 }
        var credentials = LinuxCredentials()
        var length = socklen_t(MemoryLayout<LinuxCredentials>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_PEERCRED, &credentials, &length) == 0 else { return nil }
        return PeerCredentials(uid: credentials.uid, pid: credentials.pid)
        #else
        return nil
        #endif
    }

    #if os(macOS)
    // A closed peer must fail the send, not raise SIGPIPE in the app.
    private static let sendFlags: Int32 = 0
    #else
    private static let sendFlags = Int32(MSG_NOSIGNAL)
    #endif
}

/// A listening Unix-domain socket whose file only this user can open.
public final class LocalSocketListener: @unchecked Sendable {
    private static let backlog: Int32 = 8
    private static let filePermissions: mode_t = 0o600
    private let descriptor: Int32
    private let path: String
    private let lock = NSLock()
    private var isClosed = false

    /// Replaces a stale socket file left by an earlier run.
    public init(path: String) throws {
        self.path = path
        descriptor = try LocalSocketAddress.socketDescriptor()
        #if os(macOS)
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        #endif
        unlink(path)
        do {
            try LocalSocketAddress.with(path) { address, length in
                guard bind(descriptor, address, length) == 0 else { throw LocalSocketError.system("bind", errno) }
            }
            guard chmod(path, Self.filePermissions) == 0 else { throw LocalSocketError.system("chmod", errno) }
            guard listen(descriptor, Self.backlog) == 0 else { throw LocalSocketError.system("listen", errno) }
        } catch {
            _ = systemClose(descriptor)
            unlink(path)
            throw error
        }
    }

    deinit { close() }

    /// Waits for the next connection; throws `closed` once the listener closes.
    public func accept() async throws -> LocalSocketConnection {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try self.acceptBlocking() })
            }
        }
    }

    public func close() {
        let first = lock.withLock { () -> Bool in
            guard !isClosed else { return false }
            isClosed = true
            return true
        }
        guard first else { return }
        _ = systemClose(descriptor)
        unlink(path)
    }

    private func acceptBlocking() throws -> LocalSocketConnection {
        while true {
            if lock.withLock({ isClosed }) { throw LocalSocketError.closed }
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, LocalSocketConnection.pollMilliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                if lock.withLock({ isClosed }) { throw LocalSocketError.closed }
                throw LocalSocketError.system("poll", errno)
            }
            guard ready > 0 else { continue }
            #if os(macOS)
            let client = Darwin.accept(descriptor, nil, nil)
            #else
            let client = Glibc.accept(descriptor, nil, nil)
            #endif
            if client < 0 {
                if errno == EINTR || errno == EAGAIN || errno == ECONNABORTED { continue }
                if lock.withLock({ isClosed }) { throw LocalSocketError.closed }
                throw LocalSocketError.system("accept", errno)
            }
            #if os(macOS)
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            #endif
            return LocalSocketConnection(descriptor: client)
        }
    }
}

public enum LocalSocketClient {
    public static func connect(path: String) throws -> LocalSocketConnection {
        let descriptor = try LocalSocketAddress.socketDescriptor()
        #if os(macOS)
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        #endif
        do {
            try LocalSocketAddress.with(path) { address, length in
                #if os(macOS)
                let result = Darwin.connect(descriptor, address, length)
                #else
                let result = Glibc.connect(descriptor, address, length)
                #endif
                guard result == 0 else { throw LocalSocketError.system("connect", errno) }
            }
        } catch {
            _ = systemClose(descriptor)
            throw error
        }
        return LocalSocketConnection(descriptor: descriptor)
    }
}

private enum LocalSocketAddress {
    static func socketDescriptor() throws -> Int32 {
        #if os(macOS)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        #else
        let descriptor = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard descriptor >= 0 else { throw LocalSocketError.system("socket", errno) }
        return descriptor
    }

    static func with<Result>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result) throws -> Result {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw LocalSocketError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}

private func systemClose(_ descriptor: Int32) -> Int32 {
    #if os(macOS)
    Darwin.close(descriptor)
    #else
    Glibc.close(descriptor)
    #endif
}
