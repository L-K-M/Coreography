import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class ProcessGPUTimeTests: XCTestCase {
    private static let clock = UUID(uuidString: "5E1B0C55-8D4B-4C55-9C2E-0E9A3C1F7A10")!
    private static let millisecond: UInt64 = 1_000_000

    func testDecoderReadsCreatorPIDAndSumsQueues() {
        XCTAssertEqual(GPUClientDecoder.pid(creator: "pid 631, WindowServer"), 631)
        XCTAssertEqual(GPUClientDecoder.pid(creator: "pid 12"), 12)
        XCTAssertNil(GPUClientDecoder.pid(creator: "631, WindowServer"))
        XCTAssertNil(GPUClientDecoder.pid(creator: "pid x, Name"))
        XCTAssertNil(GPUClientDecoder.pid(creator: "pid -1, Name"))

        let usage: [Any] = [
            ["accumulatedGPUTime": NSNumber(value: 5)], ["accumulatedGPUTime": NSNumber(value: 7)],
            ["other": NSNumber(value: 1)], "junk", ["accumulatedGPUTime": NSNumber(value: 1.5)],
            ["accumulatedGPUTime": NSNumber(value: -3)]
        ]
        XCTAssertEqual(GPUClientDecoder.gpuNanoseconds(appUsage: usage), 12, "only non-negative integers count")
        XCTAssertEqual(GPUClientDecoder.gpuNanoseconds(appUsage: nil), 0)
        XCTAssertEqual(GPUClientDecoder.gpuNanoseconds(appUsage: "AppUsage"), 0)
    }

    func testClosedClientsDropOutAndNewOnesCountInFull() {
        var ledger = GPUTimeLedger(maximumGap: .seconds(6))
        XCTAssertEqual(ledger.record(walk(at: 0, [(7, 40, 100), (8, 41, 500)])), .collecting)

        // Client 8 closed; client 9 opened since the complete first walk.
        let usage = ledger.record(walk(at: 1, [(7, 40, 160), (9, 40, 30)]))
        XCTAssertEqual(usage, .millisecondsPerSecond([40: 90]), "(160 − 100 + 30) ms in 1 s")
    }

    func testAfterAnIncompleteWalkNewClientsOnlyBaseline() {
        var ledger = GPUTimeLedger(maximumGap: .seconds(6))
        _ = ledger.record(walk(at: 0, [(7, 40, 100)], complete: false))
        let usage = ledger.record(walk(at: 1, [(7, 40, 150), (9, 41, 900)]))
        XCTAssertEqual(usage, .millisecondsPerSecond([40: 50, 41: 0]), "client 9 may predate the incomplete walk")
    }

    func testOverlappingQueuesAreNotCappedAndResetsReadAsIdle() {
        var ledger = GPUTimeLedger(maximumGap: .seconds(6))
        _ = ledger.record(walk(at: 0, [(7, 40, 0), (8, 41, 900)]))
        let usage = ledger.record(walk(at: 1, [(7, 40, 1_500), (8, 41, 100)]))
        XCTAssertEqual(usage, .millisecondsPerSecond([40: 1_500, 41: 0]), "ms/s is time, not a share")
    }

    func testClockChangesGapsAndFailuresAreNotZero() {
        var ledger = GPUTimeLedger(maximumGap: .seconds(6))
        _ = ledger.record(walk(at: 0, [(7, 40, 0)]))
        XCTAssertEqual(ledger.record(walk(at: 10, [(7, 40, 100)])), .gap("GPU clients were not read within the maximum gap"))
        XCTAssertEqual(ledger.record(walk(at: 11, [(7, 40, 200)], clock: UUID())), .collecting)
        XCTAssertEqual(ledger.record(failure(.systemCall(operation: "IOServiceGetMatchingServices", code: 5))),
                       .unavailable("IOServiceGetMatchingServices failed (5)"))
        XCTAssertEqual(ledger.record(walk(at: 12, [(7, 40, 300)])), .collecting, "a failure drops the baseline")
        XCTAssertEqual(ledger.record(failure(.unsupportedPlatform)), .unsupported("Per-process GPU time needs macOS"))
    }

    private func walk(
        at second: UInt64, _ clients: [(id: UInt64, pid: Int32, milliseconds: UInt64)],
        complete: Bool = true, clock: UUID = ProcessGPUTimeTests.clock
    ) -> RawGPUClientSnapshot {
        RawGPUClientSnapshot(
            clockID: clock, monotonicNanoseconds: second * 1_000_000_000, wallTime: Date(timeIntervalSince1970: Double(second)),
            walk: .success(GPUClientWalk(
                clients: clients.map {
                    RawGPUClient(registryEntryID: $0.id, pid: $0.pid, gpuNanoseconds: $0.milliseconds * Self.millisecond)
                },
                isComplete: complete
            ))
        )
    }

    private func failure(_ error: GPUDriverError) -> RawGPUClientSnapshot {
        RawGPUClientSnapshot(clockID: Self.clock, monotonicNanoseconds: 0, wallTime: Date(), walk: .failure(error))
    }
}
