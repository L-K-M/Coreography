import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class CoreHeatTests: XCTestCase {
    func testCellsSpanToTheNextSampleAndSkipUnreadCores() async throws {
        let monitor = try SystemMonitor(driver: TwoCores())
        var frames: [CapturedSnapshot] = []
        for _ in 0..<3 { frames.append(try await monitor.sample()) }
        let cells = CoreHeat.cells(frames, nominalSeconds: 2)
        XCTAssertEqual(cells.map(\.core), [0, 1, 0, 1], "the first sample is a baseline, so it draws nothing")
        XCTAssertEqual(cells.first?.busyPercent, 50)
        XCTAssertEqual(cells.first?.end, frames[2].stamp.wallTime, "a cell reaches the next sample")
        XCTAssertEqual(cells.last?.end, frames[2].stamp.wallTime.addingTimeInterval(2), "the newest spans one interval")
    }
}

private actor TwoCores: HostSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawHostSnapshot {
        reads += 1
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
            cores: .success([
                ProcessorTicks(user: reads * 10, system: 0, idle: reads * 10, nice: 0),
                ProcessorTicks(user: reads * 30, system: 0, idle: reads * 10, nice: 0)
            ])
        )
    }
}
