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

    /// SIGUSR1 and SIGUSR2 terminate a program that does not handle them,
    /// so sent to the window server they log you out; SIGINFO is ignored.
    func testUserSignalsEndASessionAndInfoDoesNot() throws {
        let windowServer = try process(pid: 80, name: "WindowServer")
        let snapshot = try self.snapshot([windowServer])
        for action in [ProcessAction.user1, .user2] {
            let request = ProcessActions.request(for: windowServer, action: action, in: snapshot)
            XCTAssertTrue(request.endsSession, "\(action)")
            XCTAssertTrue(request.consequences.contains("This logs you out; unsaved work in every app is lost."), "\(action)")
        }
        let info = ProcessActions.request(for: windowServer, action: .info, in: snapshot)
        XCTAssertFalse(info.endsSession)
        XCTAssertFalse(info.consequences.contains("This logs you out; unsaved work in every app is lost."))
    }

    func testUserAndInfoSignalsStateTheirEffect() throws {
        let worker = try process(pid: 81, name: "Worker")
        let snapshot = try self.snapshot([worker])
        for action in [ProcessAction.user1, .user2] {
            let request = ProcessActions.request(for: worker, action: action, in: snapshot)
            XCTAssertEqual(request.consequences, [
                "Each program defines its effect; one that does not handle it terminates, which is the signal's default action."
            ], "\(action)")
        }
        let info = ProcessActions.request(for: worker, action: .info, in: snapshot)
        XCTAssertEqual(info.consequences, [
            "Its effect is defined by the program; tools often print status, and most programs ignore it."
        ])
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

    func testARefusalForPermissionIsRetriedThroughTheHelper() async throws {
        let signaler = RecordingSignaler(results: [.failure(.notPermitted)])
        let answering = PrivilegedHelper(registration: StubRegistration(), transport: HelperAnswer(.actionDone), teamID: "AB12CD34EF")
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: NoHostDriver()), interval: .seconds(1),
            controller: ProcessController(driver: RecordingDriver(results: []), signaler: signaler, helper: answering)
        )
        let other = try process(pid: 300, name: "Daemon", start: 55)

        model.perform(model.actionRequest(for: other, action: .suspend))
        for _ in 0..<200 where model.markers.isEmpty || model.actionMessage == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.markers.map(\.label), ["Suspend Daemon"])
        XCTAssertEqual(model.actionMessage, "Suspend Daemon (PID 300): requested through the privileged helper")

        // Without an installed helper the app's own refusal stands.
        let absent = PrivilegedHelper(registration: StubRegistration(isEnabled: false), transport: HelperAnswer(.actionDone), teamID: "AB12CD34EF")
        let ownSignaler = RecordingSignaler(results: [.failure(.notPermitted)])
        let refused = DashboardModel(
            monitor: try SystemMonitor(driver: NoHostDriver()), interval: .seconds(1),
            controller: ProcessController(driver: RecordingDriver(results: []), signaler: ownSignaler, helper: absent)
        )
        refused.perform(refused.actionRequest(for: other, action: .suspend))
        for _ in 0..<200 where refused.actionMessage == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(refused.actionMessage, "Daemon: Not permitted: the process belongs to another user or is protected")
        XCTAssertTrue(refused.markers.isEmpty)
        XCTAssertEqual(ownSignaler.calls.count, 1, "one own attempt, nothing more")
    }

    func testUserAndInfoSignalsGoByIdentity() async throws {
        let signaler = RecordingSignaler(results: [.success(()), .success(()), .success(())])
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: NoHostDriver()), interval: .seconds(1),
            controller: ProcessController(driver: RecordingDriver(results: []), signaler: signaler)
        )
        let worker = try process(pid: 77, name: "Worker", start: 1234)

        for (action, signal) in [(ProcessAction.user1, ProcessSignal.user1), (.user2, .user2), (.info, .info)] {
            model.perform(model.actionRequest(for: worker, action: action))
            XCTAssertEqual(signaler.calls.last?.signal, signal, "\(action)")
            XCTAssertEqual(signaler.calls.last?.startSeconds, 1234, "\(action)")
        }
        XCTAssertEqual(model.markers.map(\.label), [
            "Send SIGUSR1 to Worker", "Send SIGUSR2 to Worker", "Send SIGINFO to Worker"
        ])
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
        guard case .failed(let name, let tool, let reason) = model.sampleState else { return XCTFail("expected a failure") }
        XCTAssertEqual(tool, .sample)
        XCTAssertEqual(name, "Gone")
        XCTAssertEqual(reason, "The process exited before it could be sampled")
        model.dismissSample()
        guard case .idle = model.sampleState else { return XCTFail("dismissed") }

        // Closing while it runs is allowed; the late report does not reopen the sheet.
        let slow = Task { await model.sampleProcess(try process(pid: 79, name: "Slow")) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if case .running = model.sampleState { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard case .running = model.sampleState else { return XCTFail("sampling never started") }
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

private struct StubRegistration: HelperRegistering {
    var isEnabled = true
    func status() -> HelperRegistrationStatus { isEnabled ? .enabled : .notRegistered }
    func register() throws {}
    func unregister() async throws {}
    func openApprovalSettings() {}
}

private struct HelperAnswer: HelperTransport {
    let reply: HelperReply
    init(_ reply: HelperReply) { self.reply = reply }
    func exchange(_ message: Data) async throws -> Data { HelperWire.encode(reply) }
}
