import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class InspectorHistoryTests: XCTestCase {
    @MainActor
    func testTheSelectedProcessIsRecordedFromSelectionAndClearedOnChange() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10),
            processMonitor: try ProcessMonitor(driver: TwoProcesses()), processInterval: .milliseconds(10),
            inspector: ProcessInspector(driver: Threads())
        )
        model.start()
        defer { model.stop() }
        func wait(until done: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !done(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        }
        try await wait { model.processSnapshot?.processes.contains { $0.id.pid == 42 } == true }
        XCTAssertTrue(model.selectedProcessHistory.isEmpty, "nothing is recorded before a selection")

        let first = try XCTUnwrap(model.processSnapshot?.processes.first { $0.id.pid == 42 })
        model.selectedProcessRow = ProcessGroups.rowID(first)
        try await wait { model.selectedProcessHistory.count >= 3 && model.processDetail != nil }
        XCTAssertGreaterThanOrEqual(model.selectedProcessHistory.count, 3)
        XCTAssertNotNil(model.selectedProcessHistory.last?.cpuPercent)
        XCTAssertGreaterThanOrEqual(model.processDetail?.threads ?? 0, 7)

        // The fixture's thread count grows with each read, and PID 42 skips every fifth sample.
        try await wait { (model.processDetail?.threads ?? 0) > 8 && Set(model.selectedProcessHistory.map(\.segment)).count > 1 }
        XCTAssertGreaterThan(model.processDetail?.threads ?? 0, 8, "threads are reread while selected")
        XCTAssertGreaterThan(Set(model.selectedProcessHistory.map(\.segment)).count, 1, "a skipped sample is a gap, not a bridge")

        let other = try XCTUnwrap(model.processSnapshot?.processes.first { $0.id.pid == 43 })
        model.selectedProcessRow = ProcessGroups.rowID(other)
        XCTAssertLessThanOrEqual(model.selectedProcessHistory.count, 1, "a new selection starts its own history")
    }
}

private actor Threads: ProcessDetailReading {
    private var reads = 0

    func arguments(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<[String], ProcessDetailError> {
        .success([])
    }

    func signing(path: String) async -> CodeSigning { CodeSigning(signature: .unknown, identifier: nil, teamID: nil) }

    func threads(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<Int, ProcessDetailError> {
        reads += 1
        return .success(6 + reads)
    }
}

private actor TwoProcesses: ProcessSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawProcessSnapshot {
        reads += 1
        func process(_ pid: Int32) -> RawProcessInfo {
            RawProcessInfo(
                pid: pid, parentPID: 1, uid: 501, startSeconds: 100, startMicroseconds: 0, name: "p\(pid)",
                monotonicNanoseconds: reads * 1_000_000_000,
                counters: .success(ProcessCounters(userNanoseconds: reads * 1_000_000, systemNanoseconds: 0, physicalFootprintBytes: 1, diskReadBytes: 0, diskWriteBytes: 0))
            )
        }
        return RawProcessSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)), logicalCPUCount: 4, collectorPID: 42,
            enumeration: .success(ProcessEnumeration(processes: reads.isMultiple(of: 5) ? [process(43)] : [process(42), process(43)]))
        )
    }
}

private actor Host: HostSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawHostSnapshot {
        reads += 1
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)),
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 4, physicalMemoryBytes: 1 << 30),
            cpu: .success(ProcessorTicks(user: reads, system: 0, idle: reads * 3, nice: 0)),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0, wired: 2, compressed: 3, compressorContents: 6, purgeable: 0,
                fileBacked: 1, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 8192, usedBytes: 0)),
            memoryPressure: .success(.normal), thermalPressure: .success(.nominal)
        )
    }
}
