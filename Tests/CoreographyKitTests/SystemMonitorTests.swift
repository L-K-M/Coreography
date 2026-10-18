import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class SystemMonitorTests: XCTestCase {
    func testRealIntervalsProduceWholeMachineCPUAndBoundedHistory() async throws {
        let driver = FixtureHostDriver(samples: [
            fixture(seconds: 0, user: 100, idle: 100),
            fixture(seconds: 1, user: 125, idle: 175),
            fixture(seconds: 2, user: 125, idle: 275)
        ])
        let monitor = try SystemMonitor(driver: driver, historyCapacity: 2)

        let first = try await monitor.sample()
        XCTAssertEqual(first.cpuPercentOfMachine.availability, .collecting)
        let busy = try await monitor.sample()
        XCTAssertEqual(busy.cpuPercentOfMachine.numericValue, 25)
        let idle = try await monitor.sample()
        XCTAssertEqual(idle.cpuPercentOfMachine.numericValue, 0)
        let history = await monitor.history()
        XCTAssertEqual(history.map(\.id), [busy.id, idle.id])
    }

    func testSleepGapDoesNotBecomeAnIdleReading() async throws {
        let before = fixture(seconds: 0, user: 100, idle: 100)
        let after = fixture(seconds: 1, user: 100, idle: 200, wallSeconds: 3600)
        let driver = FixtureHostDriver(samples: [before, after])
        let monitor = try SystemMonitor(driver: driver)
        _ = try await monitor.sample()
        let wake = try await monitor.sample()
        XCTAssertEqual(wake.cpuPercentOfMachine.availability, .gap)
        XCTAssertNil(wake.cpuPercentOfMachine.numericValue)
    }

    func testDeniedAndMalformedSourcesHaveNoInventedValues() async throws {
        let sample = RawHostSnapshot(
            clockID: Self.clock, monotonicNanoseconds: 1, wallTime: Self.epoch,
            inventory: Self.inventory,
            cpu: .failure(.systemCall(operation: "host_statistics", code: 5)),
            memory: .success(MemoryPages(
                active: 0, inactive: 0, speculative: 0, wired: 0,
                compressed: 0, purgeable: 1, fileBacked: 0, pageSizeBytes: 4096
            ))
        )
        let monitor = try SystemMonitor(driver: FixtureHostDriver(samples: [sample]))
        let result = try await monitor.sample()
        XCTAssertEqual(result.cpuPercentOfMachine.availability, .unavailable)
        XCTAssertNil(result.cpuPercentOfMachine.numericValue)
        XCTAssertNil(result.memoryUsedBytes.numericValue)
    }

    private static let clock = UUID(uuidString: "AFAE41C6-793E-4A64-A545-66CFA34571EB")!
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private static let inventory = HostInventory(
        operatingSystem: "Fixture", architecture: "fixture",
        logicalCPUCount: 4, physicalMemoryBytes: 4_194_304
    )

    private func fixture(
        seconds: UInt64, user: UInt64, idle: UInt64, wallSeconds: UInt64? = nil
    ) -> RawHostSnapshot {
        RawHostSnapshot(
            clockID: Self.clock, monotonicNanoseconds: seconds * 1_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(Double(wallSeconds ?? seconds)),
            inventory: Self.inventory,
            cpu: .success(ProcessorTicks(user: user, system: 0, idle: idle, nice: 0)),
            memory: .success(MemoryPages(
                active: 100, inactive: 50, speculative: 10, wired: 20,
                compressed: 30, purgeable: 5, fileBacked: 25, pageSizeBytes: 16_384
            ))
        )
    }
}

private actor FixtureHostDriver: HostSampleReading {
    private var samples: [RawHostSnapshot]

    init(samples: [RawHostSnapshot]) { self.samples = samples }

    func read() async -> RawHostSnapshot {
        precondition(!samples.isEmpty, "Fixture exhausted")
        return samples.removeFirst()
    }
}
