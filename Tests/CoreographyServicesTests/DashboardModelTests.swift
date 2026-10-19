import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

@MainActor
final class DashboardModelTests: XCTestCase {
    func testHoldingDisplayDoesNotPauseCollection() async throws {
        let driver = IncreasingHostDriver()
        let monitor = try SystemMonitor(driver: driver)
        let model = DashboardModel(monitor: monitor, interval: .milliseconds(10))
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 2 }

        model.toggleDisplayHold()
        let held = model.frames.last?.id
        let heldTime = model.latest?.stamp.wallTime
        let heldPoints = model.points(for: .memory).map(\.time)
        let before = await driver.readCount
        try await eventually { await driver.readCount >= before + 65 }
        XCTAssertEqual(model.frames.last?.id, held)
        XCTAssertEqual(model.latest?.stamp.wallTime, heldTime)
        XCTAssertEqual(model.points(for: .memory).map(\.time), heldPoints)

        model.toggleDisplayHold()
        XCTAssertNotEqual(model.frames.last?.id, held)
        XCTAssertEqual(model.displayMode, .live)
    }

    func testMemoryStackSumsLayersAndPressureSpansFollowSamples() async throws {
        let driver = IncreasingHostDriver()
        let monitor = try SystemMonitor(driver: driver)
        let model = DashboardModel(monitor: monitor, interval: .milliseconds(10))
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 3 }
        model.toggleDisplayHold()

        // 15 resident pages - 1 file-backed = 14 used: 9 app, 2 wired, 3 compressed.
        let page = 4096.0
        let first = model.frames[0]
        let layers = model.memoryStack().filter { $0.time == first.stamp.wallTime }
        XCTAssertEqual(layers.map(\.category), [.app, .wired, .compressed, .cached])
        XCTAssertEqual(layers.map(\.lower), [0, 9 * page, 11 * page, 14 * page])
        XCTAssertEqual(layers.map(\.upper), [9 * page, 11 * page, 14 * page, 15 * page])
        XCTAssertEqual(first.memoryUsedBytes.numericValue, 14 * page)

        let spans = model.memoryPressureSpans()
        XCTAssertEqual(spans.count, model.frames.count - 1)
        for (span, pair) in zip(spans, zip(model.frames, model.frames.dropFirst())) {
            XCTAssertEqual(span.start, pair.0.stamp.wallTime)
            XCTAssertEqual(span.end, pair.1.stamp.wallTime)
            XCTAssertEqual(span.level, pair.1.memory.pressureLevel)
        }
        XCTAssertTrue(spans.contains { $0.level == .warning })
    }

    /// The busiest GPU names the value, so its graph must be that GPU's too.
    func testTheMenuBarGPUValueAndGraphDescribeOneDevice() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10),
            gpuMonitor: try GPUMonitor(driver: CyclingGPUDriver())
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.gpuFrames.count >= 4 && model.displayedGPUFrame?.devices.count == 2 }
        model.toggleDisplayHold()

        let value = try XCTUnwrap(model.menuBarValue(.gpu)?.numericValue)
        let graphed = Set(model.menuBarPoints(.gpu).map(\.value))
        XCTAssertEqual(graphed, [value], "each fixture GPU holds one utilization")
    }

    func testGPUSeriesSplitWhereADeviceIsMissingAndThermalSpansFollowSamples() async throws {
        let gpu = try GPUMonitor(driver: CyclingGPUDriver())
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10),
            gpuMonitor: gpu
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.gpuFrames.count >= 4 && model.frames.count >= 7 }
        model.toggleDisplayHold()

        let series = model.gpuSeries()
        XCTAssertEqual(series.map(\.name), ["Integrated", "Discrete"])
        let integrated = try XCTUnwrap(series.first)
        XCTAssertEqual(Set(integrated.points.map(\.segment)).count, 1)
        // The discrete GPU disappears every other read; its line must not bridge that.
        let discrete = try XCTUnwrap(series.last)
        XCTAssertEqual(Set(discrete.points.map(\.segment)).count, discrete.points.count)

        // Contiguous spans at one level merge; each span covers only frames at its level.
        let spans = model.thermalPressureSpans()
        XCTAssertLessThan(spans.count, model.frames.count - 1)
        XCTAssertEqual(spans.first?.start, model.frames.first?.stamp.wallTime)
        XCTAssertEqual(spans.last?.end, model.frames.last?.stamp.wallTime)
        for (current, next) in zip(spans, spans.dropFirst()) {
            XCTAssertFalse(current.end == next.start && current.level == next.level)
        }
        for span in spans {
            let covered = model.frames.filter { $0.stamp.wallTime > span.start && $0.stamp.wallTime <= span.end }
            XCTAssertFalse(covered.isEmpty)
            XCTAssertTrue(covered.allSatisfy { ThermalPressureLevel(reading: $0.thermalPressure) == span.level })
        }
    }

    func testBatteryHistoryAndExternalPowerBandsFollowThePowerSource() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10),
            powerMonitor: try PowerMonitor(driver: AlternatingPowerDriver())
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.powerFrames.count >= 5 }
        model.toggleDisplayHold()

        let frames = model.powerFrames
        XCTAssertEqual(model.batteryChargePoints().map(\.value), frames.map { $0.batteryChargePercent.numericValue! })
        let pluggedEnds = Set(frames.dropFirst().filter { $0.powerSource == .externalPower }.map(\.stamp.wallTime))
        XCTAssertEqual(Set(model.externalPowerSpans().map(\.end)), pluggedEnds)
        XCTAssertFalse(pluggedEnds.isEmpty)
    }

    func testSixHourRangePutsStoredHistoryBehindLiveWithoutBridgingTheSeam() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-replay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let now = Date()
        let threeHoursAgo = now.addingTimeInterval(-3 * 3600)
        let stored = (0..<600).map {
            HistorySample(metric: .cpu, time: threeHoursAgo.addingTimeInterval(Double($0)), value: 50, availability: .measured)
        }
        try await store.append(stored, now: now)

        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver(origin: now)), interval: .milliseconds(10),
            historyRecorder: HistoryRecorder(store: store)
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 2 }
        XCTAssertTrue(model.points(for: .cpu).allSatisfy { $0.time >= now }, "short ranges stay live")

        model.timeRange = .sixHours
        try await eventually { model.points(for: .cpu).contains { $0.time < now } }
        let points = model.points(for: .cpu)
        let older = points.filter { $0.time < now }
        let live = points.filter { $0.time >= now }
        XCTAssertEqual(older.first?.time.timeIntervalSince(threeHoursAgo) ?? .infinity, 0, accuracy: 1e-3)
        XCTAssertTrue(older.allSatisfy { $0.value == 50 })
        XCTAssertFalse(live.isEmpty)
        XCTAssertTrue(Set(older.map(\.segment)).isDisjoint(with: live.map(\.segment)), "no line joins stored and live")
        XCTAssertNil(model.storedHistoryProblem)

        model.timeRange = .hour
        XCTAssertTrue(model.points(for: .cpu).allSatisfy { $0.time >= now }, "leaving the range drops the stored part")
    }

    /// A longer range reads further back at once, not after the last range's reload interval.
    func testSwitchingToALongerRangeLoadsItsHistoryAtOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-ranges-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let now = Date()
        let threeDaysAgo = now.addingTimeInterval(-3 * 86_400)
        try await store.append((0..<120).map {
            HistorySample(metric: .cpu, time: threeDaysAgo.addingTimeInterval(Double($0)), value: 40, availability: .measured)
        }, now: threeDaysAgo.addingTimeInterval(120))
        let threeHoursAgo = now.addingTimeInterval(-3 * 3600)
        try await store.append((0..<120).map {
            HistorySample(metric: .cpu, time: threeHoursAgo.addingTimeInterval(Double($0)), value: 40, availability: .measured)
        }, now: now)
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver(origin: now)), interval: .milliseconds(10),
            historyRecorder: HistoryRecorder(store: store)
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 2 }
        model.timeRange = .sixHours
        try await eventually { model.points(for: .cpu).contains { $0.time < now.addingTimeInterval(-3600) } }
        model.timeRange = .week
        try await eventually { model.points(for: .cpu).contains { $0.time < now.addingTimeInterval(-86_400) } }
    }

    func testQuittingWritesTheBufferedHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-quit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver(origin: Date())), interval: .milliseconds(10),
            historyRecorder: HistoryRecorder(store: store)
        )
        model.start()
        try await eventually { model.frames.count >= 3 }
        let buffered = try await store.sampleCount()
        XCTAssertEqual(buffered, 0, "samples wait in the buffer between writes")

        await model.stopForQuit()
        let written = try await store.sampleCount()
        XCTAssertGreaterThan(written, 0, "quitting writes them before it returns")
    }

    func testDeletingHistoryDropsTheStoredPartAtOnceEvenWhileHeld() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-replay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let now = Date()
        try await store.append(
            [HistorySample(metric: .cpu, time: now.addingTimeInterval(-7200), value: 50, availability: .measured)], now: now
        )
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver(origin: now)), interval: .milliseconds(10),
            historyRecorder: HistoryRecorder(store: store)
        )
        model.start()
        defer { model.stop() }
        model.timeRange = .sixHours
        try await eventually { model.points(for: .cpu).contains { $0.time < now } }

        model.toggleDisplayHold()
        let problem = await model.deleteHistory()
        XCTAssertNil(problem)
        XCTAssertFalse(model.points(for: .cpu).contains { $0.time < now }, "deleted history leaves the screen")
    }

    func testStoredLedgerReachesReportsAndScopeWhileExportStaysLive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreo-ranges-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let now = Date()
        let threeHoursAgo = now.addingTimeInterval(-3 * 3600)
        let intervals = (0..<10).map { index in
            LedgerInterval(
                start: threeHoursAgo.addingTimeInterval(Double(index * 2)), end: threeHoursAgo.addingTimeInterval(Double(index * 2 + 2)),
                cores: 4, entries: [LedgerEntry(app: "Worker", cpuSeconds: 2, diskBytes: 100, isLowerBound: false)]
            )
        }
        try await store.append([], ledger: intervals, now: now)

        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver(origin: now)), interval: .milliseconds(10),
            historyRecorder: HistoryRecorder(store: store)
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 2 }
        model.scopedApp = "Worker"
        model.timeRange = .sixHours
        try await eventually { model.scopedSeries()?.cpu.contains { $0.time < now } ?? false }
        XCTAssertEqual(model.scopedSeries()?.cpu.first?.value ?? 0, 25, accuracy: 1e-9, "2 CPU-seconds over 2 s of 4 cores")

        model.selection = threeHoursAgo.addingTimeInterval(-60)...now.addingTimeInterval(60)
        XCTAssertEqual(model.rangeReport?.topCPUApps.first?.cpuSeconds ?? 0, 20, accuracy: 1e-9)
        let export = try XCTUnwrap(model.rangeExport)
        XCTAssertGreaterThanOrEqual(export.start, now, "exports start where live data does")

        model.selection = threeHoursAgo...threeHoursAgo.addingTimeInterval(20)
        XCTAssertNil(model.rangeExport, "a selection entirely in stored history has no live data to export")
    }

    func testConnectionsAreReadOnlyWhenShownOrFilteredOn() async throws {
        let sockets = ScriptedSockets()
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10),
            processMonitor: try ProcessMonitor(driver: IncreasingProcessDriver()), processInterval: .milliseconds(10),
            connectionMonitor: ConnectionMonitor(driver: sockets)
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.processSnapshot != nil }
        let idle = await sockets.reads
        XCTAssertEqual(idle, 0, "no socket reads while connections are neither shown nor filtered on")
        XCTAssertEqual(model.processFilterIssues, [])

        model.processFilter = "#listening"
        try await eventually { model.connectionSnapshot != nil }
        XCTAssertEqual(model.visibleProcessRows.map(\.name), ["Fixture"])
        XCTAssertEqual(model.processFilterIssues, [])

        model.processFilter = ""
        model.detailPane = .connections
        let apps = model.appConnections
        XCTAssertEqual(apps.map(\.app), ["Fixture"])
        XCTAssertEqual(apps.first?.listening.first?.local, ConnectionEndpoint(address: "127.0.0.1", port: 8080))
        XCTAssertEqual(apps.first?.connected.first?.remote?.port, 443)
        model.connectionFilter = "443"
        XCTAssertEqual(model.appConnections.first?.listening.count, 0)
        XCTAssertEqual(model.appConnections.first?.connected.count, 1)
    }

    func testNothingExportsBeforeTheFirstLiveSample() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10))
        model.selection = Date().addingTimeInterval(-60)...Date()
        XCTAssertNil(model.rangeExport, "no live data, nothing to export")
    }

    func testSixHourRangeWithoutRecordingNamesTheMissingHistory() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10))
        model.timeRange = .sixHours
        XCTAssertEqual(model.storedHistoryProblem, "History is not being recorded.")
        model.timeRange = .minute
        XCTAssertNil(model.storedHistoryProblem)
    }

    func testCursorReadsTheNearestSampleOrNothingAndNilFollowsLive() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10))
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 4 }
        model.toggleDisplayHold()

        let target = model.frames[2]
        model.cursorTime = target.stamp.wallTime.addingTimeInterval(0.4)
        XCTAssertEqual(model.displayedFrame?.id, target.id)
        XCTAssertEqual(model.reading(for: .cpu), target.cpuPercentOfMachine)

        // Beyond the tolerance there is no sample; never the nearest far one.
        model.cursorTime = model.frames.last!.stamp.wallTime.addingTimeInterval(30)
        XCTAssertNil(model.displayedFrame)
        XCTAssertNil(model.reading(for: .memory))

        model.cursorTime = nil
        XCTAssertEqual(model.displayedFrame?.id, model.frames.last?.id)
    }

    func testHottestSensorChangeSplitsTheLineAndSMCPowerIsPreferred() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10),
            powerMonitor: try PowerMonitor(driver: AlternatingPowerDriver()),
            sensorMonitor: try SensorMonitor(driver: SwitchingSensorDriver())
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.sensorFrames.count >= 6 && model.powerFrames.count >= 1 }
        model.toggleDisplayHold()

        let points = model.hottestTemperaturePoints()
        XCTAssertEqual(points.count, model.sensorFrames.count)
        // Keys switch every third read; each run of one key is its own segment.
        for (point, frame) in zip(points, model.sensorFrames) {
            let sameKey = points.filter { $0.segment == point.segment }
            XCTAssertTrue(sameKey.allSatisfy { candidate in
                model.sensorFrames.first { $0.id == candidate.id }?.hottest?.key == frame.hottest?.key
            })
        }
        XCTAssertGreaterThan(Set(points.map(\.segment)).count, 1)
        XCTAssertEqual(model.displayedSystemPower?.source?.channel, "PSTR")
    }

    func testSelfCostUsesTheCollectorRowOnTheOneCoreScale() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10),
            processMonitor: try ProcessMonitor(driver: IncreasingProcessDriver()), processInterval: .milliseconds(10)
        )
        model.start()
        defer { model.stop() }
        try await eventually { model.selfCost?.cpuPercentOfOneCore.numericValue != nil }
        model.toggleDisplayHold()

        let own = try XCTUnwrap(model.processSnapshot?.processes.first { $0.id.pid == 42 })
        let cost = try XCTUnwrap(model.selfCost)
        let share = try XCTUnwrap(own.cpuPercentOfMachine.numericValue)
        XCTAssertEqual(cost.cpuPercentOfOneCore.numericValue ?? -1, share * 4, accuracy: 1e-9)
        XCTAssertEqual(cost.footprintBytes.numericValue, own.memoryFootprintBytes.numericValue)
        XCTAssertFalse(cost.footprintOverBudget)

        XCTAssertNil(SelfCost.measure(in: nil, logicalCPUCount: 4))

        // One wakeup a second is the sampling; the budget counts the rest.
        let within = SelfCost(cpuPercentOfOneCore: try .measured(0.5), footprintBytes: try .measured(1), wakeupsPerSecond: try .measured(6))
        let over = SelfCost(cpuPercentOfOneCore: try .measured(0.5), footprintBytes: try .measured(1), wakeupsPerSecond: try .measured(6.5))
        XCTAssertFalse(within.wakeupsOverBudget)
        XCTAssertTrue(over.wakeupsOverBudget)

        // In Low Power Mode the window samples every 2 s, so only half a wakeup is the sampling.
        let slow = SelfCost(
            cpuPercentOfOneCore: try .measured(0.5), footprintBytes: try .measured(1), wakeupsPerSecond: try .measured(5.8),
            samplingSeconds: 2
        )
        XCTAssertTrue(slow.wakeupsOverBudget)
        XCTAssertFalse(SelfCost(
            cpuPercentOfOneCore: try .measured(0.5), footprintBytes: try .measured(1), wakeupsPerSecond: try .measured(5.8)
        ).wakeupsOverBudget)
    }

    func testClearingASelectionAlsoClearsAnUnfinishedDrag() async throws {
        let model = DashboardModel(monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10))
        let range = Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 10)
        model.selection = range
        // A drag the system cancelled never reaches onEnded, so its draft would linger.
        model.draftSelection = range
        model.clearSelection()
        XCTAssertNil(model.selection)
        XCTAssertNil(model.draftSelection, "a lingering draft keeps shading every lane with no panel to clear it")
    }

    func testRangeReportIsBuiltOnlyWhenItsInputsChange() async throws {
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10),
            processMonitor: try ProcessMonitor(driver: IncreasingProcessDriver()), processInterval: .milliseconds(10)
        )
        model.start()
        try await eventually { model.frames.count >= 3 }
        model.toggleDisplayHold()
        defer { model.stop() }
        let start = try XCTUnwrap(model.frames.first?.stamp.wallTime)
        model.selection = start...start.addingTimeInterval(60)

        // Hovering re-renders the window; each render reads the report again.
        let first = try XCTUnwrap(model.rangeReport)
        for _ in 0..<5 { _ = model.rangeReport }
        XCTAssertEqual(model.rangeReportBuilds, 1, "an unchanged selection and data reuse the report")

        model.selection = start...start.addingTimeInterval(1)
        let narrowed = try XCTUnwrap(model.rangeReport)
        XCTAssertEqual(model.rangeReportBuilds, 2, "a new selection rebuilds it")
        XCTAssertNotEqual(first.requested, narrowed.requested)

        model.toggleDisplayHold()
        try await eventually { model.frames.last?.id != nil && model.rangeReportBuilds >= 2 }
        let live = model.frames.last?.id
        try await eventually { model.frames.last?.id != live }
        _ = model.rangeReport
        XCTAssertEqual(model.rangeReportBuilds, 3, "new samples rebuild it")
    }

    func testMemorySeriesDoesNotBridgeSamplingGaps() async throws {
        let driver = IncreasingHostDriver()
        let monitor = try SystemMonitor(driver: driver)
        let model = DashboardModel(monitor: monitor, interval: .milliseconds(10))
        model.start()
        defer { model.stop() }
        try await eventually { model.frames.count >= 2 }
        await driver.skipWallTime()
        try await eventually { model.frames.contains { $0.continuity == .interrupted } }

        let points = model.points(for: .memory)
        XCTAssertGreaterThan(Set(points.map(\.segment)).count, 1)
        XCTAssertEqual(points.count, model.frames.count)
    }

    func testDisplayHoldAlsoHoldsProcessRowsWhileTheirCollectionContinues() async throws {
        let driver = IncreasingProcessDriver()
        let model = DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()),
            interval: .milliseconds(10), processMonitor: try ProcessMonitor(driver: driver),
            processInterval: .milliseconds(10)
        )
        model.start()
        defer { model.stop() }
        try await eventually { await driver.readCount >= 2 && model.processSnapshot != nil }
        model.toggleDisplayHold()
        let held = model.processSnapshot?.stamp.monotonicNanoseconds
        let before = await driver.readCount
        try await eventually { await driver.readCount >= before + 3 }
        XCTAssertEqual(model.processSnapshot?.stamp.monotonicNanoseconds, held)
        model.toggleDisplayHold()
        XCTAssertNotEqual(model.processSnapshot?.stamp.monotonicNanoseconds, held)
    }

    func testProcessListFiltersAndOrdersMeasuredRowsBeforeMissingData() throws {
        let snapshot = ProcessSnapshot(
            stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date()),
            collectorPID: 42, enumeration: try .measured(3), enumerationTruncated: false,
            processes: [
                try process(pid: 42, name: "Browser", uid: 501, cpu: .measured(25), memory: 500),
                try process(pid: 50, name: "Editor", uid: 501, cpu: .measured(10), memory: 1000),
                try process(pid: 1, name: "System", uid: 0, cpu: .restricted(reason: "Fixture"), memory: 50)
            ], issues: [], continuity: .continuous
        )
        XCTAssertEqual(ProcessList.rows(in: snapshot, matching: "", sortedBy: .cpu).map(\.id.pid), [42, 50, 1])
        XCTAssertEqual(ProcessList.rows(in: snapshot, matching: "", sortedBy: .memory).map(\.id.pid), [50, 42, 1])
        XCTAssertEqual(ProcessList.rows(in: snapshot, matching: "broW", sortedBy: .name).map(\.id.pid), [42])
        XCTAssertEqual(ProcessList.rows(in: snapshot, matching: "42", sortedBy: .cpu).map(\.id.pid), [42])
        XCTAssertEqual(ProcessList.rows(in: snapshot, matching: " 501 ", sortedBy: .cpu).count, 2)
    }

    func testNetworkDisplayHoldFreezesRowsAndSharedTimeWhileSamplingContinues() async throws {
        let driver = IncreasingNetworkDriver()
        let model = try makeNetworkModel(driver)
        model.start()
        defer { model.stop() }
        try await eventually { model.networkFrames.count >= 2 }
        model.toggleDisplayHold()
        let held = model.networkFrames.last?.id
        let end = model.displayedEndTime
        let before = await driver.readCount
        try await eventually { await driver.readCount >= before + 5 }
        XCTAssertEqual(model.networkFrames.last?.id, held)
        XCTAssertEqual(model.displayedEndTime, end)
        model.toggleDisplayHold()
        XCTAssertNotEqual(model.networkFrames.last?.id, held)
        XCTAssertEqual(model.networkReadings.last?.interfaceName, "en0")
    }

    func testNetworkScopeUsesOneInterfaceAndSplitsPrimaryChanges() async throws {
        let driver = IncreasingNetworkDriver()
        let model = try makeNetworkModel(driver)
        model.start()
        defer { model.stop() }
        try await eventually { model.networkFrames.count >= 3 }
        XCTAssertEqual(model.reading(for: .networkReceived)?.numericValue, 100)
        model.networkScope = .interface(try CapturedInterfaceID(index: 9, name: "utun9"))
        XCTAssertEqual(model.reading(for: .networkReceived)?.numericValue, 1000)
        XCTAssertEqual(model.networkReadings.last?.interfaceName, "utun9")
        model.networkScope = .interface(try CapturedInterfaceID(index: 99, name: "missing"))
        XCTAssertNil(model.reading(for: .networkReceived)?.numericValue)
        XCTAssertEqual(model.reading(for: .networkReceived)?.availability, .gap)
        model.networkScope = .primary
        await driver.changePrimary(to: "utun9")
        try await eventually { model.networkFrames.last?.primaryInterface?.name == "utun9" }
        XCTAssertGreaterThan(Set(model.points(for: .networkReceived).map(\.segment)).count, 1)
    }

    func testExplicitInterfaceRemainsUsableWithoutPrimaryRouteMetadata() async throws {
        let driver = IncreasingNetworkDriver()
        await driver.changePrimary(to: nil)
        let model = try makeNetworkModel(driver)
        model.start()
        defer { model.stop() }
        try await eventually { model.networkFrames.count >= 2 }
        XCTAssertEqual(model.reading(for: .networkReceived)?.availability, .unavailable)
        model.networkScope = .interface(try CapturedInterfaceID(index: 2, name: "en0"))
        XCTAssertEqual(model.reading(for: .networkReceived)?.numericValue, 100)
    }

    func testStorageScopeSelectsOneDeviceWithoutSummingDrivers() async throws {
        let driver = IncreasingDiskDriver()
        let model = try makeDiskModel(driver)
        model.start()
        defer { model.stop() }
        try await eventually { model.diskFrames.count >= 2 }
        XCTAssertEqual(model.reading(for: .diskRead)?.numericValue, 100)
        await driver.changeDevices(to: [1, 2])
        try await eventually { model.diskFrames.last?.devices.count == 2 }
        XCTAssertNil(model.reading(for: .diskRead)?.numericValue)
        XCTAssertEqual(model.storageSelectionMessage, "Choose a storage device")
        XCTAssertEqual(model.diskReadings.last?.status, "Choose a storage device")
        let selected = try CapturedStorageID(registryEntryID: 2)
        model.storageScope = .device(selected)
        try await eventually { model.reading(for: .diskRead)?.numericValue == 200 }
        XCTAssertEqual(model.diskReadings.last?.deviceName, "Device 2")
        await driver.changeDevices(to: [1])
        try await eventually { model.diskFrames.last?.devices.count == 1 }
        XCTAssertEqual(model.storageScope, .device(selected))
        XCTAssertNil(model.reading(for: .diskRead)?.numericValue)
        XCTAssertEqual(model.storageSelectionMessage, "Selected storage device is not observed")
        XCTAssertEqual(model.diskReadings.last?.status, "Selected storage device is not observed")
    }

    func testStorageAutomaticSelectionRequiresCompleteInventory() async throws {
        let driver = IncreasingDiskDriver()
        await driver.makeInventoryIncomplete()
        let model = try makeDiskModel(driver)
        model.start()
        defer { model.stop() }
        try await eventually { model.diskFrames.count >= 2 }
        XCTAssertNil(model.reading(for: .diskRead)?.numericValue)
        model.storageScope = .device(try CapturedStorageID(registryEntryID: 1))
        XCTAssertEqual(model.reading(for: .diskRead)?.numericValue, 100)
    }

    func testStorageDisplayHoldPreservesHistoryWhileSamplingContinues() async throws {
        let driver = IncreasingDiskDriver()
        let model = try makeDiskModel(driver)
        model.start()
        defer { model.stop() }
        try await eventually { model.diskFrames.count >= 2 }
        model.toggleDisplayHold()
        let held = model.diskFrames.last?.id
        let end = model.displayedEndTime
        let count = await driver.readCount
        try await eventually { await driver.readCount >= count + 4 }
        XCTAssertEqual(model.diskFrames.last?.id, held)
        XCTAssertEqual(model.displayedEndTime, end)
        model.toggleDisplayHold()
        XCTAssertNotEqual(model.diskFrames.last?.id, held)
    }

    private func makeDiskModel(_ driver: IncreasingDiskDriver) throws -> DashboardModel {
        DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10),
            diskMonitor: try DiskMonitor(driver: driver)
        )
    }

    private func makeNetworkModel(_ driver: IncreasingNetworkDriver) throws -> DashboardModel {
        DashboardModel(
            monitor: try SystemMonitor(driver: IncreasingHostDriver()), interval: .milliseconds(10),
            networkMonitor: try NetworkMonitor(driver: driver)
        )
    }

    private func process(
        pid: Int32, name: String, uid: UInt32, cpu: MetricReading, memory: Double
    ) throws -> ProcessReading {
        ProcessReading(
            id: try ProcessIdentity(pid: pid, startSeconds: 100, startMicroseconds: 0),
            parentPID: 0, uid: uid, name: name,
            stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date()),
            cpuPercentOfMachine: cpu, memoryFootprintBytes: try .measured(memory),
            diskReadBytesPerSecond: .collecting(), diskWriteBytesPerSecond: .collecting(),
            executablePath: nil, responsiblePID: nil
        )
    }

    private func eventually(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition did not become true before the deadline")
        throw CancellationError()
    }
}

private actor IncreasingDiskDriver: DiskSampleReading {
    private let clock = UUID()
    private var identifiers: [UInt64] = [1]
    private var incomplete = false
    private(set) var readCount: UInt64 = 0

    func changeDevices(to identifiers: [UInt64]) { self.identifiers = identifiers }
    func makeInventoryIncomplete() { incomplete = true }

    func read() async -> RawDiskSnapshot {
        readCount += 1
        let devices = identifiers.map {
            RawDiskDevice(
                registryEntryID: $0, name: "Device \($0)", monotonicNanoseconds: readCount * 1_000_000_000,
                counters: .success(DiskByteCounters(readBytes: readCount * $0 * 100, writtenBytes: readCount * $0))
            )
        }
        return RawDiskSnapshot(
            clockID: clock, monotonicNanoseconds: readCount * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(readCount)),
            enumeration: .success(DiskEnumeration(
                devices: devices,
                failures: incomplete ? [DiskReadFailure(registryEntryID: nil, error: .unavailable(reason: "Fixture"))] : [],
                isTruncated: incomplete
            ))
        )
    }
}

private actor IncreasingNetworkDriver: NetworkSampleReading {
    private let clock = UUID()
    private var primary: String? = "en0"
    private(set) var readCount: UInt64 = 0

    func changePrimary(to name: String?) { primary = name }

    func read() async -> RawNetworkSnapshot {
        readCount += 1
        let stamp = readCount * 1_000_000_000
        let rows = [
            RawNetworkInterface(
                index: 2, name: "en0", linkState: .up, receivedBytes: readCount * 100,
                sentBytes: readCount * 10, monotonicNanoseconds: stamp
            ),
            RawNetworkInterface(
                index: 9, name: "utun9", linkState: .up, receivedBytes: readCount * 1000,
                sentBytes: readCount * 20, monotonicNanoseconds: stamp
            )
        ]
        return RawNetworkSnapshot(
            clockID: clock, monotonicNanoseconds: stamp,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(readCount)),
            enumeration: .success(NetworkEnumeration(interfaces: rows)),
            primaryInterface: primary.map { .success(PrimaryNetworkInterface(name: $0, family: .ipv4)) }
                ?? .failure(.unavailable(reason: "No primary interface"))
        )
    }
}

private actor IncreasingProcessDriver: ProcessSampleReading {
    private let clock = UUID()
    private(set) var readCount: UInt64 = 0

    func read() async -> RawProcessSnapshot {
        readCount += 1
        return RawProcessSnapshot(
            clockID: clock, monotonicNanoseconds: readCount * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(readCount)),
            logicalCPUCount: 4, collectorPID: 42,
            enumeration: .success(ProcessEnumeration(processes: [RawProcessInfo(
                pid: 42, parentPID: 1, uid: 501, startSeconds: 100,
                startMicroseconds: 0, name: "Fixture", monotonicNanoseconds: readCount * 1_000_000_000,
                counters: .success(ProcessCounters(
                    userNanoseconds: readCount, systemNanoseconds: 0,
                    physicalFootprintBytes: readCount, diskReadBytes: readCount, diskWriteBytes: 0
                ))
            )]))
        )
    }
}

private actor ScriptedSockets: ProcessSocketReading {
    private(set) var reads = 0

    func sockets(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<RawProcessSockets, SocketReadError> {
        reads += 1
        guard pid == 42 else { return .failure(.notPermitted) }
        return .success(RawProcessSockets(sockets: [
            RawSocket(descriptor: 3, transport: .tcp, tcpState: 1, localAddress: "127.0.0.1", localPort: 8080, remoteAddress: "", remotePort: 0),
            RawSocket(descriptor: 4, transport: .tcp, tcpState: 4, localAddress: "10.0.0.2", localPort: 50000, remoteAddress: "17.253.144.10", remotePort: 443)
        ], truncated: false))
    }
}

private actor SwitchingSensorDriver: SensorSampleReading {
    private let clock = UUID()
    private var readCount: UInt64 = 0

    func read() async -> RawSensorSnapshot {
        readCount += 1
        let key = (readCount / 3).isMultiple(of: 2) ? "Tp01" : "Tg05"
        return RawSensorSnapshot(
            clockID: clock, monotonicNanoseconds: readCount * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(readCount)),
            sensors: .success(RawSensors(
                power: [RawSensorValue(key: "PSTR", value: 9)],
                temperatures: [RawSensorValue(key: key, value: 60 + Double(readCount % 3))],
                fans: [], discoveryTruncated: false
            ))
        )
    }
}

private actor AlternatingPowerDriver: PowerSampleReading {
    private let clock = UUID()
    private var readCount: UInt64 = 0

    func read() async -> RawPowerSnapshot {
        readCount += 1
        let plugged = readCount.isMultiple(of: 2)
        return RawPowerSnapshot(
            clockID: clock, monotonicNanoseconds: readCount * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(readCount)),
            battery: .success(BatteryState(
                chargePercent: Double(50 + readCount), powerSource: plugged ? .externalPower : .battery,
                isCharging: plugged, minutesToEmpty: nil, minutesToFull: nil
            )),
            gauge: .failure(.unavailable(reason: "Fixture")),
            adapterWatts: .failure(.unavailable(reason: "Fixture"))
        )
    }
}

private actor CyclingGPUDriver: GPUSampleReading {
    private let clock = UUID()
    private var readCount: UInt64 = 0

    func read() async -> RawGPUSnapshot {
        readCount += 1
        let integrated = RawGPUDevice(registryEntryID: 1, name: "Integrated", statistics: .success(GPUStatistics(
            utilizationPercent: 10, rendererPercent: nil, tilerPercent: nil, inUseMemoryBytes: nil
        )))
        let discrete = RawGPUDevice(registryEntryID: 2, name: "Discrete", statistics: .success(GPUStatistics(
            utilizationPercent: 50, rendererPercent: nil, tilerPercent: nil, inUseMemoryBytes: nil
        )))
        return RawGPUSnapshot(
            clockID: clock, monotonicNanoseconds: readCount * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(readCount)),
            enumeration: .success(GPUEnumeration(
                devices: readCount.isMultiple(of: 2) ? [integrated] : [integrated, discrete]
            ))
        )
    }
}

private actor IncreasingHostDriver: HostSampleReading {
    private let clock = UUID()
    private let origin: Date
    private var wallOffset: TimeInterval = 0
    private(set) var readCount: UInt64 = 0

    init(origin: Date = Date(timeIntervalSince1970: 1_700_000_000)) { self.origin = origin }

    func skipWallTime() { wallOffset += 3600 }

    func read() async -> RawHostSnapshot {
        readCount += 1
        return RawHostSnapshot(
            clockID: clock, monotonicNanoseconds: readCount * 1_000_000_000,
            wallTime: origin.addingTimeInterval(Double(readCount) + wallOffset),
            inventory: HostInventory(
                operatingSystem: "Fixture", architecture: "fixture",
                logicalCPUCount: 4, physicalMemoryBytes: 4096 * 100
            ),
            cpu: .success(ProcessorTicks(
                user: readCount, system: 0, idle: readCount * 3, nice: 0
            )),
            memory: .success(MemoryPages(
                active: 10, inactive: 0, speculative: 0,
                wired: 2, compressed: 3, compressorContents: 6, purgeable: 0,
                fileBacked: 1, pageIns: readCount, swapIns: 0, swapOuts: 0,
                pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 8192, usedBytes: 4096)),
            memoryPressure: readCount.isMultiple(of: 2) ? .success(.warning) : .success(.normal),
            thermalPressure: readCount.isMultiple(of: 3) ? .success(.moderate) : .success(.nominal)
        )
    }
}
