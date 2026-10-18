import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class CPUSplitTests: XCTestCase {
    func testUserSitsUnderSystemAndGapsBreakTheArea() async throws {
        // Ticks per second: 30 user + 10 nice + 10 system of 100, then a sleep gap, then 20 + 0 + 20.
        let monitor = try SystemMonitor(driver: ScriptedTicks([
            (0, 0, (100, 50, 100, 10)), (1, 1, (130, 60, 150, 20)),
            (2, 3600, (150, 80, 210, 20)), (3, 3601, (170, 100, 270, 20))
        ]))
        var frames: [CapturedSnapshot] = []
        for _ in 0..<4 { frames.append(try await monitor.sample()) }

        let points = CPUSplit.points(frames)
        XCTAssertEqual(points.map(\.user), [40, 20])
        XCTAssertEqual(points.map(\.system), [10, 20])
        XCTAssertEqual(Set(points.map(\.segment)).count, 2, "the sleep gap starts a new area")
        XCTAssertNil(CPUSplit.split(frames[0]), "collecting has no split")
    }
}

/// Seconds on the uptime clock, wall seconds, and (user, system, idle, nice) ticks.
private actor ScriptedTicks: HostSampleReading {
    private let clock = UUID()
    private var script: [(UInt64, Double, (UInt64, UInt64, UInt64, UInt64))]

    init(_ script: [(UInt64, Double, (UInt64, UInt64, UInt64, UInt64))]) { self.script = script }

    func read() async -> RawHostSnapshot {
        let (seconds, wall, ticks) = script.removeFirst()
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: seconds * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + wall),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30),
            cpu: .success(ProcessorTicks(user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0, wired: 2, compressed: 3, compressorContents: 6, purgeable: 0,
                fileBacked: 1, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 8192, usedBytes: 0)),
            memoryPressure: .success(.normal), thermalPressure: .success(.nominal)
        )
    }
}
