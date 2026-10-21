import Foundation
import CoreographyDrivers

public enum ConnectionTransport: String, Codable, Sendable {
    case tcp, udp
}

/// TCP states, numbered as the kernel reports them.
public enum TCPState: Int32, Codable, CaseIterable, Sendable {
    case closed = 0
    case listen = 1
    case synSent = 2
    case synReceived = 3
    case established = 4
    case closeWait = 5
    case finWait1 = 6
    case closing = 7
    case lastAck = 8
    case finWait2 = 9
    case timeWait = 10
}

public struct ConnectionEndpoint: Codable, Hashable, Sendable {
    public let address: String
    public let port: UInt16
}

/// One internet socket of one observed process.
public struct ConnectionReading: Codable, Hashable, Identifiable, Sendable {
    public let process: ProcessIdentity
    public let processName: String
    public let descriptor: Int32
    public let transport: ConnectionTransport
    /// nil for UDP, or for a TCP state number this build does not know.
    public let state: TCPState?
    public let local: ConnectionEndpoint
    /// nil when the socket has no peer.
    public let remote: ConnectionEndpoint?

    public var id: String { "\(process.pid).\(process.startSeconds).\(process.startMicroseconds).\(descriptor)" }

    /// Accepting connections (TCP listen) or receiving on a bound port
    /// with no peer (UDP).
    public var isListening: Bool {
        switch transport {
        case .tcp: state == .listen
        case .udp: remote == nil && local.port != 0
        }
    }
}

/// Every readable process's internet sockets at one moment, with what
/// could not be read named rather than dropped.
public struct ConnectionSnapshot: Codable, Sendable {
    public let takenAt: Date
    public let connections: [ConnectionReading]
    /// Processes of other users; reading their sockets needs the helper.
    public let restrictedProcesses: Int
    /// Processes that held more sockets than one read keeps.
    public let truncatedProcesses: Int
    /// Processes whose read failed for another reason.
    public let failedProcesses: Int
    /// Why nothing could be read at all, e.g. off macOS.
    public let unavailableReason: String?

    public var listeningProcesses: Set<ProcessIdentity> {
        Set(connections.filter(\.isListening).map(\.process))
    }
}

/// Reads sockets per observed process, on request rather than every tick:
/// the window asks only while connections are shown or filtered on.
public actor ConnectionMonitor {
    private let driver: any ProcessSocketReading
    /// Reads other users' processes, when installed.
    private let helper: PrivilegedHelper?

    public init() { self.init(driver: ProcessSocketDriver(), helper: .shared) }

    init(driver: any ProcessSocketReading, helper: PrivilegedHelper? = nil) {
        self.driver = driver
        self.helper = helper
    }

    public func sample(_ processes: ProcessSnapshot, at time: Date = Date()) async -> ConnectionSnapshot {
        var connections: [ConnectionReading] = []
        var restricted: [ProcessReading] = []
        var truncated = 0
        var failed = 0
        // PID 0 is the kernel; it holds no user sockets to read.
        for process in processes.processes where process.id.pid > 0 {
            let result = await driver.sockets(
                pid: process.id.pid, startSeconds: process.id.startSeconds, startMicroseconds: process.id.startMicroseconds
            )
            switch result {
            case .success(let read):
                connections += read.sockets.map { Self.reading($0, of: process) }
                if read.truncated { truncated += 1 }
            case .failure(.notPermitted):
                restricted.append(process)
            case .failure(.exited):
                continue
            case .failure(.unsupportedPlatform):
                return ConnectionSnapshot(
                    takenAt: time, connections: [], restrictedProcesses: 0, truncatedProcesses: 0,
                    failedProcesses: 0, unavailableReason: "Connections need macOS"
                )
            case .failure(.systemCall):
                failed += 1
            }
        }
        var asked = Dictionary(restricted.map { ($0.id.helperIdentity, $0) }, uniquingKeysWith: { first, _ in first })
        var filled = 0
        for read in await helper?.sockets(of: restricted.map(\.id.helperIdentity)) ?? [] {
            guard let process = asked.removeValue(forKey: read.process) else { continue }
            connections += read.sockets.sockets.map { Self.reading($0, of: process) }
            if read.sockets.truncated { truncated += 1 }
            filled += 1
        }
        return ConnectionSnapshot(
            takenAt: time, connections: connections, restrictedProcesses: restricted.count - filled,
            truncatedProcesses: truncated, failedProcesses: failed, unavailableReason: nil
        )
    }

    /// One process's sockets, for the inspector; nil when they cannot be read.
    public func connections(of process: ProcessReading) async -> [ConnectionReading]? {
        let result = await driver.sockets(
            pid: process.id.pid, startSeconds: process.id.startSeconds, startMicroseconds: process.id.startMicroseconds
        )
        switch result {
        case .success(let read):
            return read.sockets.map { Self.reading($0, of: process) }
        case .failure(.notPermitted):
            guard let read = await helper?.sockets(of: [process.id.helperIdentity])?.first?.sockets else { return nil }
            return read.sockets.map { Self.reading($0, of: process) }
        case .failure:
            return nil
        }
    }

    private static func reading(_ socket: RawSocket, of process: ProcessReading) -> ConnectionReading {
        ConnectionReading(
            process: process.id, processName: process.name, descriptor: socket.descriptor,
            transport: socket.transport == .tcp ? .tcp : .udp,
            state: socket.tcpState.flatMap(TCPState.init(rawValue:)),
            local: ConnectionEndpoint(address: socket.localAddress, port: socket.localPort),
            remote: socket.remotePort == 0 ? nil : ConnectionEndpoint(address: socket.remoteAddress, port: socket.remotePort)
        )
    }
}
