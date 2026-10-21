import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class HelperDescriptorTests: XCTestCase {
    private static let team = "AB12CD34EF"

    func testHandlerReadsEachProcessOnceAndRefusesBadBatches() async throws {
        let one = HelperProcessIdentity(pid: 11, startSeconds: 1, startMicroseconds: 0)
        let gone = HelperProcessIdentity(pid: 12, startSeconds: 1, startMicroseconds: 0)
        let reads = Reads()
        let handler = HelperRequestHandler(
            readFiles: { await reads.record($0); return $0 == one ? RawProcessFiles(paths: ["/Users/other/a"], truncated: false) : nil },
            readSockets: { $0 == one ? Self.listening : nil }
        )

        let files = try HelperWire.decode(
            HelperReply.self, from: await handler.reply(to: HelperWire.encode(HelperRequest.openFiles(processes: [one, gone, one])))
        )
        XCTAssertEqual(files, .openFiles([HelperProcessFiles(process: one, files: RawProcessFiles(paths: ["/Users/other/a"], truncated: false))]))
        let read = await reads.processes
        XCTAssertEqual(read, [one, gone], "each process once, an unreadable one left out")

        let sockets = try HelperWire.decode(
            HelperReply.self, from: await handler.reply(to: HelperWire.encode(HelperRequest.sockets(processes: [one])))
        )
        XCTAssertEqual(sockets, .sockets([HelperProcessSockets(process: one, sockets: Self.listening)]))

        let tooMany = (1...Int32(HelperWire.maximumDescriptorProcesses + 1)).map {
            HelperProcessIdentity(pid: $0, startSeconds: 1, startMicroseconds: 0)
        }
        let cases: [([HelperProcessIdentity], String)] = [
            ([HelperProcessIdentity(pid: 0, startSeconds: 1, startMicroseconds: 0)], "A process ID must be positive."),
            (tooMany, "At most \(HelperWire.maximumDescriptorProcesses) processes per request.")
        ]
        for (processes, reason) in cases {
            for request in [HelperRequest.openFiles(processes: processes), .sockets(processes: processes)] {
                let reply = try HelperWire.decode(HelperReply.self, from: await handler.reply(to: HelperWire.encode(request)))
                XCTAssertEqual(reply, .refused(reason), "\(request)".prefix(40).description)
            }
        }
    }

    func testAReplyTooLargeKeepsTheProcessesThatFit() async throws {
        // 512 paths near PATH_MAX per process: 16 of them pass the reply limit.
        let long = String(repeating: "x", count: 1023)
        let handler = HelperRequestHandler(readFiles: { _ in RawProcessFiles(paths: Array(repeating: long, count: 512), truncated: false) })
        let processes = (1...Int32(HelperWire.maximumDescriptorProcesses)).map {
            HelperProcessIdentity(pid: $0, startSeconds: 1, startMicroseconds: 0)
        }

        let message = await handler.reply(to: HelperWire.encode(HelperRequest.openFiles(processes: processes)))
        XCTAssertLessThanOrEqual(message.count, HelperReply.maximumBytes)
        guard case .openFiles(let kept) = try HelperWire.decode(HelperReply.self, from: message) else { return XCTFail("files expected") }
        XCTAssertFalse(kept.isEmpty)
        XCTAssertLessThan(kept.count, processes.count)
        XCTAssertEqual(kept.map(\.process), Array(processes.prefix(kept.count)), "the first ones are kept")
    }

    func testAFullCounterRequestFitsTheRequestLimit() {
        let pids = [Int32](repeating: .max, count: HelperWire.maximumPIDs)
        XCTAssertLessThanOrEqual(
            HelperWire.encode(HelperRequest.processCounters(pids: pids)).count, HelperRequest.maximumBytes,
            "a full list must fit, or a current helper would refuse every fill"
        )
    }

    func testLargeListsGoInBatchesTheHelperAccepts() async {
        let transport = Recording()
        let helper = PrivilegedHelper(registration: Enabled(), transport: transport, teamID: Self.team)
        let processes = (0...40).map { HelperProcessIdentity(pid: $0, startSeconds: 1, startMicroseconds: 0) }

        let read = await helper.sockets(of: processes)
        XCTAssertEqual(read?.count, 40, "every process but the kernel")
        let batches = await transport.batchSizes
        XCTAssertEqual(batches, [16, 16, 8])
    }

    func testMonitorsFillOtherUsersProcessesFromTheHelper() async throws {
        let snapshot = try Self.processes([10, 11])
        let helper = PrivilegedHelper(registration: Enabled(), transport: Recording(), teamID: Self.team)

        let files = await OpenFileMonitor(driver: OwnFilesOnly(), helper: helper).sample(snapshot)
        XCTAssertEqual(files.files[snapshot.processes[0].id], ["/Users/me/a"], "the app's own read is kept; the helper only fills gaps")
        XCTAssertEqual(files.files[snapshot.processes[1].id], ["/helper/11"])
        XCTAssertEqual(files.restrictedProcesses, 0)
        let inspected = await OpenFileMonitor(driver: OwnFilesOnly(), helper: helper).files(of: snapshot.processes[1])
        XCTAssertEqual(inspected?.paths, ["/helper/11"])

        let connections = await ConnectionMonitor(driver: OwnSocketsOnly(), helper: helper).sample(snapshot)
        XCTAssertEqual(connections.listeningProcesses, [snapshot.processes[1].id])
        XCTAssertEqual(connections.restrictedProcesses, 0)

        let withoutHelper = await OpenFileMonitor(driver: OwnFilesOnly()).sample(snapshot)
        XCTAssertEqual(withoutHelper.restrictedProcesses, 1, "still counted when no helper reads it")
    }

    private static let listening = RawProcessSockets(sockets: [RawSocket(
        descriptor: 4, transport: .tcp, tcpState: 1, localAddress: "127.0.0.1", localPort: 8080, remoteAddress: "", remotePort: 0
    )], truncated: false)

    private static func processes(_ pids: [Int32]) throws -> ProcessSnapshot {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date())
        let rows = try pids.map { pid in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: pid == 10 ? 501 : 502,
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

private actor Reads {
    private(set) var processes: [HelperProcessIdentity] = []
    func record(_ process: HelperProcessIdentity) { processes.append(process) }
}

/// A helper that reads every process it is asked about, recording batch sizes.
private actor Recording: HelperTransport {
    private(set) var batchSizes: [Int] = []

    func exchange(_ message: Data) async throws -> Data {
        let request = try HelperWire.decode(HelperRequest.self, from: message)
        switch request {
        case .openFiles(let processes):
            batchSizes.append(processes.count)
            return HelperWire.encode(HelperReply.openFiles(processes.map {
                HelperProcessFiles(process: $0, files: RawProcessFiles(paths: ["/helper/\($0.pid)"], truncated: false))
            }))
        case .sockets(let processes):
            batchSizes.append(processes.count)
            return HelperWire.encode(HelperReply.sockets(processes.map {
                HelperProcessSockets(process: $0, sockets: RawProcessSockets(sockets: [RawSocket(
                    descriptor: 3, transport: .tcp, tcpState: 1, localAddress: "0.0.0.0", localPort: 22, remoteAddress: "", remotePort: 0
                )], truncated: false))
            }))
        default:
            return HelperWire.encode(HelperReply.refused("unexpected"))
        }
    }
}

private struct Enabled: HelperRegistering {
    func status() -> HelperRegistrationStatus { .enabled }
    func register() throws {}
    func unregister() async throws {}
    func openApprovalSettings() {}
}

/// PID 10 is the person's own; any other belongs to another user.
private struct OwnFilesOnly: ProcessFileReading {
    func files(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<RawProcessFiles, DescriptorReadError> {
        pid == 10 ? .success(RawProcessFiles(paths: ["/Users/me/a"], truncated: false)) : .failure(.notPermitted)
    }
}

private struct OwnSocketsOnly: ProcessSocketReading {
    func sockets(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<RawProcessSockets, SocketReadError> {
        pid == 10 ? .success(RawProcessSockets(sockets: [], truncated: false)) : .failure(.notPermitted)
    }
}
