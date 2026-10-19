import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class MaintenanceTests: XCTestCase {
    private static let backupdPath = "/System/Library/CoreServices/backupd.bundle/Contents/Resources/backupd"
    private let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date(timeIntervalSince1970: 1_700_000_000))

    func testOnlyAVerifiedSystemProcessGetsAMaintenanceState() throws {
        let snapshot = try snapshot([
            (10, "backupd", Self.backupdPath), (11, "backupd", "/usr/local/bin/backupd"),
            (12, "mdworker_shared", "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Versions/A/Support/mdworker_shared"),
            (13, "Finder", "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder")
        ])
        let status = MaintenanceStatus(
            readAt: stamp.wallTime, timeMachine: .backingUp(BackupProgress(phase: "Copying", fraction: 0.42, remainingSeconds: 300)),
            spotlight: .enabled
        )
        let notes = snapshot.processes.map {
            ProcessInspections.make($0, in: snapshot, startup: nil, detail: nil, sockets: nil, maintenance: status).maintenance
        }
        XCTAssertEqual(notes[0], MaintenanceNote(
            text: "Time Machine is backing up: copying, 42% done, about 5 min left. It finishes on its own.", readAt: stamp.wallTime
        ))
        XCTAssertNil(notes[1], "a name alone does not identify backupd")
        XCTAssertEqual(notes[2]?.text, "Spotlight indexing is on for the startup disk. macOS does not report indexing progress.")
        XCTAssertNil(notes[3], "Finder does no reported maintenance")
    }

    func testOnlyAReportedBackupPromisesAnEnd() {
        XCTAssertEqual(MaintenanceNotes.timeMachine(.idle), "No Time Machine backup is running.")
        XCTAssertEqual(
            MaintenanceNotes.timeMachine(.backingUp(BackupProgress(phase: nil, fraction: nil, remainingSeconds: 20))),
            "Time Machine is backing up: under a minute left. It finishes on its own."
        )
        XCTAssertEqual(MaintenanceNotes.phaseText("FindingChanges"), "finding changes")
        XCTAssertEqual(MaintenanceNotes.phaseText("HealthCheckCopyHFSMeta"), "health check copy HFS meta")
        XCTAssertEqual(MaintenanceNotes.phaseText("Copying"), "copying")
        XCTAssertEqual(
            MaintenanceNotes.timeMachine(.backingUp(BackupProgress(phase: nil, fraction: nil, remainingSeconds: 5_400))),
            "Time Machine is backing up: about 1.5 h left. It finishes on its own.", "a first backup takes hours, not 90 min"
        )
        XCTAssertEqual(
            MaintenanceNotes.timeMachine(.backingUp(BackupProgress(phase: nil, fraction: nil, remainingSeconds: 7_200))),
            "Time Machine is backing up: about 2 h left. It finishes on its own."
        )
        for indexing in [SpotlightIndexing.enabled, .disabled, .unavailable("x")] {
            XCTAssertFalse(MaintenanceNotes.spotlight(indexing).contains("finish"), "mdutil reports no progress")
        }
    }

    func testSummaryCarriesTheStateAndSignalsOnlyARunningBackup() throws {
        let running = try summaryJSON(MaintenanceStatus(
            readAt: stamp.wallTime, timeMachine: .backingUp(BackupProgress(phase: "Copying", fraction: 0.5, remainingSeconds: nil)),
            spotlight: .unavailable("mdutil hit its time limit")
        ))
        let maintenance = try XCTUnwrap(running["maintenance"] as? [String: Any])
        XCTAssertEqual(maintenance["timeMachine"] as? String, "backingUp")
        XCTAssertEqual(maintenance["backupFraction"] as? Double, 0.5)
        XCTAssertEqual(maintenance["spotlightIndexing"] as? String, "unavailable")
        XCTAssertEqual(maintenance["unavailableReasons"] as? [String], ["Spotlight: mdutil hit its time limit"])
        XCTAssertEqual((running["signals"] as? [[String: Any]])?.compactMap { $0["kind"] as? String }, ["backupRunning"])

        let idle = try summaryJSON(MaintenanceStatus(readAt: stamp.wallTime, timeMachine: .idle, spotlight: .enabled))
        XCTAssertEqual((idle["signals"] as? [[String: Any]])?.count, 0, "an indexed disk is not activity")
        XCTAssertNil(try summaryJSON(nil)["maintenance"], "no read, no invented state")
    }

    @MainActor
    func testSelectingBackupdReadsItsStateOffTheSamplingPath() async throws {
        let tools = CountingTools()
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Idle()), interval: .milliseconds(10),
            processMonitor: try ProcessMonitor(driver: Backupd()), processInterval: .milliseconds(10),
            inspector: ProcessInspector(driver: NoDetails()),
            maintenanceProvider: MaintenanceStatusProvider(driver: tools)
        )
        model.start()
        defer { model.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.processSnapshot == nil || model.maintenanceStatus == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(model.processSnapshot, "no process sample within 5 s")
        XCTAssertNotNil(model.maintenanceStatus, "no maintenance read within 5 s")
        let process = try XCTUnwrap(model.processSnapshot?.processes.first)
        model.selectedProcessRow = ProcessGroups.rowID(process)
        XCTAssertEqual(model.processInspection?.maintenance?.text, "No Time Machine backup is running.")
        XCTAssertEqual(model.diagnosticSnapshot().maintenance?.timeMachine, .idle)
        let reads = await tools.reads
        XCTAssertEqual(reads, 1, "a fresh status is not reread on selection or every sample")
    }

    // MARK: Fixtures

    private func summaryJSON(_ maintenance: MaintenanceStatus?) throws -> [String: Any] {
        let snapshot = DiagnosticSnapshot(
            takenAt: stamp.wallTime, host: [], network: [], gpu: [], power: [], sensors: [], processes: nil,
            ledger: AppLedger(capacity: 1), maintenance: maintenance
        )
        let text = try DiagnosticToolCatalog.run("get_system_summary", arguments: [:], snapshot: snapshot)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func snapshot(_ rows: [(Int32, String, String?)]) throws -> CapturedProcesses {
        let processes = try rows.map { pid, name, path in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 0, name: name,
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

private actor CountingTools: MaintenanceStatusReading {
    private(set) var reads = 0

    func timeMachineStatus() async throws -> RawToolStatus {
        reads += 1
        return RawToolStatus(text: "Backup session status:\n{\n    Running = 0;\n}", timedOut: false, exitStatus: 0)
    }

    func spotlightStatus() async throws -> RawToolStatus {
        RawToolStatus(text: "/:\n\tIndexing enabled.", timedOut: false, exitStatus: 0)
    }
}

private struct NoDetails: ProcessDetailReading {
    func arguments(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<[String], ProcessDetailError> {
        .success([])
    }

    func signing(path: String) async -> CodeSigning { CodeSigning(signature: .unknown, identifier: nil, teamID: nil) }
}

private actor Backupd: ProcessSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawProcessSnapshot {
        reads += 1
        return RawProcessSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)), logicalCPUCount: 4, collectorPID: 42,
            enumeration: .success(ProcessEnumeration(processes: [RawProcessInfo(
                pid: 42, parentPID: 1, uid: 0, startSeconds: 100, startMicroseconds: 0, name: "backupd",
                monotonicNanoseconds: reads * 1_000_000_000,
                counters: .success(ProcessCounters(userNanoseconds: reads, systemNanoseconds: 0, physicalFootprintBytes: 1, diskReadBytes: 0, diskWriteBytes: 0)),
                executablePath: "/System/Library/CoreServices/backupd.bundle/Contents/Resources/backupd"
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
