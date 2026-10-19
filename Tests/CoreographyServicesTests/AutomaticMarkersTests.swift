import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class AutomaticMarkersTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testMarksPressureChangesSkippingUnknownSamplesAndSleepSinceTheStart() async throws {
        // Pressure: normal, unknown, normal, warning, warning, normal.
        let levels: [KernelMemoryPressure?] = [.normal, nil, .normal, .warning, .warning, .normal]
        let monitor = try SystemMonitor(driver: Pressures(levels, epoch: epoch))
        var host: [CapturedSnapshot] = []
        for _ in levels { host.append(try await monitor.sample()) }

        let events = [
            PowerEvent(time: epoch.addingTimeInterval(-60), kind: .sleep, reason: nil, powerSource: nil, batteryPercent: nil),
            PowerEvent(time: epoch.addingTimeInterval(2), kind: .wake, reason: "Lid Open", powerSource: .battery, batteryPercent: 80)
        ]
        let markers = AutomaticMarkers.derive(host: host, power: [], sleepEvents: events, since: nil)
        XCTAssertEqual(markers.map(\.label), ["Wake: Lid Open", "Memory pressure warning", "Memory pressure normal"])
        XCTAssertEqual(markers.map(\.time), [epoch.addingTimeInterval(2), epoch.addingTimeInterval(3), epoch.addingTimeInterval(5)])
        XCTAssertTrue(markers.allSatisfy { $0.kind == .system })

        let again = AutomaticMarkers.derive(host: host, power: [], sleepEvents: events, since: nil)
        XCTAssertEqual(again.map(\.id), markers.map(\.id), "rebuilt markers keep their identity")

        let longer = AutomaticMarkers.derive(host: host, power: [], sleepEvents: events, since: epoch.addingTimeInterval(-3600))
        XCTAssertEqual(longer.first?.label, "Sleep", "the stored range reaches the earlier sleep")
    }

    func testSameTimeMarkersKeepOneOrderAndOneIdentity() {
        let wake = PowerEvent(time: epoch, kind: .wake, reason: "Lid Open", powerSource: nil, batteryPercent: nil)
        let darkWake = PowerEvent(time: epoch, kind: .darkWake, reason: nil, powerSource: nil, batteryPercent: nil)
        // An import can list one record twice; it is one marker, not two with one identity.
        let markers = AutomaticMarkers.derive(host: [], power: [], sleepEvents: [wake, darkWake, wake], since: .distantPast)
        let reversed = AutomaticMarkers.derive(host: [], power: [], sleepEvents: [darkWake, wake], since: .distantPast)
        XCTAssertEqual(markers.map(\.label), reversed.map(\.label), "ties break by label, not by input order")
        XCTAssertEqual(Set(markers.map(\.id)).count, markers.count)
        XCTAssertEqual(markers.count, 2)
    }
}

/// One host sample per second with the given kernel pressure; nil fails the read.
private actor Pressures: HostSampleReading {
    private let clock = UUID()
    private let levels: [KernelMemoryPressure?]
    private let epoch: Date
    private var step = 0

    init(_ levels: [KernelMemoryPressure?], epoch: Date) {
        self.levels = levels
        self.epoch = epoch
    }

    func read() async -> RawHostSnapshot {
        defer { step += 1 }
        let level = levels[min(step, levels.count - 1)]
        let pressure: Result<KernelMemoryPressure, HostDriverError> = level.map { .success($0) }
            ?? .failure(.systemCall(operation: "fixture", code: 5))
        let pages = MemoryPages(
            active: 10, inactive: 0, speculative: 0, wired: 2, compressed: 3, compressorContents: 6, purgeable: 0,
            fileBacked: 1, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
        )
        let inventory = HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30)
        let tick = UInt64(step)
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: (tick + 1) * 1_000_000_000, wallTime: epoch.addingTimeInterval(Double(step)),
            inventory: inventory, cpu: .success(ProcessorTicks(user: tick, system: 0, idle: tick, nice: 0)),
            memory: .success(pages), swap: .success(SwapUsage(totalBytes: 0, usedBytes: 0)),
            memoryPressure: pressure, thermalPressure: .success(.nominal)
        )
    }
}
