import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

@MainActor
final class AccountNamingTests: XCTestCase {
    /// The first lookup can be slow on a directory service, so it runs off the
    /// main actor and the group reads its UID until the name arrives.
    func testTheByUserViewNamesTheCurrentAccountOnceLookedUp() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10),
            processMonitor: try ProcessMonitor(driver: Mine()), processInterval: .milliseconds(10)
        )
        model.processGrouping = .user
        model.start()
        defer { model.stop() }
        let expected = "You, \(NSUserName())"
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.visibleProcessRows.first?.name != expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.visibleProcessRows.first?.name, expected)
    }
}

/// One process of the user running the tests.
private actor Mine: ProcessSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawProcessSnapshot {
        reads += 1
        return RawProcessSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)), logicalCPUCount: 4, collectorPID: 42,
            enumeration: .success(ProcessEnumeration(processes: [RawProcessInfo(
                pid: 42, parentPID: 1, uid: UInt32(getuid()), startSeconds: 100, startMicroseconds: 0, name: "fixture",
                monotonicNanoseconds: reads * 1_000_000_000,
                counters: .success(ProcessCounters(userNanoseconds: reads, systemNanoseconds: 0, physicalFootprintBytes: 1, diskReadBytes: 0, diskWriteBytes: 0))
            )]))
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
