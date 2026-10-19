import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class SamplingCadenceTests: XCTestCase {
    @MainActor
    func testLowPowerModeHalvesTheCadenceAndSaysSo() async throws {
        let mode = SwitchableMode()
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Steady()), interval: .milliseconds(20),
            energyMode: EnergyModeMonitor(driver: mode)
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 2 }
        XCTAssertEqual(model.samplingCadence, .normal)
        XCTAssertEqual(model.samplingSeconds, 0.02, accuracy: 1e-9)

        mode.set(true)
        try await eventually { model.samplingCadence == .lowPower }
        XCTAssertEqual(model.samplingSeconds, 0.04, accuracy: 1e-9)

        mode.set(false)
        try await eventually { model.samplingCadence == .normal }
    }

    @MainActor
    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class SwitchableMode: EnergyModeReading, @unchecked Sendable {
    private let lock = NSLock()
    private var lowPower = false

    func set(_ value: Bool) { lock.withLock { lowPower = value } }
    func isLowPowerModeEnabled() -> Bool { lock.withLock { lowPower } }
}

private actor Steady: HostSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawHostSnapshot {
        reads += 1
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 20_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads) * 0.02),
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

final class WakeImportSpacingTests: XCTestCase {
    func testOneReimportPerMinuteHoweverOftenSamplingStalls() {
        var spacing = WakeImportSpacing()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(spacing.admit(at: start))
        XCTAssertFalse(spacing.admit(at: start.addingTimeInterval(5)))
        XCTAssertFalse(spacing.admit(at: start.addingTimeInterval(59)))
        XCTAssertTrue(spacing.admit(at: start.addingTimeInterval(60)))
    }
}
