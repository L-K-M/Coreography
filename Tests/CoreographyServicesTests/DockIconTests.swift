import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class DockIconTests: XCTestCase {
    func testStyleIsSavedAndTheAppIconIsTheDefault() throws {
        let suite = "DockIconTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(DockIconStyle.saved(in: defaults), .appIcon)
        DockIconStyle.memory.save(in: defaults)
        XCTAssertEqual(DockIconStyle.saved(in: defaults), .memory)
        XCTAssertNil(DockIconStyle.appIcon.metric)
        XCTAssertEqual(DockIconStyle.cpu.metric, .cpu)
    }

    @MainActor
    func testTheGraphFollowsLiveSamplesWhileTheWindowIsHeld() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Ticking()), interval: .milliseconds(10))
        model.dockIcon = .cpu
        defer { model.dockIcon = .appIcon }
        XCTAssertTrue(model.dockIconPoints.isEmpty, "no samples, no graph")
        model.start()
        defer { model.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.dockIconPoints.count < 3, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }

        model.toggleDisplayHold()
        let held = model.dockIconPoints.count
        while model.dockIconPoints.count <= held, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertGreaterThan(model.dockIconPoints.count, held, "the Dock shows now, not the held window")
        XCTAssertEqual(model.dockIconScale, 100)
        XCTAssertTrue(model.dockIconPoints.allSatisfy { (0...100).contains($0.value) })
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
