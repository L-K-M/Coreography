import Foundation

#if os(macOS)
import Darwin
import CoreographySystem
#elseif canImport(Glibc)
import Glibc
#endif

public enum SocketTransport: String, Codable, Sendable {
    case tcp, udp
}

/// One internet socket as the kernel described it.
public struct RawSocket: Codable, Equatable, Sendable {
    public let descriptor: Int32
    public let transport: SocketTransport
    /// xnu `TSI_S_*` numbering; nil for UDP.
    public let tcpState: Int32?
    public let localAddress: String
    public let localPort: UInt16
    /// Empty with port 0 when the socket has no peer.
    public let remoteAddress: String
    public let remotePort: UInt16

    public init(
        descriptor: Int32, transport: SocketTransport, tcpState: Int32?,
        localAddress: String, localPort: UInt16, remoteAddress: String, remotePort: UInt16
    ) {
        self.descriptor = descriptor
        self.transport = transport
        self.tcpState = tcpState
        self.localAddress = localAddress
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
    }
}

public struct RawProcessSockets: Codable, Equatable, Sendable {
    public let sockets: [RawSocket]
    /// The process held more internet sockets than one read keeps.
    public let truncated: Bool

    public init(sockets: [RawSocket], truncated: Bool) {
        self.sockets = sockets
        self.truncated = truncated
    }
}

public enum SocketReadError: Error, Equatable, Sendable {
    case unsupportedPlatform
    /// Gone, or the pid now names another process.
    case exited
    /// Another user's process; reading it needs the helper.
    case notPermitted
    case systemCall(code: Int32)
}

public protocol ProcessSocketReading: Sendable {
    func sockets(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<RawProcessSockets, SocketReadError>
}

/// Reads one process's TCP and UDP sockets through libproc, only for the
/// exact process identity the caller saw.
public actor ProcessSocketDriver: ProcessSocketReading {
    /// Enough for busy servers; more are reported as truncated.
    private static let capacity = 512
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.socket-sampling")
    #if os(macOS)
    // Reused across reads: a pass over every process would otherwise allocate per process.
    private var buffer = [coreo_socket_sample](repeating: coreo_socket_sample(), count: ProcessSocketDriver.capacity)
    #endif

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func sockets(
        pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64
    ) -> Result<RawProcessSockets, SocketReadError> {
        #if os(macOS)
        var count: Int32 = 0
        var truncated: Int32 = 0
        let status = buffer.withUnsafeMutableBufferPointer {
            coreo_process_sockets(
                pid, startSeconds, startMicroseconds, $0.baseAddress, Int32(Self.capacity), &count, &truncated
            )
        }
        guard status == 0 else { return .failure(Self.error(status)) }
        return .success(RawProcessSockets(
            sockets: buffer.prefix(Int(count)).compactMap(Self.socket), truncated: truncated != 0
        ))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    private static func socket(_ sample: coreo_socket_sample) -> RawSocket? {
        let transport: SocketTransport
        switch sample.kind {
        case Int32(COREO_SOCKET_TCP): transport = .tcp
        case Int32(COREO_SOCKET_UDP): transport = .udp
        default: return nil
        }
        let local = withUnsafeBytes(of: sample.local_address) { Array($0) }
        let remote = withUnsafeBytes(of: sample.remote_address) { Array($0) }
        let connected = sample.remote_port != 0
        return RawSocket(
            descriptor: sample.fd, transport: transport,
            tcpState: transport == .tcp ? sample.tcp_state : nil,
            localAddress: SocketAddressText.format(local, ipVersion: sample.ip_version) ?? "",
            localPort: sample.local_port,
            remoteAddress: connected ? SocketAddressText.format(remote, ipVersion: sample.ip_version) ?? "" : "",
            remotePort: sample.remote_port
        )
    }

    private static func error(_ code: Int32) -> SocketReadError {
        switch code {
        case ESRCH, EAGAIN: .exited
        case EPERM, EACCES: .notPermitted
        case ENOTSUP: .unsupportedPlatform
        default: .systemCall(code: code)
        }
    }
    #endif
}

/// Numeric address text, as `inet_ntop` writes it: `127.0.0.1`, `::1`.
public enum SocketAddressText {
    private static let ipv4Length = 4
    private static let ipv6Length = 16

    /// IPv4 uses the first four bytes; nil for other versions or short input.
    public static func format(_ bytes: [UInt8], ipVersion: Int32) -> String? {
        let family: Int32
        let length: Int
        switch ipVersion {
        case 4: (family, length) = (AF_INET, ipv4Length)
        case 6: (family, length) = (AF_INET6, ipv6Length)
        default: return nil
        }
        guard bytes.count >= length else { return nil }
        var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let written = bytes.withUnsafeBytes { raw in
            inet_ntop(family, raw.baseAddress, &text, socklen_t(text.count))
        }
        guard written != nil else { return nil }
        return String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
