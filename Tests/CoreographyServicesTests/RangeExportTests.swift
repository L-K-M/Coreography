import Foundation
import CoreographyDrivers
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

@MainActor
final class RangeExportTests: XCTestCase {
    func testExportKeepsOnlyTheRangeAndRoundTripsAsJSON() async throws {
        let frames = try await hostFrames(count: 5)
        let range = frames[1].stamp.wallTime...frames[3].stamp.wallTime
        let document = RangeExport.document(
            range: range, model: DashboardFrames(host: frames, network: [], disks: [], gpu: [], power: [], sensors: []),
            apps: [AppRangeTotal(name: "App", cpuSeconds: 2, diskBytes: 0, isLowerBound: true)]
        )
        XCTAssertEqual(document.host.map(\.id), frames[1...3].map(\.id))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RangeExport.Document.self, from: try RangeExport.json(document))
        XCTAssertEqual(decoded.schemaVersion, RangeExport.schemaVersion)
        XCTAssertEqual(decoded.host.count, 3)
        XCTAssertEqual(decoded.apps.first?.isLowerBound, true)
    }

    func testCSVLeavesMissingReadingsEmptyNeverZero() async throws {
        let frames = try await hostFrames(count: 3)
        let document = RangeExport.document(
            range: frames[0].stamp.wallTime...frames[2].stamp.wallTime,
            model: DashboardFrames(host: frames, network: [], disks: [], gpu: [], power: [], sensors: []), apps: []
        )
        let lines = RangeExport.csv(document).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].hasPrefix("time,cpu_percent_of_machine,memory_used_bytes"))
        // The first sample has no CPU baseline yet, and no GPU, sensor or power frames exist.
        let first = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(first.count, 9)
        XCTAssertEqual(first[1], "")
        XCTAssertNotEqual(first[2], "")
        XCTAssertEqual(first[6], "")
        XCTAssertEqual(first[8], "")
    }

    private func hostFrames(count: Int) async throws -> [CapturedSnapshot] {
        let monitor = try SystemMonitor(driver: StepHostDriver())
        var frames: [CapturedSnapshot] = []
        for _ in 0..<count { frames.append(try await monitor.sample()) }
        return frames
    }
}

private actor StepHostDriver: HostSampleReading {
    private let clock = UUID()
    private var step: UInt64 = 0

    func read() async -> RawHostSnapshot {
        step += 1
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: step * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(step)),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 2, physicalMemoryBytes: 1 << 20),
            cpu: .success(ProcessorTicks(user: step, system: 0, idle: step, nice: 0)),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0, wired: 1, compressed: 0, compressorContents: 0,
                purgeable: 0, fileBacked: 0, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 0, usedBytes: 0)),
            memoryPressure: .success(.normal), thermalPressure: .success(.nominal)
        )
    }
}
