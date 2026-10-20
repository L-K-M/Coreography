import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class ProcessInspectionTests: XCTestCase {
    private let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date())

    func testParentChainEndsAtLaunchdOrTheFirstUnobservedParent() throws {
        let snapshot = try snapshot([(1, 0, "launchd", nil), (50, 1, "WindowServer", "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"), (60, 50, "child", "/opt/child"), (70, 999, "orphan", nil)])
        let child = try XCTUnwrap(snapshot.processes.first { $0.id.pid == 60 })
        let startup = StartupInventory(
            takenAt: Date(), items: [StartupItem(
                label: "com.example.child", kind: .agent, plistPath: "/Library/LaunchAgents/c.plist", program: "/opt/child",
                runsAtLoad: true, keepsAlive: true, state: .enabled, isApple: false
            )],
            unreadableDefinitions: 0, stateProblem: nil
        )
        let inspection = ProcessInspections.make(child, in: snapshot, startup: startup, detail: nil, sockets: nil)
        XCTAssertEqual(inspection.parentChain.map(\.pid), [50, 1])
        XCTAssertEqual(inspection.parentChain.map(\.name), ["WindowServer", "launchd"])
        XCTAssertEqual(inspection.launchdLabel, "com.example.child")
        XCTAssertNil(inspection.explanation)

        let orphan = try XCTUnwrap(snapshot.processes.first { $0.id.pid == 70 })
        let unobserved = ProcessInspections.make(orphan, in: snapshot, startup: nil, detail: nil, sockets: nil)
        XCTAssertEqual(unobserved.parentChain.map(\.pid), [999])
        XCTAssertNil(unobserved.parentChain.first?.name, "an unobserved parent keeps its PID only")

        let server = try XCTUnwrap(snapshot.processes.first { $0.id.pid == 50 })
        guard case .logsOut = ProcessInspections.make(server, in: snapshot, startup: nil, detail: nil, sockets: nil).explanation?.quitting else {
            return XCTFail("quitting WindowServer ends the session")
        }
    }

    func testExplanationsRequireASystemPathAndDoNotPromiseSafeQuitting() throws {
        let snapshot = try snapshot([
            (10, 1, "mds", "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Support/mds"),
            (11, 1, "mds", "/Applications/mds.app/Contents/MacOS/mds"),
            (12, 1, "mds", "/usr/local/bin/mds"),
            (13, 1, "mds", nil)
        ])
        let note = try XCTUnwrap(ProcessExplanations.note(for: snapshot.processes[0]))
        XCTAssertTrue(note.summary.contains("Spotlight"))
        XCTAssertFalse(note.quittingNote.contains("safe"), "a role does not establish that current work can be interrupted safely")
        for process in snapshot.processes.dropFirst() {
            XCTAssertNil(ProcessExplanations.note(for: process), "a name alone does not identify an Apple process")
        }

        let captured = DiagnosticSnapshot(
            takenAt: stamp.wallTime, host: [], network: [], gpu: [], power: [], sensors: [],
            processes: snapshot, ledger: AppLedger(capacity: 1)
        )
        XCTAssertEqual(DiagnosticTools.processDetails(captured, pid: 10)?.explanation, "\(note.summary) \(note.quittingNote)")
        XCTAssertNil(DiagnosticTools.processDetails(captured, pid: 11)?.explanation)
        let encoded = try DiagnosticToolCatalog.run("get_process_details", arguments: ["pid": 10], snapshot: captured)
        XCTAssertTrue(encoded.contains("Spotlight"), "the qualified note is exported")
        XCTAssertFalse(encoded.contains("/System/"), "path qualification must not export the path")
    }

    @MainActor
    func testSelectingAProcessOpensTheInspectorAndReadsItsDetail() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Idle()), interval: .milliseconds(10),
            processMonitor: try ProcessMonitor(driver: OneProcess()), processInterval: .milliseconds(10),
            inspector: ProcessInspector(driver: Details())
        )
        model.start()
        defer { model.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.processSnapshot == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let process = try XCTUnwrap(model.processSnapshot?.processes.first)

        XCTAssertFalse(model.inspectorShown)
        model.selectedProcessRow = ProcessGroups.rowID(process)
        XCTAssertTrue(model.inspectorShown)
        while model.processDetail == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.processInspection?.detail?.arguments, ["fixture", "--serve"])
        XCTAssertEqual(model.processInspection?.process.id, process.id)
    }

    /// Plan: the catalogue matches on code signature as well as path. A
    /// program another developer signed is not the macOS one, wherever it
    /// sits; an unread signature leaves the path to decide.
    func testAnExplanationNeedsAnAppleSignatureWhenOneWasRead() throws {
        let snapshot = try snapshot([(10, 1, "mds", "/usr/libexec/mds")])
        let mds = snapshot.processes[0]
        XCTAssertNotNil(ProcessExplanations.note(for: mds, signer: .apple))
        XCTAssertNotNil(ProcessExplanations.note(for: mds, signer: .unknown), "an unreadable signature proves nothing")
        XCTAssertNil(ProcessExplanations.note(for: mds, signer: .developer(team: "ABCDE12345")))
        XCTAssertNil(ProcessExplanations.note(for: mds, signer: .unsigned))

        let signed = ProcessDetail(
            process: mds.id, arguments: nil, argumentsProblem: nil,
            signing: ProcessSigning(signer: .unsigned, identifier: nil)
        )
        XCTAssertNotNil(ProcessInspections.make(mds, in: snapshot, startup: nil, detail: nil, sockets: nil).explanation)
        XCTAssertNil(ProcessInspections.make(mds, in: snapshot, startup: nil, detail: signed, sockets: nil).explanation,
                     "the inspector checks the signature once it has read it")
    }

    func testKernelTaskUsesItsUnforgeablePIDInsteadOfAnExecutablePath() throws {
        let snapshot = try snapshot([(0, 0, "kernel_task", nil), (10, 1, "kernel_task", nil)])
        let note = try XCTUnwrap(ProcessExplanations.note(for: snapshot.processes[0]))
        guard case .notAllowed = note.quitting else { return XCTFail("the kernel cannot be quit") }
        XCTAssertNil(ProcessExplanations.note(for: snapshot.processes[1]), "a same-named user process is not the kernel")
    }

    private func snapshot(_ rows: [(Int32, UInt32, String, String?)]) throws -> CapturedProcesses {
        let processes = try rows.map { pid, parent, name, path in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: parent, uid: 501, name: name,
                stamp: stamp, cpuPercentOfMachine: try .measured(0), memoryFootprintBytes: try .measured(1),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                executablePath: path, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(processes.count)), enumerationTruncated: false,
            processes: processes, issues: [], continuity: .continuous
        )
    }
}

private struct Details: ProcessDetailReading {
    func arguments(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<[String], ProcessDetailError> {
        .success(["fixture", "--serve"])
    }

    func signing(path: String) async -> CodeSigning { CodeSigning(signature: .unknown, identifier: nil, teamID: nil) }
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
