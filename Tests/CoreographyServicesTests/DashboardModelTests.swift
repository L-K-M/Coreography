import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

@MainActor
final class DashboardModelTests: XCTestCase {
    func testHoldingDisplayDoesNotPauseCollection() async throws {
        let driver = IncreasingHostDriver()
        let monitor = try SystemMonitor(driver: driver)
        let model = DashboardModel(monitor: monitor, interval: .milliseconds(10))
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 2 }

        model.toggleDisplayHold()
        let held = model.frames.last?.id
        let heldTime = model.latest?.stamp.wallTime
        let heldPoints = model.points(for: .memory).map(\.time)
        let before = await driver.readCount
        try await eventually { await driver.readCount >= before + 65 }
        XCTAssertEqual(model.frames.last?.id, held)
        XCTAssertEqual(model.latest?.stamp.wallTime, heldTime)
        XCTAssertEqual(model.points(for: .memory).map(\.time), heldPoints)

        model.toggleDisplayHold()
        XCTAssertNotEqual(model.frames.last?.id, held)
        XCTAssertEqual(model.displayMode, .live)
    }

    func testMemorySeriesDoesNotBridgeSamplingGaps() async throws {
        let driver = IncreasingHostDriver()
        let monitor = try SystemMonitor(driver: driver)
        let model = DashboardModel(monitor: monitor, interval: .milliseconds(10))
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 2 }
        await driver.skipWallTime()
        try await eventually { model.frames.contains { $0.continuity == .interrupted } }

        let points = model.points(for: .memory)
        XCTAssertGreaterThan(Set(points.map(\.segment)).count, 1)
        XCTAssertEqual(points.count, model.frames.count)
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true before the deadline")
        throw CancellationError()
    }
}

private actor IncreasingHostDriver: HostSampleReading {
    private let clock = UUID()
    private var wallOffset: TimeInterval = 0
    private(set) var readCount: UInt64 = 0

    func skipWallTime() { wallOffset += 3600 }

    func read() async -> RawHostSnapshot {
        readCount += 1
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: readCount * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(readCount) + wallOffset),
            inventory: HostInventory(
                operatingSystem: "Fixture", architecture: "fixture",
                logicalCPUCount: 4, physicalMemoryBytes: 4096 * 100
            ),
            cpu: .success(ProcessorTicks(
                user: readCount, system: 0, idle: readCount * 3, nice: 0
            )),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0,
                wired: 0, compressed: 0, purgeable: 0,
                fileBacked: 0, pageSizeBytes: 4096
            ))
        )
    }
}
