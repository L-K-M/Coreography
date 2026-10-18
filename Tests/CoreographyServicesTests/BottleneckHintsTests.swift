import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class BottleneckHintsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let clock = UUID()

    func testPinnedGPUWithIdlePerformanceCoresLooksGPUBound() throws {
        let hints = try evaluate(gpuBusy: 97, topActive: 30, frequency: 2000, maximum: 3200)
        XCTAssertEqual(hints.map(\.kind), [.gpuBound])
        XCTAssertEqual(hints.first?.evidence, ["GPU busy 97% (at least 90%)", "P cores 30% active (at most 50%)"])
    }

    func testSaturatedTopTierAtFullSpeedWithGPUHeadroomLooksCPUBound() throws {
        XCTAssertEqual(try evaluate(gpuBusy: 40, topActive: 95, frequency: 3150, maximum: 3200).map(\.kind), [.cpuBound])
        XCTAssertTrue(try evaluate(gpuBusy: 40, topActive: 95, frequency: 2400, maximum: 3200).isEmpty,
                      "busy below top frequency is not flat out")
        XCTAssertTrue(try evaluate(gpuBusy: 40, topActive: 95, frequency: 3150, maximum: nil).isEmpty,
                      "without the tier's table there is no top frequency to compare")
    }

    func testFallingFrequencyUnderThermalPressureMayBeThrottling() throws {
        let hints = try evaluate(gpuBusy: 60, topActive: 80, frequency: 2400, maximum: 3200, earlier: 3200, thermal: .heavy)
        XCTAssertEqual(hints.map(\.kind), [.throttling])
        XCTAssertEqual(hints.first?.evidence.first, "Thermal pressure heavy")
        XCTAssertTrue(try evaluate(gpuBusy: 60, topActive: 80, frequency: 2400, maximum: 3200, earlier: 3200, thermal: .nominal).isEmpty,
                      "a drop without thermal pressure is just less work")
    }

    func testNoReadingsNoHints() {
        XCTAssertTrue(BottleneckHints.evaluate(gpu: [], silicon: [], thermal: nil, now: epoch).isEmpty)
    }

    // MARK: Fixtures

    /// Five recent seconds at `frequency`, five earlier ones at `earlier`.
    private func evaluate(
        gpuBusy: Double, topActive: Double, frequency: Double, maximum: Double?, earlier: Double? = nil,
        thermal: ThermalPressureLevel = .nominal
    ) throws -> [BottleneckHint] {
        let now = epoch.addingTimeInterval(10)
        let silicon = try (1...10).map { second in
            try siliconFrame(at: Double(second), active: topActive, frequency: second <= 5 ? (earlier ?? frequency) : frequency, maximum: maximum)
        }
        let gpu = try (6...10).map { try gpuFrame(at: Double($0), busy: gpuBusy) }
        return BottleneckHints.evaluate(gpu: gpu, silicon: silicon, thermal: thermal, now: now)
    }

    private func stamp(_ second: Double) -> SampleStamp {
        SampleStamp(clockID: clock, monotonicNanoseconds: UInt64(second * 1e9), wallTime: epoch.addingTimeInterval(second))
    }

    private func siliconFrame(at second: Double, active: Double, frequency: Double, maximum: Double?) throws -> CapturedSilicon {
        let watts = try MetricReading.estimated(1, method: "test")
        return SiliconSnapshot(
            id: UUID(), stamp: stamp(second), cpuPowerWatts: watts, gpuPowerWatts: watts, anePowerWatts: watts,
            dramPowerWatts: watts,
            cpuTiers: [CPUTierReading(
                kind: .p, cores: 4, activePercent: try .estimated(active, method: "test"),
                frequencyMHz: try .estimated(frequency, method: "test"), maximumMHz: maximum
            )],
            gpuActivePercent: watts, gpuFrequencyMHz: watts, continuity: .continuous
        )
    }

    private func gpuFrame(at second: Double, busy: Double) throws -> CapturedGPU {
        let reading = try MetricReading.measured(busy)
        return GPUSnapshot(
            id: UUID(), stamp: stamp(second), enumeration: try .measured(1), enumerationTruncated: false,
            devices: [GPUDeviceReading(
                id: try GPUDeviceID(registryEntryID: 1), name: "GPU", utilizationPercent: reading,
                rendererPercent: reading, tilerPercent: reading, inUseMemoryBytes: try .measured(0)
            )],
            issues: [], continuity: .continuous
        )
    }
}
