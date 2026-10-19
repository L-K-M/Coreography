import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class CoreActivityTests: XCTestCase {
    /// Plan: a per-core heat strip. Each core's share is its own busy ticks over its own ticks.
    func testEachCoreReadsItsBusyShareAndAChangeOfCoresStartsOver() async throws {
        let monitor = try SystemMonitor(driver: Cores([
            [ticks(0, 0, 0), ticks(0, 0, 0)],
            [ticks(30, 10, 60), ticks(0, 0, 100)],
            [ticks(60, 20, 120), ticks(50, 0, 150)],
            [ticks(60, 20, 120)]
        ]))
        let first = try await monitor.sample()
        XCTAssertEqual(first.coreBusyPercent?.map(\.availability), [.collecting, .collecting], "a share needs a baseline")

        let second = try await monitor.sample()
        XCTAssertEqual(second.coreBusyPercent?.map(\.numericValue), [40, 0])
        let third = try await monitor.sample()
        XCTAssertEqual(third.coreBusyPercent?.map(\.numericValue), [40, 50])
        XCTAssertEqual(third.coreBusyPercent?.first?.availability, .measured)

        let fewer = try await monitor.sample()
        XCTAssertEqual(fewer.coreBusyPercent?.map(\.availability), [.collecting], "a different core count has no baseline")
    }

    func testAMonitorWithoutCoreCountersHasNoStrip() async throws {
        let monitor = try SystemMonitor(driver: Cores([]))
        let snapshot = try await monitor.sample()
        XCTAssertNil(snapshot.coreBusyPercent)
    }

    private func ticks(_ user: UInt64, _ system: UInt64, _ idle: UInt64) -> ProcessorTicks {
        ProcessorTicks(user: user, system: system, idle: idle, nice: 0)
    }
}

/// Replays per-core ticks one second apart; with none, reads as a Mac without them.
private actor Cores: HostSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0
    private var cores: [[ProcessorTicks]]

    init(_ cores: [[ProcessorTicks]]) { self.cores = cores }

    func read() async -> RawHostSnapshot {
        reads += 1
        let next: Result<[ProcessorTicks], HostDriverError> = cores.isEmpty ? .failure(.unsupportedPlatform) : .success(cores.removeFirst())
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 2, physicalMemoryBytes: 1 << 30),
            cpu: .success(ProcessorTicks(user: reads, system: 0, idle: reads, nice: 0)),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0, wired: 2, compressed: 3, compressorContents: 6, purgeable: 0,
                fileBacked: 1, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 8192, usedBytes: 0)),
            memoryPressure: .success(.normal), thermalPressure: .success(.nominal),
            cores: next
        )
    }
}
