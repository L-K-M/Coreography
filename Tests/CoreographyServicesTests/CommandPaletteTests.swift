import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class CommandPaletteTests: XCTestCase {
    private let entries = ["Sort by Memory", "Show Processes", "Range: 1 Hour", "Hold Display", "Filter: My Processes"]
        .map { PaletteEntry(title: $0, action: .toggleHold, unavailableReason: nil) }

    func testRanksTitlePrefixThenWordPrefixThenSubstringThenSubsequence() {
        XCTAssertEqual(CommandPalette.matches("", in: entries), entries, "no query lists everything in order")
        XCTAssertEqual(CommandPalette.matches("sort mem", in: entries).map(\.title), ["Sort by Memory"])
        XCTAssertEqual(CommandPalette.matches("pro", in: entries).map(\.title), ["Show Processes", "Filter: My Processes"], "ties keep catalogue order")
        XCTAssertEqual(CommandPalette.matches("SHOW", in: entries).map(\.title), ["Show Processes"], "case is ignored")
        XCTAssertEqual(CommandPalette.matches("rng hr", in: entries).map(\.title), ["Range: 1 Hour"], "letters in order match")
        XCTAssertEqual(CommandPalette.matches("ocess", in: entries).map(\.title), ["Show Processes", "Filter: My Processes"])
        XCTAssertTrue(CommandPalette.matches("zzz", in: entries).isEmpty)
    }

    @MainActor
    func testEntriesNameTheirTargetAndRunThroughTheModel() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: Idle()), interval: .milliseconds(10),
            processMonitor: try ProcessMonitor(driver: OneProcess()), processInterval: .milliseconds(10)
        )
        let suite = "CommandPaletteTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        model.useFilterStore(defaults)
        model.start()
        defer { model.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.processSnapshot == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }

        let before = Dictionary(uniqueKeysWithValues: model.paletteEntries.map { ($0.title, $0) })
        XCTAssertEqual(model.paletteEntries.count, before.count, "titles are unique ids")
        XCTAssertEqual(before["Quit Selected Process…"]?.unavailableReason, "Select a process first")
        XCTAssertEqual(before["Clear Filter"]?.unavailableReason, "No filter is set")
        XCTAssertNotNil(before["Start Recording"])

        let process = try XCTUnwrap(model.processSnapshot?.processes.first)
        model.selectedProcessRow = ProcessGroups.rowID(process)
        let titles = Set(model.paletteEntries.filter { $0.unavailableReason == nil }.map(\.title))
        XCTAssertTrue(titles.isSuperset(of: ["Quit fixture…", "Force Quit fixture…", "Copy fixture as Text"]))

        await model.run(.filter("#listening"))
        XCTAssertEqual(model.processFilter, "#listening")
        XCTAssertNil(model.paletteEntries.first { $0.title == "Clear Filter" }?.unavailableReason)
        await model.run(.saveFilter)
        XCTAssertEqual(model.paletteEntries.first { $0.title == "Save Filter" }?.unavailableReason, "Already saved")
        XCTAssertNotNil(model.paletteEntries.first { $0.title == "Saved Filter: #listening" })
        await model.run(.clearFilter)
        XCTAssertEqual(model.processFilter, "")

        await model.run(.range(.tenMinutes))
        XCTAssertEqual(model.timeRange, .tenMinutes)
        await model.run(.sort(.memory))
        XCTAssertEqual(model.processSort, .memory)
        await model.run(.pane(.sensors))
        XCTAssertEqual(model.detailPane, .sensors)
        await model.run(.startRecording)
        XCTAssertNotNil(model.paletteEntries.first { $0.title == "Stop Recording" })

        // The app confirms these; the model must not act on them unasked.
        await model.run(.processAction(.forceQuit))
        XCTAssertNil(model.actionMessage)
    }
}

private actor OneProcess: ProcessSampleReading {
    private let clock = UUID()
    private var reads: UInt64 = 0

    func read() async -> RawProcessSnapshot {
        reads += 1
        return RawProcessSnapshot(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)), logicalCPUCount: 4, collectorPID: 42,
            enumeration: .success(ProcessEnumeration(processes: [RawProcessInfo(
                pid: 42, parentPID: 1, uid: 501, startSeconds: 100, startMicroseconds: 0, name: "fixture",
                monotonicNanoseconds: reads * 1_000_000_000,
                counters: .success(ProcessCounters(userNanoseconds: reads, systemNanoseconds: 0, physicalFootprintBytes: 1, diskReadBytes: 0, diskWriteBytes: 0))
            )]))
        )
    }
}

private actor Idle: HostSampleReading {
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
