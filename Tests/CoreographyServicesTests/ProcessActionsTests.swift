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

    func testSignalsThatCanEndASessionSayItLogsYouOut() throws {
        let windowServer = try process(pid: 80, name: "WindowServer")
        let snapshot = try self.snapshot([windowServer])
        for action in [ProcessAction.hangUp, .interrupt] {
            let request = ProcessActions.request(for: windowServer, action: action, in: snapshot)
            XCTAssertEqual(request.consequences.first, "This logs you out; unsaved work in every app is lost.", "\(action)")
            XCTAssertTrue(request.endsSession, "\(action)")
        }
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

    func testSignalsAndPriorityGoByIdentityAndRefuseWhatCannotBeUndone() async throws {
        let signaler = RecordingSignaler(results: [.success(()), .failure(.needsAdministrator)])
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: NoHostDriver()), interval: .seconds(1),
            controller: ProcessController(driver: RecordingDriver(results: []), signaler: signaler)
        )
        let worker = try process(pid: 77, name: "Worker", start: 1234)
        let session = try process(pid: 88, name: "WindowServer")

        let suspend = model.actionRequest(for: worker, action: .suspend)
        XCTAssertNil(suspend.refusal)
        XCTAssertEqual(suspend.consequences, ["It stops running until resumed; an app stops responding meanwhile."])
        model.perform(suspend)
        XCTAssertEqual(signaler.calls.first?.signal, .suspend)
        XCTAssertEqual(signaler.calls.first?.startSeconds, 1234)
        XCTAssertEqual(model.markers.map(\.label), ["Suspend Worker"])

        model.perform(model.actionRequest(for: worker, action: .lowerPriority))
        XCTAssertEqual(signaler.calls.last?.nice, ProcessController.lowPriorityNice)
        XCTAssertEqual(model.actionMessage, "Worker: Its priority was not changed; only an administrator can change it")

        let frozen = model.actionRequest(for: session, action: .suspend)
        XCTAssertEqual(frozen.refusal, "Suspending it would freeze the screen with no way back.")
        model.perform(frozen)
        XCTAssertEqual(signaler.calls.count, 2, "a refused action sends nothing")

        XCTAssertTrue(model.copyText(for: worker).contains("PID 77"))
        XCTAssertTrue(model.copyJSON(for: worker).contains("\"name\" : \"Worker\""))
    }

    func testSamplingOpensAReportOrNamesWhyNot() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: NoHostDriver()), interval: .seconds(1),
            sampler: ProcessSampler(driver: Sampler())
        )
        await model.sampleProcess(try process(pid: 77, name: "Worker", start: 1234))
        guard case .finished(let report) = model.sampleState else { return XCTFail("expected a report") }
        XCTAssertEqual(report.name, "Worker")
        XCTAssertEqual(report.seconds, ProcessSampler.defaultSeconds)
        XCTAssertTrue(report.text.hasPrefix("Call graph"))

        await model.sampleProcess(try process(pid: 78, name: "Gone"))
        guard case .failed(let name, let reason) = model.sampleState else { return XCTFail("expected a failure") }
        XCTAssertEqual(name, "Gone")
        XCTAssertEqual(reason, "The process exited before it could be sampled")
        model.dismissSample()
        guard case .idle = model.sampleState else { return XCTFail("dismissed") }

        // Closing while it runs is allowed; the late report does not reopen the sheet.
        let slow = Task { await model.sampleProcess(try process(pid: 79, name: "Slow")) }
        while true {
            if case .running = model.sampleState { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        model.dismissSample()
        guard case .idle = model.sampleState else { return XCTFail("closing a running sample closes it") }
        _ = await slow.result
        guard case .idle = model.sampleState else { return XCTFail("the abandoned report stays away") }
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

private final class RecordingSignaler: ProcessSignaling, @unchecked Sendable {
    struct Call { let signal: ProcessSignal?; let nice: Int32?; let startSeconds: UInt64 }
    private(set) var calls: [Call] = []
    private var results: [Result<Void, ProcessControlError>]

    init(results: [Result<Void, ProcessControlError>]) { self.results = results }

    func send(_ signal: ProcessSignal, pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) -> Result<Void, ProcessControlError> {
        calls.append(Call(signal: signal, nice: nil, startSeconds: startSeconds))
        return results.removeFirst()
    }

    func renice(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, to niceValue: Int32) -> Result<Void, ProcessControlError> {
        calls.append(Call(signal: nil, nice: niceValue, startSeconds: startSeconds))
        return results.removeFirst()
    }
}

private struct Sampler: ProcessSampling {
    func sample(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, seconds: Int) async -> Result<String, ProcessSampleError> {
        if pid == 79 { try? await Task.sleep(for: .milliseconds(100)) }
        return pid == 77 || pid == 79 ? .success("Call graph:\n    3 Thread_1") : .failure(.exited)
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
