import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class AlertActionTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testStartupDiskRuleRaisesUnderTenPercentAndClearsAfterAMinute() {
        var engine = AlertEngine(rules: AlertRules.shipped)
        func inputs(_ free: Double?) -> AlertInputs {
            AlertInputs(memoryPressure: nil, thermalPressure: nil, batteryPercent: nil, onBattery: nil, startupFreeFraction: free)
        }
        XCTAssertEqual(engine.evaluate(inputs(0.05), at: epoch).map(\.ruleID), ["startup-disk-low"])
        XCTAssertTrue(engine.evaluate(inputs(nil), at: epoch.addingTimeInterval(10)).isEmpty, "an unread volume changes nothing")
        XCTAssertTrue(engine.evaluate(inputs(0.2), at: epoch.addingTimeInterval(20)).isEmpty)
        XCTAssertEqual(engine.evaluate(inputs(0.2), at: epoch.addingTimeInterval(80)).map(\.kind), [.cleared])
        XCTAssertEqual(AlertRules.shipped.first { $0.id == "startup-disk-low" }?.lane, .disk)
    }

    func testShortcutsAreSavedPerRuleAndBlankRemoves() throws {
        let suite = "AlertActionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertShortcuts(defaults: defaults)
        XCTAssertEqual(store.set(" Clean Up ", for: "startup-disk-low"), ["startup-disk-low": "Clean Up"])
        XCTAssertEqual(AlertShortcuts(defaults: defaults).all, ["startup-disk-low": "Clean Up"])
        XCTAssertEqual(store.set("  ", for: "startup-disk-low"), [:])
        XCTAssertFalse(ShortcutRunner.isValid(""))
        XCTAssertFalse(ShortcutRunner.isValid("a\nb"))
        XCTAssertFalse(ShortcutRunner.isValid(String(repeating: "x", count: 257)))
        XCTAssertTrue(ShortcutRunner.isValid("Free Up Space"))
    }

    @MainActor
    func testARaisedRuleRunsItsShortcutOnceAndReportsFailures() async throws {
        let shortcuts = RecordingShortcuts()
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Ticking()), interval: .milliseconds(10),
            shortcutRunner: ShortcutLauncher(runner: shortcuts),
            volumeReader: StartupVolumeMonitor(driver: NearlyFull())
        )
        let suite = "AlertActionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        model.useShortcutStore(defaults)
        model.setShortcut("Free Up Space", for: "startup-disk-low")
        model.start()
        defer { model.stop() }

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.activeAlerts[.disk] == nil || model.actionMessage == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.activeAlerts[.disk], "Startup disk under 10% free")
        let runs = await shortcuts.runs
        XCTAssertEqual(runs, ["Free Up Space"], "one raise runs the Shortcut once")
        XCTAssertEqual(model.actionMessage, "Shortcut Free Up Space for “Startup disk under 10% free” failed: it exited with status 1")

        await model.refreshShortcuts()
        XCTAssertEqual(model.availableShortcuts, ["Free Up Space", "Mute"])
    }
}

private actor RecordingShortcuts: ShortcutRunning {
    private(set) var runs: [String] = []

    func list() async -> Result<[String], ShortcutError> { .success(["Free Up Space", "Mute"]) }

    func run(_ name: String) async -> Result<Void, ShortcutError> {
        runs.append(name)
        return .failure(.failed(1))
    }
}

private struct NearlyFull: VolumeCapacityReading {
    func startupVolume() async -> Result<RawVolumeCapacity, VolumeCapacityError> {
        .success(RawVolumeCapacity(totalBytes: 1_000, availableBytes: 50))
    }
}

private actor Ticking: HostSampleReading {
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
