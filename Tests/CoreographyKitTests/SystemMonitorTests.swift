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
                compressed: 0, compressorContents: 0, purgeable: 1, fileBacked: 0,
                pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .failure(.systemCall(operation: "sysctl vm.swapusage", code: 12)),
            memoryPressure: .failure(.unexpectedValue(
                operation: "sysctl kern.memorystatus_vm_pressure_level", value: 8
            ))
        )
        let monitor = try SystemMonitor(driver: FixtureHostDriver(samples: [sample]))
        let result = try await monitor.sample()
        XCTAssertEqual(result.cpuPercentOfMachine.availability, .unavailable)
        XCTAssertNil(result.cpuPercentOfMachine.numericValue)
        XCTAssertNil(result.memoryUsedBytes.numericValue)
        XCTAssertEqual(result.memory.appBytes.availability, .unavailable)
        XCTAssertEqual(result.memory.compressionRatio.reason, "Compressor is empty")
        XCTAssertEqual(result.memory.swapUsedBytes.availability, .unavailable)
        XCTAssertEqual(result.memory.swapTotalBytes.availability, .unavailable)
        XCTAssertEqual(result.memory.pressure.availability, .unavailable)
        XCTAssertNil(result.memory.pressureLevel)
        XCTAssertEqual(
            result.memory.pressure.reason,
            "sysctl kern.memorystatus_vm_pressure_level returned unexpected value 8"
        )
    }

    func testMemoryDetailReportsCompositionSwapPressureAndPagingRates() async throws {
        let driver = FixtureHostDriver(samples: [
            fixture(seconds: 0, user: 0, idle: 0, pageIns: 100, swapIns: 0, swapOuts: 5),
            fixture(seconds: 2, user: 0, idle: 0, pageIns: 120, swapIns: 4, swapOuts: 5)
        ])
        let monitor = try SystemMonitor(driver: driver)
        let first = try await monitor.sample()
        XCTAssertEqual(first.memory.pageInBytesPerSecond.availability, .collecting)

        let detail = try await monitor.sample().memory
        let page = 16_384.0
        XCTAssertEqual(detail.appBytes.numericValue, 130 * page)
        XCTAssertEqual(detail.appBytes.availability, .estimated)
        XCTAssertEqual(detail.wiredBytes.numericValue, 20 * page)
        XCTAssertEqual(detail.wiredBytes.availability, .measured)
        XCTAssertEqual(detail.compressedBytes.numericValue, 30 * page)
        XCTAssertEqual(detail.cachedBytes.numericValue, 30 * page)
        XCTAssertEqual(detail.compressionRatio.numericValue, 3)
        XCTAssertEqual(detail.swapUsedBytes.numericValue, 1024)
        XCTAssertEqual(detail.swapTotalBytes.numericValue, 2048)
        XCTAssertEqual(detail.pressureLevel, .warning)
        XCTAssertEqual(detail.pressure.source?.channel, "kern.memorystatus_vm_pressure_level")
        // Counter deltas over the real two-second interval, in bytes.
        XCTAssertEqual(detail.pageInBytesPerSecond.numericValue, 10 * page)
        XCTAssertEqual(detail.swapInBytesPerSecond.numericValue, 2 * page)
        XCTAssertEqual(detail.swapOutBytesPerSecond.numericValue, 0)
    }

    func testSleepGapMakesPagingRatesGapsButKeepsMemoryGauges() async throws {
        let driver = FixtureHostDriver(samples: [
            fixture(seconds: 0, user: 0, idle: 0, pageIns: 100),
            fixture(seconds: 1, user: 0, idle: 0, pageIns: 900, wallSeconds: 3600),
            fixture(seconds: 2, user: 0, idle: 0, pageIns: 901, wallSeconds: 3601)
        ])
        let monitor = try SystemMonitor(driver: driver)
        _ = try await monitor.sample()
        let wake = try await monitor.sample()
        XCTAssertEqual(wake.memory.pageInBytesPerSecond.availability, .gap)
        XCTAssertEqual(wake.memory.swapInBytesPerSecond.availability, .gap)
        XCTAssertEqual(wake.memory.wiredBytes.numericValue, 20 * 16_384)
        let after = try await monitor.sample()
        XCTAssertEqual(after.memory.pageInBytesPerSecond.numericValue, 16_384)
    }

    func testKernelPressureLevelsDecodeOnlyKnownValues() {
        XCTAssertEqual(KernelMemoryPressure(dispatchLevel: 1), .normal)
        XCTAssertEqual(KernelMemoryPressure(dispatchLevel: 2), .warning)
        XCTAssertEqual(KernelMemoryPressure(dispatchLevel: 4), .critical)
        for unknown: UInt32 in [0, 3, 8, .max] {
            XCTAssertNil(KernelMemoryPressure(dispatchLevel: unknown))
        }
    }

    #if os(macOS)
    func testKernelPressureLevelsMatchPublicDispatchValues() {
        let events: [(DispatchSource.MemoryPressureEvent, KernelMemoryPressure)] = [
            (.normal, .normal), (.warning, .warning), (.critical, .critical)
        ]
        for (event, level) in events {
            XCTAssertEqual(KernelMemoryPressure(dispatchLevel: UInt32(event.rawValue)), level)
        }
    }

    func testNativeSwapAndPressureSourcesAreReadable() async throws {
        let raw = await HostStatisticsDriver().read()
        let swap = try raw.swap.get()
        XCTAssertLessThanOrEqual(swap.usedBytes, swap.totalBytes)
        XCTAssertNoThrow(try raw.memoryPressure.get())
        let pages = try raw.memory.get()
        XCTAssertGreaterThan(pages.pageIns, 0)
    }
    #endif

    private static let clock = UUID(uuidString: "AFAE41C6-793E-4A64-A545-66CFA34571EB")!
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private static let inventory = HostInventory(
        operatingSystem: "Fixture", architecture: "fixture",
        logicalCPUCount: 4, physicalMemoryBytes: 4_194_304
    )

    private func fixture(
        seconds: UInt64, user: UInt64, idle: UInt64, pageIns: UInt64 = 0,
        swapIns: UInt64 = 0, swapOuts: UInt64 = 0, wallSeconds: UInt64? = nil
    ) -> RawHostSnapshot {
        RawHostSnapshot(
            clockID: Self.clock, monotonicNanoseconds: seconds * 1_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(Double(wallSeconds ?? seconds)),
            inventory: Self.inventory,
            cpu: .success(ProcessorTicks(user: user, system: 0, idle: idle, nice: 0)),
            memory: .success(MemoryPages(
                active: 100, inactive: 50, speculative: 10, wired: 20,
                compressed: 30, compressorContents: 90, purgeable: 5, fileBacked: 25,
                pageIns: pageIns, swapIns: swapIns, swapOuts: swapOuts, pageSizeBytes: 16_384
            )),
            swap: .success(SwapUsage(totalBytes: 2048, usedBytes: 1024)),
            memoryPressure: .success(.warning)
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
