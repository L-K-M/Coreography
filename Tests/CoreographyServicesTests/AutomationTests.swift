import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class AutomationTests: XCTestCase {
    private let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date(timeIntervalSince1970: 1_700_000_000))

    func testLinksMapToNavigationCommandsOnly() throws {
        let cases: [(String, AutomationCommand)] = [
            ("coreography://", .show),
            ("coreography://show", .show),
            ("COREOGRAPHY://Show", .show),
            ("coreography://filter?q=cpu:%3E10%20safari", .filter("cpu:>10 safari")),
            ("coreography://find?port=443", .filter("port:443")),
            ("coreography://find?file=~/Downloads", .filter("file:~/Downloads")),
            ("coreography://process?pid=412", .selectProcess(pid: 412)),
            ("coreography://range?seconds=3600", .range(.hour)),
            ("coreography://record/start?name=Build", .startRecording(name: "Build")),
            ("coreography://record/start", .startRecording(name: "")),
            ("coreography://record/stop", .stopRecording),
            ("coreography://hud/toggle", .toggleHUD)
        ]
        for (text, expected) in cases {
            XCTAssertEqual(AutomationLink.command(from: try XCTUnwrap(URL(string: text))), .success(expected), text)
        }
    }

    func testInvalidLinksAreRefusedWithAReason() throws {
        let refused: [(String, AutomationLinkError)] = [
            ("https://show", .wrongScheme),
            ("coreography://quit?pid=1", .unknownCommand("quit")),
            ("coreography://process/kill?pid=1", .unknownCommand("process/kill")),
            ("coreography://find?port=0", .invalidArgument("port must be 1-65535")),
            ("coreography://find?port=70000", .invalidArgument("port must be 1-65535")),
            ("coreography://find", .invalidArgument("find needs port= or file=")),
            ("coreography://find?file=My%20Files", .invalidArgument("file cannot contain spaces; use part of the name")),
            ("coreography://process?pid=abc", .invalidArgument("process needs pid=<number>")),
            ("coreography://filter?q=a%0Ab", .invalidArgument("q contains control characters")),
            ("coreography://filter?q=" + String(repeating: "a", count: 257), .invalidArgument("q is longer than 256 characters"))
        ]
        for (text, expected) in refused {
            XCTAssertEqual(AutomationLink.command(from: try XCTUnwrap(URL(string: text))), .failure(expected), text)
        }
        guard case .failure(.invalidArgument(let message)) = AutomationLink.command(from: try XCTUnwrap(URL(string: "coreography://range?seconds=5"))) else {
            return XCTFail("only the window's ranges are accepted")
        }
        XCTAssertTrue(message.contains("3600"))
    }

    func testHolderLookupsMatchPortsAndPathsAndNameWhatTheyMissed() throws {
        let processes = try snapshot([(10, "Safari Web Content"), (11, "curl"), (12, "Preview")])
        let connections = ConnectionSnapshot(
            takenAt: stamp.wallTime,
            connections: [
                socket(processes.processes[0], local: 50_000, remote: 443),
                socket(processes.processes[1], local: 8080, remote: nil)
            ],
            restrictedProcesses: 2, truncatedProcesses: 0, failedProcesses: 1, unavailableReason: nil
        )
        let byPort = HolderLookups.port(443, in: processes, connections: connections)
        XCTAssertEqual(byPort.holders.map(\.line), ["Safari Web Content (Safari Web Content, PID 10)"])
        XCTAssertEqual(byPort.limitations, ["2 processes of other users need the helper", "1 processes could not be read"])
        XCTAssertEqual(HolderLookups.port(8080, in: processes, connections: connections).holders.map(\.pid), [11])

        let files = OpenFileSnapshot(
            takenAt: stamp.wallTime, files: [processes.processes[2].id: ["/Users/me/Downloads/Report.pdf"]],
            restrictedProcesses: 0, truncatedProcesses: 0, failedProcesses: 0, unavailableReason: nil
        )
        XCTAssertEqual(HolderLookups.file("report.PDF", in: processes, files: files).holders.map(\.pid), [12], "the filter's case-insensitive rule")
        let unavailable = OpenFileSnapshot(
            takenAt: stamp.wallTime, files: [:], restrictedProcesses: 0, truncatedProcesses: 0, failedProcesses: 0,
            unavailableReason: "Open files need macOS"
        )
        XCTAssertEqual(HolderLookups.file("x", in: processes, files: unavailable), HolderLookup(holders: [], limitations: ["Open files need macOS"]))
    }

    @MainActor
    func testModelAppliesCommandsAndExplainsRefusals() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Idle()), interval: .milliseconds(10),
            processMonitor: try ProcessMonitor(driver: OneProcess()), processInterval: .milliseconds(10)
        )
        model.start()
        defer { model.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.processSnapshot == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }

        model.detailPane = .connections
        let none = await model.perform(.filter("port:443"))
        XCTAssertNil(none)
        XCTAssertEqual(model.processFilter, "port:443")
        XCTAssertEqual(model.detailPane, .processes, "a filter shows the processes it filters")

        let selected = await model.perform(.selectProcess(pid: 42))
        XCTAssertNil(selected)
        XCTAssertEqual(model.selectedProcess?.id.pid, 42)
        let missing = await model.perform(.selectProcess(pid: 7))
        XCTAssertEqual(missing, "No observed process has PID 7")
        XCTAssertEqual(model.actionMessage, "No observed process has PID 7")

        _ = await model.perform(.range(.hour))
        XCTAssertEqual(model.timeRange, .hour)

        let notRecording = await model.perform(.stopRecording)
        XCTAssertEqual(notRecording, "No session is recording")
        _ = await model.perform(.startRecording(name: "Build"))
        XCTAssertEqual(model.recordingName, "Build")
        let twice = await model.perform(.startRecording(name: "Other"))
        XCTAssertEqual(twice, "A session is already recording")
        XCTAssertEqual(model.recordingName, "Build")

        let lookup = await model.holders(ofPort: 443)
        XCTAssertEqual(lookup.limitations, ["Connections are not read here"], "a host without a socket reader says so")
    }

    func testSummaryTextUsesOnlyReadingsThatExist() {
        XCTAssertEqual(AutomationText.summary(DiagnosticTools.summary(DiagnosticSnapshot(
            takenAt: stamp.wallTime, host: [], network: [], gpu: [], power: [], sensors: [], processes: nil,
            ledger: AppLedger(capacity: 1)
        ))), "No readings yet.")
    }

    // MARK: Fixtures

    private func socket(_ process: ObservedProcess, local: UInt16, remote: UInt16?) -> ConnectionReading {
        ConnectionReading(
            process: process.id, processName: process.name, descriptor: Int32(local % 100), transport: .tcp,
            state: remote == nil ? .listen : .established, local: ConnectionEndpoint(address: "127.0.0.1", port: local),
            remote: remote.map { ConnectionEndpoint(address: "17.0.0.1", port: $0) }
        )
    }

    private func snapshot(_ rows: [(Int32, String)]) throws -> CapturedProcesses {
        let processes = try rows.map { pid, name in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501, name: name,
                stamp: stamp, cpuPercentOfMachine: try .measured(0), memoryFootprintBytes: try .measured(1),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(processes.count)), enumerationTruncated: false,
            processes: processes, issues: [], continuity: .continuous
        )
    }
}

private actor OneProcess: ProcessSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawProcessSnapshot {
        reads += 1
        return RawProcessSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)), logicalCPUCount: 4, collectorPID: 42,
            enumeration: .success(ProcessEnumeration(processes: [RawProcessInfo(
                pid: 42, parentPID: 1, uid: 501, startSeconds: 100, startMicroseconds: 0, name: "fixture",
                monotonicNanoseconds: reads * 1_000_000_000,
                counters: .success(ProcessCounters(userNanoseconds: reads, systemNanoseconds: 0, physicalFootprintBytes: 1, diskReadBytes: 0, diskWriteBytes: 0))
            )]))
        )
    }
}

private actor Idle: HostSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawHostSnapshot {
        reads += 1
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30),
            cpu: .success(ProcessorTicks(user: reads, system: 0, idle: reads * 3, nice: 0)),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0, wired: 2, compressed: 3, compressorContents: 6, purgeable: 0,
                fileBacked: 1, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 8192, usedBytes: 0)),
            memoryPressure: .success(.normal), thermalPressure: .success(.nominal)
        )
    }
}
