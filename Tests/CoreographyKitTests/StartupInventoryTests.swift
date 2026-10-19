import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class StartupInventoryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testReadsJobDefinitionsAndCountsUnreadableOnes() async throws {
        try write("agent", ["Label": "com.example.agent", "ProgramArguments": ["/opt/example/agent", "--quiet"], "RunAtLoad": true])
        try write("keeper", ["Label": "com.example.keeper", "Program": "/opt/example/keeper", "KeepAlive": ["SuccessfulExit": false], "Disabled": true])
        try write("nolabel", ["Program": "/opt/x"])
        try Data("not a plist".utf8).write(to: folder.appendingPathComponent("broken.plist"))
        try Data().write(to: folder.appendingPathComponent("ignored.txt"))

        let raw = await LaunchJobDriver(folders: [(.userAgents, folder)], readsOverrides: false).read()
        XCTAssertEqual(raw.unreadable, 2)
        let jobs = raw.jobs.sorted { $0.label < $1.label }
        XCTAssertEqual(jobs.map(\.label), ["com.example.agent", "com.example.keeper"])
        XCTAssertEqual(jobs[0].program, "/opt/example/agent", "the first program argument")
        XCTAssertTrue(jobs[0].runAtLoad)
        XCTAssertFalse(jobs[0].keepAlive)
        XCTAssertTrue(jobs[1].keepAlive, "a condition dictionary still restarts the job")
        XCTAssertTrue(jobs[1].disabledInPlist)
        XCTAssertEqual(jobs[1].signature, .unknown, "a missing program has no signature to read")
    }

    func testOverridesParseBothSpellings() {
        let text = """
            disabled services = {
            \t"com.example.agent" => disabled
            \t"com.example.keeper" => enabled
            \t"com.old.style" => true
            }
            """
        XCTAssertEqual(LaunchJobDriver.overrides(text), ["com.example.agent": true, "com.example.keeper": false, "com.old.style": true])
    }

    func testLaunchdOverridesWinAndUnreadableOverridesAreNamed() async {
        let jobs = [
            job("com.example.agent", .userAgents, disabled: false),
            job("com.example.keeper", .daemons, disabled: true),
            job("com.apple.thing", .systemDaemons, disabled: false)
        ]
        let read = await StartupProvider(driver: Jobs(RawLaunchJobs(
            jobs: jobs, unreadable: 1, overrides: [.user: ["com.example.agent": true]], overridesProblem: nil
        ))).load()
        XCTAssertEqual(read.items.map(\.label), ["com.example.agent", "com.example.keeper", "com.apple.thing"])
        XCTAssertEqual(read.items.map(\.state), [.disabled, .disabled, .enabled])
        XCTAssertEqual(read.items.map(\.isApple), [false, false, true])
        XCTAssertEqual(read.unreadableDefinitions, 1)

        let unconfirmed = await StartupProvider(driver: Jobs(RawLaunchJobs(
            jobs: jobs, unreadable: 0, overrides: [:], overridesProblem: "launchctl could not start"
        ))).load()
        XCTAssertEqual(unconfirmed.items.map(\.state), [.unconfirmed, .unconfirmed, .unconfirmed])
        XCTAssertEqual(unconfirmed.stateProblem, "launchctl could not start")
    }

    /// launchd keeps overrides per domain; one label can be an agent and a daemon.
    func testOverridesApplyOnlyInTheirOwnDomain() async {
        let jobs = [job("com.example.shared", .userAgents, disabled: false), job("com.example.shared", .daemons, disabled: false)]
        let read = await StartupProvider(driver: Jobs(RawLaunchJobs(
            jobs: jobs, unreadable: 0, overrides: [.user: ["com.example.shared": true], .system: ["com.example.shared": false]],
            overridesProblem: nil
        ))).load()
        XCTAssertEqual(read.items.map(\.state), [.disabled, .enabled])
    }

    private func write(_ name: String, _ plist: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: folder.appendingPathComponent("\(name).plist"))
    }

    private func job(_ label: String, _ domain: LaunchDomain, disabled: Bool) -> RawLaunchJob {
        RawLaunchJob(
            domain: domain, plistPath: "/x/\(label).plist", label: label, program: "/opt/\(label)",
            runAtLoad: true, keepAlive: false, disabledInPlist: disabled, signature: .unknown
        )
    }
}

private struct Jobs: LaunchJobReading {
    let raw: RawLaunchJobs

    init(_ raw: RawLaunchJobs) { self.raw = raw }

    func read() async -> RawLaunchJobs { raw }
}
