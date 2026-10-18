import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class DiskMonitorTests: XCTestCase {
    func testStatisticsDecoderPreservesUnsignedCountersAndMeasuredZero() throws {
        let wide = (UInt64(1) << 60) + 7
        let counters = try DiskStatisticsDecoder.counters([
            "Bytes (Read)": NSNumber(value: wide), "Bytes (Write)": NSNumber(value: UInt64.max)
        ]).get()
        XCTAssertEqual(counters.readBytes, wide)
        XCTAssertEqual(counters.writtenBytes, UInt64.max)
        let idle = try DiskStatisticsDecoder.counters([
            "Bytes (Read)": NSNumber(value: 0), "Bytes (Write)": NSNumber(value: 0)
        ]).get()
        XCTAssertEqual(idle.readBytes, 0)
    }

    func testStatisticsDecoderRejectsMissingBooleanFractionalAndNegativeData() {
        for bad in [NSNumber(value: true), NSNumber(value: 1.5), NSNumber(value: 12.0),
                    NSNumber(value: -1), NSNumber(value: Double.infinity)] {
            let result = DiskStatisticsDecoder.counters([
                "Bytes (Read)": bad, "Bytes (Write)": NSNumber(value: 10)
            ])
            XCTAssertThrowsError(try result.get())
        }
        XCTAssertThrowsError(try DiskStatisticsDecoder.counters([:]).get())
    }

    func testRatesUseDeviceIntervalsAndCountersBeyondFourGiB() async throws {
        let wide = UInt64(1) << 40
        let monitor = try makeMonitor([
            sample(time: 2, devices: [device(time: 1, read: wide, written: wide)]),
            sample(time: 5, devices: [device(time: 3, read: wide + 4000, written: wide + 2000)])
        ])
        let first = try await monitor.sample()
        XCTAssertEqual(first.devices.first?.readBytesPerSecond.availability, .collecting)
        let measured = try await monitor.sample()
        XCTAssertEqual(measured.devices.first?.readBytesPerSecond.numericValue, 2000)
        XCTAssertEqual(measured.devices.first?.writtenBytesPerSecond.numericValue, 1000)
    }

    func testRegistryIdentityKeepsDevicesSeparateAndNameChangesDoNotResetIt() async throws {
        let monitor = try makeMonitor([
            sample(time: 1, devices: [device(id: 1, time: 1), device(id: 2, time: 1)]),
            sample(time: 2, devices: [device(id: 1, name: "Renamed", time: 2, read: 100),
                                      device(id: 2, time: 2, read: 200)])
        ])
        _ = try await monitor.sample()
        let next = try await monitor.sample()
        XCTAssertEqual(next.devices.map(\.readBytesPerSecond.numericValue), [100, 200])
        XCTAssertEqual(next.devices.first?.name, "Renamed")
    }

    func testMissingAndRestrictedDevicesDropRateBaselines() async throws {
        let monitor = try makeMonitor([
            sample(time: 1, devices: [device(time: 1)]),
            sample(time: 2, devices: [device(time: 2, error: .restricted(code: 1))]),
            sample(time: 3, devices: [device(time: 3, read: 5000)]),
            sample(time: 4, devices: []),
            sample(time: 5, devices: [device(time: 5, read: 9000)])
        ])
        _ = try await monitor.sample()
        let denied = try await monitor.sample()
        XCTAssertEqual(denied.devices.first?.readBytesPerSecond.availability, .restricted)
        XCTAssertNil(denied.devices.first?.readBytesPerSecond.numericValue)
        let restored = try await monitor.sample()
        XCTAssertEqual(restored.devices.first?.readBytesPerSecond.availability, .collecting)
        _ = try await monitor.sample()
        let reappeared = try await monitor.sample()
        XCTAssertEqual(reappeared.devices.first?.readBytesPerSecond.availability, .collecting)
    }

    func testCounterResetSleepAndClockChangeRemainGaps() async throws {
        let monitor = try makeMonitor([
            sample(time: 1, devices: [device(time: 1, read: 100)]),
            sample(time: 2, devices: [device(time: 2, read: 1)]),
            sample(time: 3, devices: [device(time: 3, read: 50)], wall: 3600),
            sample(time: 4, devices: [device(time: 4, read: 100)], wall: 3601, clock: UUID())
        ])
        _ = try await monitor.sample()
        let reset = try await monitor.sample()
        XCTAssertEqual(reset.devices.first?.readBytesPerSecond.availability, .gap)
        let wake = try await monitor.sample()
        XCTAssertEqual(wake.continuity, .interrupted)
        XCTAssertNil(wake.devices.first?.writtenBytesPerSecond.numericValue)
        let newClock = try await monitor.sample()
        XCTAssertEqual(newClock.devices.first?.readBytesPerSecond.availability, .gap)
        let history = await monitor.history()
        XCTAssertEqual(history.count, 1)
    }

    func testEnumerationFailureAndIncompleteInventoryStayExplicit() async throws {
        let failed = RawDiskSnapshot(
            clockID: Self.clock, monotonicNanoseconds: 2_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(2),
            enumeration: .failure(.systemCall(operation: "IOServiceGetMatchingServices", code: 5))
        )
        let partial = RawDiskSnapshot(
            clockID: Self.clock, monotonicNanoseconds: 3_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(3),
            enumeration: .success(DiskEnumeration(
                devices: [device(time: 3)],
                failures: [DiskReadFailure(registryEntryID: nil, error: .unavailable(reason: "No identity"))],
                isTruncated: true
            ))
        )
        let monitor = try makeMonitor([sample(time: 1, devices: [device(time: 1)]), failed, partial])
        _ = try await monitor.sample()
        let failure = try await monitor.sample()
        XCTAssertEqual(failure.enumeration.availability, .unavailable)
        XCTAssertTrue(failure.devices.isEmpty)
        let recovered = try await monitor.sample()
        XCTAssertTrue(recovered.enumerationTruncated)
        XCTAssertEqual(recovered.issues.count, 1)
        XCTAssertEqual(recovered.devices.first?.readBytesPerSecond.availability, .collecting)
    }

    func testInvalidAndDuplicateRegistryEntriesAreNotMeasurements() async throws {
        let snapshot = sample(time: 1, devices: [device(id: 0, time: 1), device(time: 1), device(time: 1)])
        let result = try await makeMonitor([snapshot]).sample()
        XCTAssertEqual(result.devices.count, 1)
        XCTAssertEqual(result.issues.count, 2)
        XCTAssertThrowsError(try JSONDecoder().decode(
            StorageDeviceID.self, from: Data(#"{"registryEntryID":0}"#.utf8)
        ))
    }

    func testNativeDiskDriverExposesRealInventoryOrExplicitUnsupportedState() async throws {
        let raw = await DiskIODriver().read()
        #if os(macOS)
        let inventory = try raw.enumeration.get()
        XCTAssertTrue(inventory.devices.allSatisfy { $0.registryEntryID > 0 && !$0.name.isEmpty })
        // Virtualized CI may expose no matching storage driver; that is not zero I/O.
        #else
        switch raw.enumeration {
        case .failure(.unsupportedPlatform): break
        default: XCTFail("Linux must not invent Mac storage readings")
        }
        #endif
    }

    private static let clock = UUID(uuidString: "AFAE41C6-793E-4A64-A545-66CFA34571EB")!
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeMonitor(_ samples: [RawDiskSnapshot]) throws -> DiskMonitor {
        try DiskMonitor(driver: FixtureDiskDriver(samples))
    }

    private func sample(
        time: UInt64, devices: [RawDiskDevice], wall: UInt64? = nil, clock: UUID = DiskMonitorTests.clock
    ) -> RawDiskSnapshot {
        RawDiskSnapshot(
            clockID: clock, monotonicNanoseconds: time * 1_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(Double(wall ?? time)),
            enumeration: .success(DiskEnumeration(devices: devices))
        )
    }

    private func device(
        id: UInt64 = 1, name: String = "Storage fixture", time: UInt64,
        read: UInt64 = 0, written: UInt64 = 0, error: DiskDriverError? = nil
    ) -> RawDiskDevice {
        RawDiskDevice(
            registryEntryID: id, name: name, monotonicNanoseconds: time * 1_000_000_000,
            counters: error.map { .failure($0) }
                ?? .success(DiskByteCounters(readBytes: read, writtenBytes: written))
        )
    }
}

private actor FixtureDiskDriver: DiskSampleReading {
    private var samples: [RawDiskSnapshot]
    init(_ samples: [RawDiskSnapshot]) { self.samples = samples }
    func read() async -> RawDiskSnapshot {
        precondition(!samples.isEmpty, "Fixture exhausted")
        return samples.removeFirst()
    }
}
