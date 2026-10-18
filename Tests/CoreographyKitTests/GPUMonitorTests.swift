import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class GPUMonitorTests: XCTestCase {
    func testDecoderReadsAGXKeysAndFallsBackToGPUActivity() throws {
        let agx = try GPUStatisticsDecoder.statistics([
            "Device Utilization %": NSNumber(value: 37), "Renderer Utilization %": NSNumber(value: 30),
            "Tiler Utilization %": NSNumber(value: 12), "In use system memory": NSNumber(value: UInt64(1 << 30))
        ]).get()
        XCTAssertEqual(agx, GPUStatistics(
            utilizationPercent: 37, rendererPercent: 30, tilerPercent: 12, inUseMemoryBytes: 1 << 30
        ))

        let amd = try GPUStatisticsDecoder.statistics(["GPU Activity(%)": NSNumber(value: 5)]).get()
        XCTAssertEqual(amd.utilizationPercent, 5)
        XCTAssertNil(amd.rendererPercent)
        XCTAssertNil(amd.inUseMemoryBytes)
    }

    func testDecoderRejectsMissingAndInvalidUtilization() {
        let invalid: [[String: Any]] = [
            [:],
            ["Device Utilization %": NSNumber(value: 101)],
            ["Device Utilization %": NSNumber(value: -1)],
            ["Device Utilization %": "37"],
            ["Device Utilization %": NSNumber(value: Double.nan)]
        ]
        for table in invalid {
            XCTAssertThrowsError(try GPUStatisticsDecoder.statistics(table).get(), "\(table)")
        }
        // Invalid optional fields are absent, never zero.
        let partial = try? GPUStatisticsDecoder.statistics([
            "Device Utilization %": NSNumber(value: 1), "Tiler Utilization %": NSNumber(value: 400),
            "In use system memory": NSNumber(value: 1.5)
        ]).get()
        XCTAssertNil(partial?.tilerPercent)
        XCTAssertNil(partial?.inUseMemoryBytes)
    }

    func testMonitorKeepsUnpublishedFieldsAndBadDevicesExplicit() async throws {
        let monitor = try GPUMonitor(driver: FixtureGPUDriver([
            snapshot(seconds: 0, devices: [
                RawGPUDevice(registryEntryID: 7, name: "Apple M4", statistics: .success(GPUStatistics(
                    utilizationPercent: 42, rendererPercent: nil, tilerPercent: 3, inUseMemoryBytes: 2048
                ))),
                RawGPUDevice(registryEntryID: 7, name: "Duplicate", statistics: .success(GPUStatistics(
                    utilizationPercent: 1, rendererPercent: nil, tilerPercent: nil, inUseMemoryBytes: nil
                ))),
                RawGPUDevice(registryEntryID: 9, name: "Unpublished", statistics: .failure(
                    .unavailable(reason: "GPU performance statistics are not published")
                ))
            ], failures: [.systemCall(operation: "IORegistryEntryGetRegistryEntryID", code: 5)])
        ]))
        let result = try await monitor.sample()

        XCTAssertEqual(result.enumeration.numericValue, 4)
        XCTAssertEqual(result.devices.map(\.name), ["Apple M4", "Unpublished"])
        XCTAssertEqual(result.issues.count, 2)
        let gpu = try XCTUnwrap(result.devices.first)
        XCTAssertEqual(gpu.utilizationPercent.numericValue, 42)
        XCTAssertEqual(gpu.utilizationPercent.availability, .measured)
        XCTAssertEqual(gpu.rendererPercent.availability, .unavailable)
        XCTAssertEqual(gpu.tilerPercent.numericValue, 3)
        XCTAssertEqual(gpu.inUseMemoryBytes.numericValue, 2048)
        XCTAssertEqual(result.devices.last?.utilizationPercent.reason, "GPU performance statistics are not published")
    }

    func testUnsupportedPlatformAndSleepGapsStayExplicit() async throws {
        let monitor = try GPUMonitor(driver: FixtureGPUDriver([
            snapshot(seconds: 0, devices: []),
            snapshot(seconds: 1, wallSeconds: 3600, devices: []),
            RawGPUSnapshot(
                clockID: Self.clock, monotonicNanoseconds: 2_000_000_000,
                wallTime: Self.epoch.addingTimeInterval(3601), enumeration: .failure(.unsupportedPlatform)
            )
        ]))
        _ = try await monitor.sample()
        let wake = try await monitor.sample()
        XCTAssertEqual(wake.continuity, .interrupted)
        let unsupported = try await monitor.sample()
        XCTAssertEqual(unsupported.enumeration.availability, .unsupported)
        XCTAssertTrue(unsupported.devices.isEmpty)
    }

    private static let clock = UUID(uuidString: "6C2C55A8-14B2-4D7E-9E1C-3B4C0D2F7A10")!
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(
        seconds: UInt64, wallSeconds: UInt64? = nil, devices: [RawGPUDevice], failures: [GPUDriverError] = []
    ) -> RawGPUSnapshot {
        RawGPUSnapshot(
            clockID: Self.clock, monotonicNanoseconds: seconds * 1_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(Double(wallSeconds ?? seconds)),
            enumeration: .success(GPUEnumeration(devices: devices, failures: failures))
        )
    }
}

private actor FixtureGPUDriver: GPUSampleReading {
    private var samples: [RawGPUSnapshot]
    init(_ samples: [RawGPUSnapshot]) { self.samples = samples }
    func read() async -> RawGPUSnapshot {
        precondition(!samples.isEmpty, "Fixture exhausted")
        return samples.removeFirst()
    }
}
