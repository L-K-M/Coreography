import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class AlertEngineTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testRulesRaiseAndClearOnlyAfterTheirDurations() {
        var engine = AlertEngine(rules: AlertRules.shipped)
        func step(_ second: TimeInterval, _ pressure: MemoryPressureLevel?) -> [AlertEvent.Kind] {
            engine.evaluate(inputs(memory: pressure), at: epoch.addingTimeInterval(second))
                .filter { $0.ruleID == "memory-critical" }.map(\.kind)
        }
        XCTAssertEqual(step(0, .critical), [])
        XCTAssertEqual(step(20, .critical), [])
        XCTAssertEqual(step(30, .critical), [.raised])
        XCTAssertEqual(engine.activeRuleIDs, ["memory-critical"])
        // A brief recovery does not clear; returning to critical restarts the clear clock.
        XCTAssertEqual(step(31, .normal), [])
        XCTAssertEqual(step(40, .critical), [])
        XCTAssertEqual(step(41, .warning), [])
        // An unknown reading pauses the clock instead of counting toward a change.
        XCTAssertEqual(step(60, nil), [])
        XCTAssertEqual(step(65, .normal), [])
        XCTAssertEqual(step(94, .normal), [])
        XCTAssertEqual(step(95, .normal), [.cleared])
        XCTAssertTrue(engine.activeRuleIDs.isEmpty)
    }

    func testLowBatteryRaisesAtOnceAndNeedsDischarge() {
        var engine = AlertEngine(rules: AlertRules.shipped)
        let charging = engine.evaluate(inputs(battery: 10, onBattery: false), at: epoch)
        XCTAssertTrue(charging.isEmpty)
        let discharging = engine.evaluate(inputs(battery: 10, onBattery: true), at: epoch.addingTimeInterval(1))
        XCTAssertEqual(discharging.map(\.ruleID), ["battery-low"])
    }

    func testCooldownCollapsesRepeatNotifications() {
        var cooldown = AlertCooldown()
        XCTAssertTrue(cooldown.admit("memory-critical", at: epoch))
        XCTAssertFalse(cooldown.admit("memory-critical", at: epoch.addingTimeInterval(60)))
        XCTAssertTrue(cooldown.admit("battery-low", at: epoch.addingTimeInterval(60)))
        XCTAssertTrue(cooldown.admit("memory-critical", at: epoch.addingTimeInterval(AlertCooldown.interval)))
    }

    func testDeliveryAsksOnceAndPostsUnderTheRuleIdentifier() async {
        let denied = RecordingPoster(permission: false)
        let quiet = AlertDelivery(poster: denied)
        let first = await quiet.deliver(ruleID: "r", title: "t", body: "b")
        let second = await quiet.deliver(ruleID: "r", title: "t", body: "b")
        XCTAssertFalse(first || second)
        let deniedRequests = await denied.permissionRequests
        let deniedPosts = await denied.posts
        XCTAssertEqual(deniedRequests, 1)
        XCTAssertTrue(deniedPosts.isEmpty)

        let allowed = RecordingPoster(permission: true)
        let delivery = AlertDelivery(poster: allowed)
        let posted = await delivery.deliver(ruleID: "memory-critical", title: "t", body: "b")
        XCTAssertTrue(posted)
        let identifiers = await allowed.posts
        XCTAssertEqual(identifiers, ["coreography.alert.memory-critical"])
    }

    private func inputs(
        memory: MemoryPressureLevel? = nil, battery: Double? = nil, onBattery: Bool? = nil
    ) -> AlertInputs {
        AlertInputs(memoryPressure: memory, thermalPressure: nil, batteryPercent: battery, onBattery: onBattery)
    }
}

@MainActor
final class DashboardAlertTests: XCTestCase {
    func testSustainedCriticalPressureTintsTheLaneMarksAndNotifies() async throws {
        let poster = RecordingPoster(permission: true)
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: CriticalPressureDriver()), interval: .milliseconds(5),
            notifier: AlertDelivery(poster: poster)
        )
        model.start()
        defer { model.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.activeAlerts[.memory] == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.activeAlerts[.memory], "Critical memory pressure")
        XCTAssertTrue(model.markers.contains { $0.label == "Critical memory pressure" })
        var posts: [String] = []
        while posts.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            posts = await poster.posts
        }
        XCTAssertEqual(posts, ["coreography.alert.memory-critical"])
    }
}

private actor RecordingPoster: NotificationPosting {
    private let permission: Bool
    private(set) var permissionRequests = 0
    private(set) var posts: [String] = []

    init(permission: Bool) { self.permission = permission }

    func requestPermission() async -> Bool {
        permissionRequests += 1
        return permission
    }

    func post(identifier: String, title: String, body: String) async throws { posts.append(identifier) }
}

/// Critical pressure with ten wall-clock seconds per read.
private actor CriticalPressureDriver: HostSampleReading {
    private let clock = UUID()
    private var step: UInt64 = 0

    func read() async -> RawHostSnapshot {
        step += 1
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: step * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(step) * 10),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 1, physicalMemoryBytes: 1 << 20),
            cpu: .success(ProcessorTicks(user: step, system: 0, idle: step, nice: 0)),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0, wired: 1, compressed: 0, compressorContents: 0,
                purgeable: 0, fileBacked: 0, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 0, usedBytes: 0)),
            memoryPressure: .success(.critical), thermalPressure: .success(.nominal)
        )
    }
}
