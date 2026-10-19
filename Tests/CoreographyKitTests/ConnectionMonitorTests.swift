import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class ConnectionMonitorTests: XCTestCase {
    func testReadsSocketsPerProcessAndCountsWhatItCannotRead() async throws {
        let monitor = ConnectionMonitor(driver: Sockets())
        let snapshot = await monitor.sample(try processes([0, 10, 11, 12, 13, 14]))

        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(snapshot.restrictedProcesses, 1)
        XCTAssertEqual(snapshot.truncatedProcesses, 1)
        XCTAssertEqual(snapshot.failedProcesses, 1)
        XCTAssertEqual(snapshot.connections.map(\.process.pid), [10, 10, 10, 14], "the kernel and exited processes are skipped")

        let listener = try XCTUnwrap(snapshot.connections.first)
        XCTAssertEqual(listener.state, .listen)
        XCTAssertTrue(listener.isListening)
        XCTAssertNil(listener.remote)
        XCTAssertFalse(snapshot.connections[1].isListening, "an established socket has a peer")
        XCTAssertEqual(snapshot.connections[1].remote, ConnectionEndpoint(address: "::1", port: 443))
        XCTAssertTrue(snapshot.connections[2].isListening, "a bound UDP socket without a peer receives")
        XCTAssertNil(snapshot.connections[2].state)
        XCTAssertEqual(snapshot.listeningProcesses.map(\.pid), [10])
    }

    func testUnsupportedPlatformsReportWhyRatherThanEmptyData() async throws {
        let snapshot = await ConnectionMonitor(driver: Unsupported()).sample(try processes([10, 11]))
        XCTAssertEqual(snapshot.unavailableReason, "Connections need macOS")
        XCTAssertTrue(snapshot.connections.isEmpty)
    }

    func testAddressTextMatchesInetNtop() {
        XCTAssertEqual(SocketAddressText.format([127, 0, 0, 1], ipVersion: 4), "127.0.0.1")
        XCTAssertEqual(SocketAddressText.format([127, 0, 0, 1] + Array(repeating: 0, count: 12), ipVersion: 4), "127.0.0.1")
        XCTAssertEqual(SocketAddressText.format(Array(repeating: 0, count: 15) + [1], ipVersion: 6), "::1")
        XCTAssertNil(SocketAddressText.format([1, 2], ipVersion: 4))
        XCTAssertNil(SocketAddressText.format([1, 2, 3, 4], ipVersion: 5))
    }

    private func processes(_ pids: [Int32]) throws -> ProcessSnapshot {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date())
        let rows = try pids.map { pid in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501,
                name: "P\(pid)", stamp: stamp, cpuPercentOfMachine: try .measured(0), memoryFootprintBytes: try .measured(1),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(rows.count)), enumerationTruncated: false,
            processes: rows, issues: [], continuity: .continuous
        )
    }
}

/// 10 serves, 11 belongs to another user, 12 exited, 13 fails, 14 holds too many sockets.
private struct Sockets: ProcessSocketReading {
    func sockets(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<RawProcessSockets, SocketReadError> {
        switch pid {
        case 0: XCTFail("the kernel is never read"); return .failure(.notPermitted)
        case 10:
            return .success(RawProcessSockets(sockets: [
                RawSocket(descriptor: 3, transport: .tcp, tcpState: 1, localAddress: "0.0.0.0", localPort: 22, remoteAddress: "", remotePort: 0),
                RawSocket(descriptor: 4, transport: .tcp, tcpState: 4, localAddress: "::1", localPort: 50000, remoteAddress: "::1", remotePort: 443),
                RawSocket(descriptor: 5, transport: .udp, tcpState: nil, localAddress: "0.0.0.0", localPort: 5353, remoteAddress: "", remotePort: 0)
            ], truncated: false))
        case 11: return .failure(.notPermitted)
        case 12: return .failure(.exited)
        case 13: return .failure(.systemCall(code: 5))
        default:
            return .success(RawProcessSockets(sockets: [
                RawSocket(descriptor: 6, transport: .tcp, tcpState: 4, localAddress: "10.0.0.2", localPort: 50001, remoteAddress: "1.1.1.1", remotePort: 853)
            ], truncated: true))
        }
    }
}

private struct Unsupported: ProcessSocketReading {
    func sockets(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<RawProcessSockets, SocketReadError> {
        .failure(.unsupportedPlatform)
    }
}
