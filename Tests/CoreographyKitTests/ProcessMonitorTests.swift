import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class ProcessMonitorTests: XCTestCase {
    func testRatesUseEachProcessElapsedTimeAndWholeMachineCPU() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, cpu: 1_000_000_000, read: 100)]),
            fixture(time: 3, rows: [row(time: 3, cpu: 3_000_000_000, read: 1100)])
        ])
        let first = try await monitor.sample()
        XCTAssertEqual(first.processes.first?.cpuPercentOfMachine.availability, .collecting)
        let second = try await monitor.sample()
        let process = try XCTUnwrap(second.processes.first)
        XCTAssertEqual(process.cpuPercentOfMachine.numericValue, 25)
        XCTAssertEqual(process.diskReadBytesPerSecond.numericValue, 500)
        XCTAssertEqual(process.diskWriteBytesPerSecond.numericValue, 0)
        XCTAssertEqual(process.memoryFootprintBytes.numericValue, 4096)
    }

    func testBatchDurationDoesNotReplaceProcessSampleInterval() async throws {
        let monitor = try makeMonitor([
            fixture(time: 2, rows: [row(time: 1, cpu: 0, read: 0)]),
            fixture(time: 5, rows: [row(time: 3, cpu: 2_000_000_000, read: 200)])
        ])
        _ = try await monitor.sample()
        let second = try await monitor.sample()
        XCTAssertEqual(second.processes.first?.cpuPercentOfMachine.numericValue, 25)
        XCTAssertEqual(second.processes.first?.diskReadBytesPerSecond.numericValue, 100)
    }

    func testPIDReuseDoesNotInheritCounters() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, cpu: 8_000_000_000)]),
            fixture(time: 3, rows: [row(time: 3, start: 200, cpu: 1_000_000_000)])
        ])
        let first = try await monitor.sample()
        let second = try await monitor.sample()
        XCTAssertNotEqual(first.processes.first?.id, second.processes.first?.id)
        XCTAssertEqual(second.processes.first?.cpuPercentOfMachine.availability, .collecting)
        XCTAssertNil(second.processes.first?.diskReadBytesPerSecond.numericValue)
    }

    func testPermissionLossDropsBaselineAndNeverInventsZero() async throws {
        let denied = row(time: 3, failure: .restricted(code: 1))
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1)]),
            fixture(time: 3, rows: [denied]),
            fixture(time: 5, rows: [row(time: 5)])
        ])
        _ = try await monitor.sample()
        let restricted = try await monitor.sample()
        XCTAssertEqual(restricted.restrictedUsageCount, 1)
        XCTAssertEqual(restricted.processes.first?.memoryFootprintBytes.availability, .restricted)
        XCTAssertNil(restricted.processes.first?.cpuPercentOfMachine.numericValue)
        let recovered = try await monitor.sample()
        XCTAssertEqual(recovered.processes.first?.cpuPercentOfMachine.availability, .collecting)
    }

    func testProcessMissingFromOneEnumerationNeedsNewBaseline() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1)]), fixture(time: 3, rows: []),
            fixture(time: 5, rows: [row(time: 5)])
        ])
        _ = try await monitor.sample()
        let missing = try await monitor.sample()
        XCTAssertTrue(missing.processes.isEmpty)
        let returned = try await monitor.sample()
        XCTAssertEqual(returned.processes.first?.cpuPercentOfMachine.availability, .collecting)
    }

    func testSleepClockChangeAndCounterResetLeaveGaps() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, cpu: 100)]),
            fixture(time: 3, rows: [row(time: 3, cpu: 100)], wallTime: 3600),
            fixture(time: 5, rows: [row(time: 5, cpu: 90)], wallTime: 3602),
            fixture(time: 7, rows: [row(time: 7, cpu: 100)], wallTime: 3604, clock: UUID())
        ])
        _ = try await monitor.sample()
        let wake = try await monitor.sample()
        XCTAssertEqual(wake.continuity, .interrupted)
        XCTAssertEqual(wake.processes.first?.cpuPercentOfMachine.availability, .gap)
        XCTAssertEqual(wake.processes.first?.memoryFootprintBytes.availability, .measured)
        let reset = try await monitor.sample()
        XCTAssertEqual(reset.processes.first?.cpuPercentOfMachine.availability, .gap)
        let newClock = try await monitor.sample()
        XCTAssertEqual(newClock.processes.first?.diskReadBytesPerSecond.availability, .gap)
    }

    func testFailedEnumerationClearsBaselinesAndPreservesFailure() async throws {
        let failure = RawProcessSnapshot(
            clockID: Self.clock, monotonicNanoseconds: 3_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(3), logicalCPUCount: 4, collectorPID: 42,
            enumeration: .failure(.systemCall(operation: "proc_listpids", code: 5))
        )
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1)]), failure,
            fixture(time: 5, rows: [row(time: 5)])
        ])
        _ = try await monitor.sample()
        let failed = try await monitor.sample()
        XCTAssertEqual(failed.enumeration.availability, .unavailable)
        XCTAssertNil(failed.enumeration.numericValue)
        let recovered = try await monitor.sample()
        XCTAssertEqual(recovered.processes.first?.cpuPercentOfMachine.availability, .collecting)
    }

    func testCollectionCoverageIncludesDeniedIdentitiesAndTruncation() async throws {
        let sample = fixture(
            time: 1, rows: [row(time: 1)],
            failures: [ProcessReadFailure(pid: 99, error: .restricted(code: 1))], truncated: true
        )
        let result = try await makeMonitor([sample]).sample()
        XCTAssertEqual(result.enumeration.numericValue, 2)
        XCTAssertEqual(result.processes.count, 1)
        XCTAssertEqual(result.issues.first?.reading.availability, .restricted)
        XCTAssertTrue(result.enumerationTruncated)
    }

    func testMalformedIdentitiesAndOverflowCannotProduceMetrics() async throws {
        let invalid = RawProcessInfo(
            pid: -1, parentPID: 0, uid: 0, startSeconds: 0,
            startMicroseconds: 1_000_000, name: "Invalid", monotonicNanoseconds: 1,
            counters: .failure(.identityChanged)
        )
        let overflow = RawProcessInfo(
            pid: 42, parentPID: 1, uid: 501, startSeconds: 100, startMicroseconds: 0,
            name: "Overflow", monotonicNanoseconds: 1,
            counters: .success(ProcessCounters(
                userNanoseconds: .max, systemNanoseconds: 1,
                physicalFootprintBytes: 0, diskReadBytes: 0, diskWriteBytes: 0
            ))
        )
        let result = try await makeMonitor([fixture(time: 1, rows: [invalid, overflow])]).sample()
        XCTAssertEqual(result.processes.count, 1)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.processes.first?.cpuPercentOfMachine.availability, .gap)
        XCTAssertThrowsError(try JSONDecoder().decode(
            ProcessIdentity.self,
            from: Data(#"{"pid":42,"startSeconds":0,"startMicroseconds":1000000}"#.utf8)
        ))
    }

    func testRetainsTailProcessesRatherThanOnlyTopContributors() async throws {
        let rows = (1...120).map { row(pid: Int32($0), time: 1) }
        let result = try await makeMonitor([fixture(time: 1, rows: rows)]).sample()
        XCTAssertEqual(result.processes.count, 120)
    }

    func testNativeDriverReportsOwnIdentityOrExplicitUnsupportedState() async throws {
        let raw = await ProcessStatisticsDriver().read()
        #if os(macOS)
        let enumeration = try raw.enumeration.get()
        let own = try XCTUnwrap(enumeration.processes.first { $0.pid == raw.collectorPID })
        XCTAssertGreaterThan(own.startSeconds, 0)
        XCTAssertLessThan(own.startMicroseconds, 1_000_000)
        let counters = try own.counters.get()
        XCTAssertGreaterThan(counters.physicalFootprintBytes, 0)
        #else
        switch raw.enumeration {
        case .failure(.unsupportedPlatform): break
        default: XCTFail("Linux must not fabricate macOS process data")
        }
        #endif
    }

    private static let clock = UUID(uuidString: "AFAE41C6-793E-4A64-A545-66CFA34571EB")!
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeMonitor(_ samples: [RawProcessSnapshot]) throws -> ProcessMonitor {
        try ProcessMonitor(driver: FixtureProcessDriver(samples))
    }

    private func fixture(
        time: UInt64, rows: [RawProcessInfo], wallTime: UInt64? = nil,
        clock: UUID = ProcessMonitorTests.clock,
        failures: [ProcessReadFailure] = [], truncated: Bool = false
    ) -> RawProcessSnapshot {
        RawProcessSnapshot(
            clockID: clock, monotonicNanoseconds: time * 1_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(Double(wallTime ?? time)),
            logicalCPUCount: 4, collectorPID: 42,
            enumeration: .success(ProcessEnumeration(
                processes: rows, failures: failures, isTruncated: truncated
            ))
        )
    }

    private func row(
        pid: Int32 = 42, time: UInt64, start: UInt64 = 100,
        cpu: UInt64 = 0, read: UInt64 = 0, failure: ProcessDriverError? = nil
    ) -> RawProcessInfo {
        RawProcessInfo(
            pid: pid, parentPID: 1, uid: 501, startSeconds: start, startMicroseconds: 123,
            name: "Fixture \(pid)", monotonicNanoseconds: time * 1_000_000_000,
            counters: failure.map { .failure($0) } ?? .success(ProcessCounters(
                userNanoseconds: cpu, systemNanoseconds: 0, physicalFootprintBytes: 4096,
                diskReadBytes: read, diskWriteBytes: 0
            ))
        )
    }
}

private actor FixtureProcessDriver: ProcessSampleReading {
    private var samples: [RawProcessSnapshot]
    init(_ samples: [RawProcessSnapshot]) { self.samples = samples }
    func read() async -> RawProcessSnapshot {
        precondition(!samples.isEmpty, "Fixture exhausted")
        return samples.removeFirst()
    }
}
