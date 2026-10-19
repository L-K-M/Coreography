import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class RecordingTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testARecordingRoundTripsAndRedactsAppsConsistently() throws {
        var ledger = AppLedger(capacity: 10)
        ledger.record(try processes(at: 0, [("Secret Project", 50), ("Mail", 10)]), logicalCPUCount: 4)
        ledger.record(try processes(at: 2, [("Secret Project", 50), ("Mail", 10)]), logicalCPUCount: 4)
        ledger.record(try processes(at: 4, [("Secret Project", 50), ("Mail", 10)]), logicalCPUCount: 4)
        let range = epoch...epoch.addingTimeInterval(10)
        let frames = DashboardFrames(host: [], network: [], disks: [], gpu: [], power: [], sensors: [])
        let markers = [
            TimelineMarker(time: epoch.addingTimeInterval(3), label: "Launched the build", kind: .note),
            TimelineMarker(time: epoch.addingTimeInterval(3), label: "Sleep", kind: .system)
        ]

        let redacted = Recording.make(name: "Build", range: range, frames: frames, ledger: ledger, markers: markers, naming: .redacted)
        let data = try Recording.encode(redacted)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Secret"), "no app name leaves a redacted recording")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Mail"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Launched the build"), "nor the person's marker names")
        let read = try Recording.decode(data)
        XCTAssertEqual(read.ledger.count, 2)
        XCTAssertEqual(Set(read.ledger.flatMap(\.entries).map(\.app)), ["App 1", "App 2"])
        XCTAssertTrue(read.ledger.allSatisfy { interval in interval.entries.first { $0.app == "App 1" }?.cpuSeconds == 4 },
                      "the same app keeps one placeholder, ranked by CPU")
        XCTAssertTrue(read.ledger.allSatisfy { interval in interval.entries.first { $0.app == "App 2" }?.cpuSeconds == 0.8 })
        XCTAssertEqual(read.markers.map(\.label), ["Marker", "Sleep"])
        XCTAssertEqual(read.markers.map(\.kind), [.note, .system], "a marker keeps its kind")

        let named = Recording.make(name: "Build", range: range, frames: frames, ledger: ledger, markers: markers, naming: .named)
        XCTAssertTrue(named.ledger.flatMap(\.entries).contains { $0.app == "Secret Project" })
    }

    func testUnreadableNewerAndInvalidFilesAreRefusedWithAReason() throws {
        XCTAssertThrowsError(try Recording.decode(Data("nope".utf8))) {
            XCTAssertEqual($0 as? Recording.Failure, .unreadable("not a Coreography recording"))
        }
        XCTAssertThrowsError(try Recording.decode(Data(#"{"schemaVersion":99}"#.utf8))) {
            XCTAssertEqual($0 as? Recording.Failure, .newerSchema(99))
        }
        let backwards = Recording.make(
            name: "x", range: epoch...epoch, frames: DashboardFrames(host: [], network: [], disks: [], gpu: [], power: [], sensors: []),
            ledger: AppLedger(capacity: 1), markers: [], naming: .named
        )
        let encoded = try XCTUnwrap(String(data: try Recording.encode(backwards), encoding: .utf8))
        let json = encoded.replacingOccurrences(of: "\"start\":\"2023-11-14T22:13:20Z\"", with: "\"start\":\"2024-11-14T22:13:20Z\"")
        XCTAssertNotEqual(json, encoded, "the fixture moved the start past the end")
        XCTAssertThrowsError(try Recording.decode(Data(json.utf8))) { XCTAssertEqual($0 as? Recording.Failure, .invalidRange) }
    }

    @MainActor
    func testOpeningARecordingHoldsTheWindowOnItUntilReturningToLive() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Host()), interval: .milliseconds(10))
        model.start()
        defer { model.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.frames.count < 5, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let start = try XCTUnwrap(model.frames.first?.stamp.wallTime)
        let end = try XCTUnwrap(model.frames.last?.stamp.wallTime)
        model.selection = start...end
        model.addMarker(named: "Here", at: start.addingTimeInterval(1))
        model.exportNaming = .named
        let data = try XCTUnwrap(model.recordingData(name: "Saved"))
        model.returnToNow()

        let opened = await model.openRecording(data, fileName: "Build log")
        XCTAssertNil(opened)
        XCTAssertEqual(model.openRecording?.name, "Build log", "the file's name, which the person chose, names it")
        XCTAssertEqual(model.displayMode, .held)
        XCTAssertEqual(model.frames.first?.stamp.wallTime, start)
        XCTAssertNil(model.selection, "a recording opens without a selection")
        XCTAssertTrue(model.timelineMarkers.contains { $0.label == "Here" })
        XCTAssertEqual(model.timelineMarkers.filter { $0.label == "Memory pressure warning" }.count, 1,
                       "system markers come again from the frames, not twice")
        XCTAssertNil(model.processSnapshot, "no live process detail mixed into a replay")

        model.toggleDisplayHold()
        XCTAssertNil(model.openRecording)
        XCTAssertEqual(model.displayMode, .live)
        let refused = await model.openRecording(Data("x".utf8))
        XCTAssertEqual(refused, "The recording could not be read: not a Coreography recording")
        XCTAssertEqual(model.actionMessage, "The recording could not be read: not a Coreography recording")
    }

    // MARK: Fixtures

    private func processes(at second: TimeInterval, _ rows: [(String, Double)]) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: UInt64(1 + second * 1e9), wallTime: epoch.addingTimeInterval(second))
        let readings = try rows.enumerated().map { offset, row in
            ProcessReading(
                id: try ProcessIdentity(pid: Int32(100 + offset), startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501,
                name: row.0, stamp: stamp, cpuPercentOfMachine: try .measured(row.1), memoryFootprintBytes: try .measured(1),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(readings.count)), enumerationTruncated: false,
            processes: readings, issues: [], continuity: .continuous
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
            // Pressure rises once, so the recording holds one system marker.
            memoryPressure: .success(reads >= 3 ? .warning : .normal), thermalPressure: .success(.nominal)
        )
    }
}
