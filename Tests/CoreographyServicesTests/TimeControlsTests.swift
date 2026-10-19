import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class TimeControlsTests: XCTestCase {
    @MainActor
    func testPausingStopsSamplingLeavesMarkersAndSurvivesStart() async throws {
        let driver = Counting()
        let model = DashboardModel(monitor: try SystemMonitor(driver: driver), interval: .milliseconds(10))
        model.start()
        defer { model.stop() }
        try await until { await driver.reads >= 2 }

        model.pauseSampling()
        XCTAssertTrue(model.samplingPaused)
        XCTAssertEqual(model.timelineMarkers.last?.label, "Recording paused")
        let paused = await driver.reads
        // Opening the window calls start(); a pause must hold.
        model.start()
        try await Task.sleep(for: .milliseconds(100))
        let afterStart = await driver.reads
        XCTAssertLessThanOrEqual(afterStart, paused + 1, "no sampling while paused")
        XCTAssertTrue(model.paletteEntries.contains { $0.title == "Resume Recording" })

        model.resumeSampling()
        XCTAssertEqual(model.timelineMarkers.last?.label, "Recording resumed")
        try await until { await driver.reads >= afterStart + 2 }
        XCTAssertFalse(model.samplingPaused)
    }

    /// Plan: the range inspector's Annotate names a range where it starts and ends.
    @MainActor
    func testAnnotatingARangeMarksItsStartAndEnd() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Counting()), interval: .milliseconds(10))
        model.annotateSelection(named: "Nothing selected")
        XCTAssertTrue(model.timelineMarkers.isEmpty, "without a range there is nothing to annotate")

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        model.selection = start...start.addingTimeInterval(30)
        model.annotateSelection(named: "  Build  ")
        XCTAssertEqual(model.timelineMarkers.map(\.label), ["Build", "End of Build"])
        XCTAssertEqual(model.timelineMarkers.map(\.time), [start, start.addingTimeInterval(30)])
        XCTAssertTrue(model.timelineMarkers.allSatisfy { $0.kind == .note })

        model.selection = start...start
        model.annotateSelection(named: "Instant")
        XCTAssertEqual(model.timelineMarkers.filter { $0.label.contains("Instant") }.count, 1, "an instant is one marker")

        model.selection = start...start.addingTimeInterval(5)
        model.annotateSelection(named: String(repeating: "x", count: 200))
        XCTAssertTrue(model.timelineMarkers.allSatisfy { $0.label.count <= DashboardModel.maximumMarkerLength }, "the end's label keeps the limit too")
    }

    /// One core = 100 % needs the core count; until a sample names it, labels must not claim it.
    @MainActor
    func testTheOneCoreScaleWaitsForTheCoreCount() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Counting()), interval: .milliseconds(10))
        let saved = model.processCPUScale
        defer { model.processCPUScale = saved }
        model.processCPUScale = .oneCore
        XCTAssertEqual(model.processCPUScaleInEffect, .machine)
        XCTAssertEqual(model.processCPUFactor, 1)

        model.start()
        defer { model.stop() }
        try await until { await MainActor.run { model.latest != nil } }
        XCTAssertEqual(model.processCPUScaleInEffect, .oneCore)
        XCTAssertEqual(model.processCPUFactor, 4)
    }

    @MainActor
    func testClearingTheSelectionFromThePaletteDropsTheComparison() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Counting()), interval: .milliseconds(10))
        model.selection = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 10)
        model.comparison = Date(timeIntervalSince1970: 20)...Date(timeIntervalSince1970: 30)
        await model.run(.clearSelection)
        XCTAssertNil(model.selection)
        XCTAssertNil(model.comparison, "a later selection must not revive it")
    }

    @MainActor
    func testReturnToNowLeavesHoldAndCursorAndMarkersAreNamed() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Counting()), interval: .milliseconds(10))
        model.toggleDisplayHold()
        model.cursorTime = Date(timeIntervalSince1970: 1_700_000_000)
        model.selection = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 10)
        model.returnToNow()
        XCTAssertEqual(model.displayMode, .live)
        XCTAssertNil(model.cursorTime)
        XCTAssertNotNil(model.selection, "the selection stays")

        let time = Date(timeIntervalSince1970: 1_700_000_000)
        model.addMarker(named: "  Build started  ", at: time)
        XCTAssertEqual(model.timelineMarkers.last?.label, "Build started")
        XCTAssertTrue(model.timelineMarkers.last.map { if case .note = $0.kind { true } else { false } } ?? false)
        model.addMarker(named: "", at: time)
        XCTAssertTrue(model.timelineMarkers.last?.label.hasPrefix("Marker ") ?? false)
        model.addMarker(named: String(repeating: "x", count: 500), at: time)
        XCTAssertEqual(model.timelineMarkers.last?.label.count, DashboardModel.maximumMarkerLength)
    }

    @MainActor
    private func until(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let met = await condition()
        XCTAssertTrue(met)
    }
}

private actor Counting: HostSampleReading {
    private let clock = UUID()
    private(set) var reads: UInt64 = 0

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

@MainActor
final class PanZoomTests: XCTestCase {
    /// Plan: scroll pans and pinch zooms through the ranges, as far as history goes.
    func testPanningDetachesFromLiveStaysInsideHistoryAndReturnsToNow() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Steps(), historyCapacity: 600), interval: .milliseconds(5))
        model.start()
        defer { model.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.frames.count < 120, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try XCTSkipIf(model.frames.count < 120, "sampling stalled; the pan needs two minutes of history")
        XCTAssertEqual(model.displayMode, .live)
        let end = try XCTUnwrap(model.displayedEndTime)
        let first = try XCTUnwrap(model.frames.first?.stamp.wallTime)
        XCTAssertEqual(model.visibleWindow?.upperBound, end, "live shows the newest data")

        model.pan(bySeconds: 30)
        XCTAssertEqual(model.displayMode, .held, "panning back detaches from live")
        XCTAssertEqual(model.visibleWindow?.upperBound, end.addingTimeInterval(-30))
        XCTAssertEqual(model.visibleWindow?.lowerBound, end.addingTimeInterval(-30 - TimeRange.minute.seconds))

        model.pan(bySeconds: 10_000)
        XCTAssertEqual(model.visibleWindow?.lowerBound, first, "it stops where history starts")
        model.pan(bySeconds: -10_000)
        XCTAssertEqual(model.visibleWindow?.upperBound, end, "and forward at the newest data")

        model.pan(bySeconds: 30)
        model.returnToNow()
        XCTAssertEqual(model.displayMode, .live)
        XCTAssertEqual(model.visibleWindow?.upperBound, model.displayedEndTime)
    }

    func testZoomStepsThroughTheRangesAndStopsAtTheEnds() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: Steps()), interval: .milliseconds(5))
        model.timeRange = .tenMinutes
        model.zoom(.wider)
        XCTAssertEqual(model.timeRange, .hour)
        model.zoom(.closer)
        model.zoom(.closer)
        XCTAssertEqual(model.timeRange, .minute)
        model.zoom(.closer)
        XCTAssertEqual(model.timeRange, .minute, "there is nothing closer than a minute")
        model.timeRange = .month
        model.zoom(.wider)
        XCTAssertEqual(model.timeRange, .month)
    }
}

/// One second per read on both clocks.
private actor Steps: HostSampleReading {
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
