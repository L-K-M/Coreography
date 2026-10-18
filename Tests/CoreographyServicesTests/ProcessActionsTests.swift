import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

@MainActor
final class ProcessActionsTests: XCTestCase {
    func testConsequencesNameLogoutChildrenAndForce() async throws {
        let session = try process(pid: 90, name: "loginwindow")
        let child = try process(pid: 91, name: "helper", parent: 90)
        let snapshot = try self.snapshot([session, child])

        let quit = ProcessActions.request(for: session, mode: .graceful, in: snapshot)
        XCTAssertTrue(quit.endsSession)
        XCTAssertEqual(quit.consequences.first, "This logs you out; unsaved work in every app is lost.")
        XCTAssertTrue(quit.consequences.contains("1 child process may also exit."))

        let force = ProcessActions.request(for: child, mode: .forced, in: snapshot)
        XCTAssertFalse(force.endsSession)
        XCTAssertEqual(force.consequences, ["The process ends immediately without a chance to save."])

        let unknown = ProcessActions.request(for: child, mode: .forced, in: nil)
        XCTAssertEqual(unknown.consequences.last, "Child processes, if any, may also exit.")
    }

    func testRequestsTargetTheExactIdentityAndMarkOnlySuccess() async throws {
        let driver = RecordingDriver(results: [.success(()), .failure(.identityChanged)])
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: NoHostDriver()), interval: .seconds(1),
            controller: ProcessController(driver: driver)
        )
        let target = try process(pid: 77, name: "Worker", start: 1234)

        model.perform(model.actionRequest(for: target, mode: .forced))
        XCTAssertEqual(driver.calls.first?.pid, 77)
        XCTAssertEqual(driver.calls.first?.startSeconds, 1234)
        XCTAssertEqual(driver.calls.first?.mode, .forced)
        XCTAssertEqual(model.markers.map(\.label), ["Force quit Worker"])

        model.perform(model.actionRequest(for: target, mode: .graceful))
        XCTAssertEqual(model.markers.count, 1, "a refused request leaves no marker")
        XCTAssertEqual(model.actionMessage, "Worker: The PID now belongs to a different process; nothing was sent")
    }

    private func process(pid: Int32, name: String, parent: UInt32 = 1, start: UInt64 = 10) throws -> ObservedProcess {
        ProcessReading(
            id: try ProcessIdentity(pid: pid, startSeconds: start, startMicroseconds: 0),
            parentPID: parent, uid: 501, name: name,
            stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date()),
            cpuPercentOfMachine: .collecting(), memoryFootprintBytes: .collecting(),
            diskReadBytesPerSecond: .collecting(), diskWriteBytesPerSecond: .collecting(),
            executablePath: nil, responsiblePID: nil
        )
    }

    private func snapshot(_ processes: [ObservedProcess]) throws -> CapturedProcesses {
        ProcessSnapshot(
            stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date()), collectorPID: 1,
            enumeration: try .measured(Double(processes.count)), enumerationTruncated: false,
            processes: processes, issues: [], continuity: .continuous
        )
    }
}

private final class RecordingDriver: ProcessTerminating, @unchecked Sendable {
    struct Call { let pid: Int32; let startSeconds: UInt64; let mode: ProcessTermination }
    private(set) var calls: [Call] = []
    private var results: [Result<Void, ProcessControlError>]

    init(results: [Result<Void, ProcessControlError>]) { self.results = results }

    @MainActor
    func terminate(
        pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, mode: ProcessTermination
    ) -> Result<Void, ProcessControlError> {
        calls.append(Call(pid: pid, startSeconds: startSeconds, mode: mode))
        return results.removeFirst()
    }
}

private actor NoHostDriver: HostSampleReading {
    func read() async -> RawHostSnapshot {
        RawHostSnapshot(
            clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date(),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 1, physicalMemoryBytes: 1),
            cpu: .failure(.unsupportedPlatform), memory: .failure(.unsupportedPlatform),
            swap: .failure(.unsupportedPlatform), memoryPressure: .failure(.unsupportedPlatform),
            thermalPressure: .failure(.unsupportedPlatform)
        )
    }
}
