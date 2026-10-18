import Foundation
import CoreographyDrivers
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class HistoryRecorderTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testBatchesWritesEveryThirtySeconds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-recorder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let recorder = HistoryRecorder(store: store)

        for second in 0..<30 {
            await recorder.record([sample(second)], at: epoch.addingTimeInterval(TimeInterval(second)))
        }
        let beforeFlush = try await store.sampleCount()
        XCTAssertEqual(beforeFlush, 0, "nothing is written until the batch interval passes")

        await recorder.record([sample(30)], at: epoch.addingTimeInterval(30))
        let afterFlush = try await store.sampleCount()
        XCTAssertEqual(afterFlush, 31, "one transaction holds the whole batch")
        let error = await recorder.lastError
        XCTAssertNil(error)

        try await recorder.deleteAll()
        let deleted = try await store.sampleCount()
        XCTAssertEqual(deleted, 0)
    }

    func testLatestReadingsKeepUnavailableStatesAndSkipAmbiguousDisks() async throws {
        let monitor = try SystemMonitor(driver: HostOnce(epoch: epoch))
        let host = try await monitor.sample()
        let samples = HistorySamples.latest(host: host, network: nil, disks: nil, gpu: nil, power: nil, sensors: nil)
        XCTAssertEqual(Set(samples.map(\.metric)), [
            .cpu, .memoryUsed, .memoryApp, .memoryWired, .memoryCompressed, .memoryCached,
            .memoryPressure, .swapUsed, .thermalPressure
        ])
        let cpu = try XCTUnwrap(samples.first { $0.metric == .cpu })
        XCTAssertNil(cpu.value, "the first CPU sample is still collecting")
        XCTAssertEqual(cpu.availability, .collecting)
        XCTAssertEqual(samples.first { $0.metric == .thermalPressure }?.availability, .unavailable)
    }

    func testLedgerIntervalsReachTheStoreAndRebuildTheSameTotals() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-ledger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let recorder = HistoryRecorder(store: store)

        var ledger = AppLedger(capacity: 10)
        XCTAssertNil(ledger.record(try processes(at: 0, cpu: 50), logicalCPUCount: 2), "the first sample opens no interval")
        let interval = try XCTUnwrap(ledger.record(try processes(at: 2, cpu: 50), logicalCPUCount: 2))
        XCTAssertEqual(interval.entries.map(\.app), ["Worker"])
        XCTAssertEqual(interval.entries.first?.cpuSeconds ?? 0, 2, accuracy: 1e-9, "half of two cores for two seconds")

        await recorder.recordLedger(interval)
        await recorder.flush(now: epoch.addingTimeInterval(2))
        let stored = try await store.ledger(from: epoch, to: epoch.addingTimeInterval(2))
        XCTAssertEqual(stored, [interval])

        let range = epoch...epoch.addingTimeInterval(2)
        let rebuilt = AppLedger(stored: stored).totals(in: range)
        let live = ledger.totals(in: range)
        XCTAssertEqual(rebuilt.apps.map(\.cpuSeconds), live.apps.map(\.cpuSeconds))
        XCTAssertEqual(rebuilt.covered, live.covered)
    }

    private func processes(at second: TimeInterval, cpu: Double) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: UInt64(second * 1e9), wallTime: epoch.addingTimeInterval(second))
        let row = ProcessReading(
            id: try ProcessIdentity(pid: 42, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501,
            name: "Worker", stamp: stamp, cpuPercentOfMachine: try .measured(cpu), memoryFootprintBytes: try .measured(1),
            diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
            executablePath: nil, responsiblePID: nil
        )
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(1), enumerationTruncated: false,
            processes: [row], issues: [], continuity: .continuous
        )
    }

    private func sample(_ second: Int) -> HistorySample {
        HistorySample(metric: .cpu, time: epoch.addingTimeInterval(TimeInterval(second)), value: Double(second), availability: .measured)
    }
}

private actor HostOnce: HostSampleReading {
    let epoch: Date
    init(epoch: Date) { self.epoch = epoch }

    func read() async -> RawHostSnapshot {
        RawHostSnapshot(
            clockID: UUID(), monotonicNanoseconds: 1, wallTime: epoch,
            inventory: HostInventory(operatingSystem: "Fixture", architecture: "fixture", logicalCPUCount: 1, physicalMemoryBytes: 1 << 20),
            cpu: .success(ProcessorTicks(user: 1, system: 0, idle: 1, nice: 0)),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0, wired: 1, compressed: 0, compressorContents: 0,
                purgeable: 0, fileBacked: 0, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 0, usedBytes: 0)), memoryPressure: .success(.normal),
            thermalPressure: .failure(.systemCall(operation: "notify", code: 5))
        )
    }
}
