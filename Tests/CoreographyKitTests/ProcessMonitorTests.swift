import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class ProcessMonitorTests: XCTestCase {
    func testSaturatedCPURoundingStaysMeasuredButExcessUsageIsAGap() async throws {
        let elapsed: UInt64 = 1_500_000_015
        func sample(at time: UInt64, cpu: UInt64) -> RawProcessSnapshot {
            RawProcessSnapshot(
                clockID: Self.clock, monotonicNanoseconds: time,
                wallTime: Self.epoch.addingTimeInterval(Double(time) / 1_000_000_000),
                logicalCPUCount: 4, collectorPID: 42,
                enumeration: .success(ProcessEnumeration(processes: [RawProcessInfo(
                    pid: 42, parentPID: 1, uid: 501, startSeconds: 100,
                    startMicroseconds: 0, name: "Saturated fixture", monotonicNanoseconds: time,
                    counters: .success(ProcessCounters(
                        userNanoseconds: cpu, systemNanoseconds: 0,
                        physicalFootprintBytes: 4096, diskReadBytes: 0, diskWriteBytes: 0
                    ))
                )]))
            )
        }
        let monitor = try makeMonitor([
            sample(at: 0, cpu: 0), sample(at: elapsed, cpu: elapsed * 4),
            sample(at: elapsed * 2, cpu: elapsed * 12)
        ])
        _ = try await monitor.sample()
        let saturated = try await monitor.sample()
        XCTAssertEqual(saturated.processes.first?.cpuPercentOfMachine.availability, .measured)
        XCTAssertEqual(saturated.processes.first?.cpuPercentOfMachine.numericValue, 100)
        let impossible = try await monitor.sample()
        XCTAssertEqual(impossible.processes.first?.cpuPercentOfMachine.availability, .gap)
        XCTAssertNil(impossible.processes.first?.cpuPercentOfMachine.numericValue)
    }

    func testRatesUseEachProcessElapsedTimeAndWholeMachineCPU() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, cpu: 1_000_000_000, read: 100, wakeups: 10)]),
            fixture(time: 3, rows: [row(time: 3, cpu: 3_000_000_000, read: 1100, wakeups: 30)])
        ])
        let first = try await monitor.sample()
        XCTAssertEqual(first.processes.first?.cpuPercentOfMachine.availability, .collecting)
        XCTAssertEqual(first.processes.first?.wakeupsPerSecond.availability, .collecting)
        XCTAssertEqual(first.processes.first?.cpuTimeSeconds.numericValue, 1, "lifetime CPU time needs no baseline")
        XCTAssertEqual(first.processes.first?.threadCount.numericValue, 7, "a thread count needs no baseline")
        let second = try await monitor.sample()
        let process = try XCTUnwrap(second.processes.first)
        XCTAssertEqual(process.cpuPercentOfMachine.numericValue, 25)
        XCTAssertEqual(process.diskReadBytesPerSecond.numericValue, 500)
        XCTAssertEqual(process.diskWriteBytesPerSecond.numericValue, 0)
        XCTAssertEqual(process.memoryFootprintBytes.numericValue, 4096)
        XCTAssertEqual(process.wakeupsPerSecond.numericValue, 10, "20 wakeups over 2 s")
        XCTAssertEqual(process.cpuTimeSeconds.numericValue, 3)
        XCTAssertEqual(process.cpuTimeSeconds.availability, .measured)
    }

    /// Another user's task info needs the helper; its count is restricted, not zero.
    func testAnUnreadableThreadCountIsRestricted() async throws {
        let monitor = try makeMonitor([fixture(time: 1, rows: [row(time: 1, threads: .failure(.restricted(code: 1)))])])
        let sample = try await monitor.sample()
        let process = try XCTUnwrap(sample.processes.first)
        XCTAssertEqual(process.threadCount.availability, .restricted)
        XCTAssertNil(process.threadCount.numericValue)
        XCTAssertEqual(process.memoryFootprintBytes.numericValue, 4096, "the other readings stand")
    }

    func testTheCPUTypeNamesTheArchitectureAndAFailureNamesNone() async throws {
        let monitor = try makeMonitor([fixture(time: 1, rows: [
            row(pid: 1, time: 1), row(pid: 2, time: 1, cpuType: .success(.x86_64Translated)),
            row(pid: 3, time: 1, cpuType: .success(.x86_64)), row(pid: 4, time: 1, cpuType: .failure(.disappeared))
        ])])
        let sample = try await monitor.sample()
        XCTAssertEqual(sample.processes.map(\.architecture), [.appleSilicon, .intelTranslated, .intel, nil])
    }

    func testPowerIsAnEstimateFromTheEnergyCounter() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, cpu: 1_000_000_000, energy: 1_000_000_000)]),
            fixture(time: 3, rows: [row(time: 3, cpu: 2_000_000_000, energy: 4_000_000_000)])
        ])
        let first = try await monitor.sample()
        XCTAssertEqual(first.processes.first?.cpuPowerWatts.availability, .collecting)
        let second = try await monitor.sample()
        let power = try XCTUnwrap(second.processes.first?.cpuPowerWatts)
        XCTAssertEqual(power.availability, .estimated)
        XCTAssertEqual(power.numericValue, 1.5, "3 J over 2 s")
        XCTAssertNotNil(power.method)
    }

    func testRunningProcessWithoutEnergyCounterIsNotZeroWatts() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, cpu: 1_000_000_000)]),
            fixture(time: 3, rows: [row(time: 3, cpu: 2_000_000_000)])
        ])
        _ = try await monitor.sample()
        let second = try await monitor.sample()
        let power = try XCTUnwrap(second.processes.first?.cpuPowerWatts)
        XCTAssertEqual(power.availability, .unsupported)
        XCTAssertNil(power.numericValue)
    }

    func testWithoutAnyEnergyCounterIdleProcessesAreNotZeroWattsEither() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(pid: 42, time: 1, cpu: 1_000_000_000), row(pid: 43, time: 1)]),
            fixture(time: 3, rows: [row(pid: 42, time: 3, cpu: 2_000_000_000), row(pid: 43, time: 3)])
        ])
        _ = try await monitor.sample()
        let second = try await monitor.sample()
        XCTAssertEqual(second.processes.map(\.cpuPowerWatts.availability), [.unsupported, .unsupported],
                       "no process on this Mac has a counter, so none gets an estimate")
    }

    func testWithACounterOnThisMacAnIdleProcessDrawsZero() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(pid: 42, time: 1, cpu: 1_000_000_000, energy: 5), row(pid: 43, time: 1)]),
            fixture(time: 3, rows: [row(pid: 42, time: 3, cpu: 2_000_000_000, energy: 9), row(pid: 43, time: 3)])
        ])
        _ = try await monitor.sample()
        let idle = try await monitor.sample().processes.last?.cpuPowerWatts
        XCTAssertEqual(idle?.availability, .estimated)
        XCTAssertEqual(idle?.numericValue, 0)
    }

    func testInstructionsPerSecondUsesTheActualInterval() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, cpu: 1_000_000_000, instructions: 2_000_000_000)]),
            fixture(time: 3, rows: [row(time: 3, cpu: 2_000_000_000, instructions: 4_500_000_000)])
        ])
        let first = try await monitor.sample()
        XCTAssertEqual(first.processes.first?.instructionsPerSecond.availability, .collecting)
        let second = try await monitor.sample()
        XCTAssertEqual(second.processes.first?.instructionsPerSecond.numericValue, 1_250_000_000, "2.5 G in 2 s")
    }

    func testAMacWithoutAnInstructionCounterIsNotZeroPerSecond() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, cpu: 1_000_000_000)]),
            fixture(time: 3, rows: [row(time: 3, cpu: 2_000_000_000)])
        ])
        _ = try await monitor.sample()
        let second = try await monitor.sample()
        let instructions = try XCTUnwrap(second.processes.first?.instructionsPerSecond)
        XCTAssertEqual(instructions.availability, .unsupported)
        XCTAssertNil(instructions.numericValue)
    }

    func testWithAnInstructionCounterAnIdleProcessRetiresNone() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [
                row(pid: 42, time: 1, cpu: 1_000_000_000, instructions: 5), row(pid: 43, time: 1)
            ]),
            fixture(time: 3, rows: [
                row(pid: 42, time: 3, cpu: 2_000_000_000, instructions: 9), row(pid: 43, time: 3)
            ])
        ])
        _ = try await monitor.sample()
        let idle = try await monitor.sample().processes.last?.instructionsPerSecond
        XCTAssertEqual(idle?.availability, .measured)
        XCTAssertEqual(idle?.numericValue, 0)
    }

    func testTheQOSSplitSumsEachClassOverTheInterval() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, cpu: 1_000_000_000, qos: [.default: 1_000_000_000])]),
            fixture(time: 3, rows: [row(
                time: 3, cpu: 2_000_000_000, qos: [.default: 1_800_000_000, .utility: 200_000_000]
            )])
        ])
        let first = try await monitor.sample()
        XCTAssertEqual(first.processes.first?.qosCPUPercent?[.default]?.availability, .collecting)
        let second = try await monitor.sample()
        let split = try XCTUnwrap(second.processes.first?.qosCPUPercent)
        XCTAssertEqual(split[.default]?.numericValue, 10, "800 M ns in 2 s on 4 CPUs")
        XCTAssertEqual(split[.utility]?.numericValue, 2.5)
        XCTAssertEqual(split[.background]?.numericValue, 0, "a class without time is measured zero")
    }

    /// The split rides on the usage counters, so restricted means no split at all.
    func testAProcessWhoseUsageCannotBeReadHasNoQOSSplit() async throws {
        let monitor = try makeMonitor([fixture(time: 1, rows: [row(time: 1, failure: .restricted(code: 1))])])
        let process = try await monitor.sample().processes.first
        XCTAssertNil(process?.qosCPUPercent)
        XCTAssertEqual(process?.instructionsPerSecond.availability, .restricted)
    }

    func testGPUTimeJoinsByPIDEvenWhereUsageIsRestricted() async throws {
        let monitor = try makeMonitor(
            [
                fixture(time: 1, rows: [row(pid: 42, time: 1), row(pid: 43, time: 1), row(pid: 44, time: 1, failure: .restricted(code: 1))]),
                fixture(time: 3, rows: [row(pid: 42, time: 3), row(pid: 43, time: 3), row(pid: 44, time: 3, failure: .restricted(code: 1))])
            ],
            gpu: [
                gpuWalk(time: 1, [(7, 42, 100_000_000), (8, 44, 0)]),
                gpuWalk(time: 3, [(7, 42, 500_000_000), (8, 44, 1_000_000_000)])
            ]
        )
        let first = try await monitor.sample()
        XCTAssertEqual(first.processes.first?.gpuMillisecondsPerSecond.availability, .collecting)
        let times = Dictionary(uniqueKeysWithValues: try await monitor.sample().processes.map { ($0.id.pid, $0.gpuMillisecondsPerSecond) })
        XCTAssertEqual(times[42]?.numericValue, 200, "400 ms of GPU time in 2 s")
        XCTAssertEqual(times[43]?.availability, .measured, "no GPU client is no GPU use")
        XCTAssertEqual(times[43]?.numericValue, 0)
        XCTAssertEqual(times[44]?.numericValue, 500, "the registry is readable where rusage is not")
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

    func testOwnershipFieldsPassThroughWithoutBecomingMetrics() async throws {
        let helper = RawProcessInfo(
            pid: 43, parentPID: 1, uid: 501, startSeconds: 100, startMicroseconds: 0,
            name: "Helper", monotonicNanoseconds: 1, counters: .failure(.restricted(code: 1)),
            executablePath: "/Applications/Host.app/Contents/MacOS/Helper", responsiblePID: 42
        )
        let result = try await makeMonitor([fixture(time: 1, rows: [helper])]).sample()
        let reading = try XCTUnwrap(result.processes.first)
        XCTAssertEqual(reading.executablePath, "/Applications/Host.app/Contents/MacOS/Helper")
        XCTAssertEqual(reading.responsiblePID, 42)
        XCTAssertEqual(reading.cpuPercentOfMachine.availability, .restricted)
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

    func testKernelTaskIsAValidProcessIdentity() async throws {
        let result = try await makeMonitor([
            fixture(time: 1, rows: [row(pid: 0, time: 1)])
        ]).sample()
        XCTAssertEqual(result.processes.first?.id.pid, 0)
        XCTAssertTrue(result.issues.isEmpty)
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

    func testNativeDriverKeepsCancellationContextOnSamplingExecutor() async throws {
        let driver = ProcessStatisticsDriver()
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return await driver.read()
        }
        task.cancel()
        let raw = await task.value
        #if os(macOS)
        let enumeration = try raw.enumeration.get()
        XCTAssertTrue(enumeration.processes.isEmpty)
        XCTAssertTrue(enumeration.isTruncated)
        #else
        switch raw.enumeration {
        case .failure(.unsupportedPlatform): break
        default: XCTFail("Cancelled Linux reads must remain explicitly unsupported")
        }
        #endif
    }

    private static let clock = UUID(uuidString: "AFAE41C6-793E-4A64-A545-66CFA34571EB")!
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeMonitor(_ samples: [RawProcessSnapshot], gpu: [RawGPUClientSnapshot] = []) throws -> ProcessMonitor {
        try ProcessMonitor(driver: FixtureProcessDriver(samples), gpuClients: FixtureGPUClients(gpu))
    }

    private func gpuWalk(time: UInt64, _ clients: [(id: UInt64, pid: Int32, nanoseconds: UInt64)]) -> RawGPUClientSnapshot {
        RawGPUClientSnapshot(
            clockID: Self.clock, monotonicNanoseconds: time * 1_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(Double(time)),
            walk: .success(GPUClientWalk(
                clients: clients.map { RawGPUClient(registryEntryID: $0.id, pid: $0.pid, gpuNanoseconds: $0.nanoseconds) },
                isComplete: true
            ))
        )
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
        cpu: UInt64 = 0, read: UInt64 = 0, wakeups: UInt64 = 0, energy: UInt64 = 0, failure: ProcessDriverError? = nil,
        instructions: UInt64 = 0, qos: [ProcessQoSClass: UInt64] = [:],
        threads: Result<Int, ProcessDriverError> = .success(7),
        cpuType: Result<ProcessCPUType, ProcessDriverError> = .success(.arm64)
    ) -> RawProcessInfo {
        RawProcessInfo(
            pid: pid, parentPID: 1, uid: 501, startSeconds: start, startMicroseconds: 123,
            name: "Fixture \(pid)", monotonicNanoseconds: time * 1_000_000_000,
            counters: failure.map { .failure($0) } ?? .success(ProcessCounters(
                userNanoseconds: cpu, systemNanoseconds: 0, physicalFootprintBytes: 4096,
                diskReadBytes: read, diskWriteBytes: 0, wakeups: wakeups, energyNanojoules: energy,
                instructions: instructions, qosNanoseconds: qos
            )),
            threads: threads, cpuType: cpuType
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

/// Replays GPU walks; once they run out, reads as a Mac without the registry.
private actor FixtureGPUClients: GPUClientTimeReading {
    private var walks: [RawGPUClientSnapshot]
    init(_ walks: [RawGPUClientSnapshot]) { self.walks = walks }
    func read() async -> RawGPUClientSnapshot {
        guard !walks.isEmpty else {
            return RawGPUClientSnapshot(clockID: UUID(), monotonicNanoseconds: 0, wallTime: Date(), walk: .failure(.unsupportedPlatform))
        }
        return walks.removeFirst()
    }
}
