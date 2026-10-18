import Foundation
import Observation
import CoreographyKit

public enum DashboardMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case networkReceived
    case networkSent
    case diskRead
    case diskWritten

    public var id: Self { self }
}

public enum DashboardDisplayMode: Equatable, Sendable {
    case live
    case held
}

public struct DashboardPoint: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let value: Double
    public let segment: Int
}

/// Memory lane layers, bottom to top; app, wired and compressed sum to used.
public enum MemoryCategory: String, CaseIterable, Identifiable, Sendable {
    case app
    case wired
    case compressed
    case cached

    public var id: Self { self }
}

/// One stacked layer at one sample: the layer spans `lower...upper` bytes.
public struct MemoryStackPoint: Identifiable, Sendable {
    public let id: String
    public let time: Date
    public let category: MemoryCategory
    public let lower: Double
    public let upper: Double
    public let segment: Int

    public var value: Double { upper - lower }
}

/// Pressure between two consecutive samples, labelled with the later reading.
public struct MemoryPressureSpan: Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let level: MemoryPressureLevel
}

/// Thermal pressure between two consecutive samples, labelled with the later reading.
public struct ThermalPressureSpan: Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let level: ThermalPressureLevel
}

/// Time on external power between two consecutive samples.
public struct ExternalPowerSpan: Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
}

public struct GPUTableReading: Identifiable, Sendable {
    public let id: String
    public let time: Date
    public let name: String
    public let device: CapturedGPUDevice
}

/// One GPU's utilization history; missing samples split segments.
public struct GPUSeries: Identifiable, Sendable {
    public let id: GPUDeviceID
    public let name: String
    public let points: [DashboardPoint]
}

@MainActor
@Observable
public final class DashboardModel {
    public private(set) var frames: [CapturedSnapshot] = []
    public private(set) var displayMode: DashboardDisplayMode = .live
    public private(set) var collectionError: String?
    public private(set) var processSnapshot: CapturedProcesses?
    public private(set) var networkFrames: [CapturedNetwork] = []
    public var networkScope: NetworkScope = .primary
    public private(set) var diskFrames: [CapturedDisks] = []
    public var storageScope: StorageScope = .automatic
    public private(set) var gpuFrames: [CapturedGPU] = []
    public private(set) var powerFrames: [CapturedPower] = []
    public private(set) var sensorFrames: [CapturedSensors] = []
    public var processFilter = ""
    public var processSort: ProcessSort = .cpu
    public var processGrouping: ProcessGrouping = .app
    /// The shared hover time across all lanes; nil follows the live edge.
    public var cursorTime: Date?
    public var timeRange: TimeRange = .minute
    /// A dragged time range; cleared only explicitly (plan: Esc or clear).
    public var selection: ClosedRange<Date>?
    /// The range while a drag is in progress; reports wait for the drag to end.
    public var draftSelection: ClosedRange<Date>?
    public private(set) var markers: [TimelineMarker] = []
    /// One app scoping every view (plan P8); cleared only by its clear button.
    public var scopedApp: String?
    public private(set) var actionMessage: String?
    public private(set) var contributorHistory: [ContributorSnapshot] = []

    @ObservationIgnored private let monitor: SystemMonitor?
    @ObservationIgnored private let controller: ProcessController
    @ObservationIgnored private let processMonitor: ProcessMonitor?
    @ObservationIgnored private let networkMonitor: NetworkMonitor?
    @ObservationIgnored private let diskMonitor: DiskMonitor?
    @ObservationIgnored private let gpuMonitor: GPUMonitor?
    @ObservationIgnored private let powerMonitor: PowerMonitor?
    @ObservationIgnored private let sensorMonitor: SensorMonitor?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let processInterval: Duration
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var liveFrames: [CapturedSnapshot] = []
    @ObservationIgnored private var liveProcesses: CapturedProcesses?
    @ObservationIgnored private var liveContributorHistory: [ContributorSnapshot] = []
    @ObservationIgnored private var liveLedger = AppLedger(capacity: contributorCapacity)
    private var ledger = AppLedger(capacity: contributorCapacity)
    @ObservationIgnored private var liveNetworkFrames: [CapturedNetwork] = []
    @ObservationIgnored private var liveDiskFrames: [CapturedDisks] = []
    @ObservationIgnored private var liveGPUFrames: [CapturedGPU] = []
    @ObservationIgnored private var livePowerFrames: [CapturedPower] = []
    @ObservationIgnored private var liveSensorFrames: [CapturedSensors] = []

    public init() {
        controller = ProcessController()
        interval = .seconds(1)
        processInterval = .seconds(2)
        do {
            let system = try SystemMonitor()
            let processes = try ProcessMonitor()
            let network = try NetworkMonitor()
            let disk = try DiskMonitor()
            let gpu = try GPUMonitor()
            let power = try PowerMonitor()
            let sensors = try SensorMonitor()
            monitor = system
            processMonitor = processes
            networkMonitor = network
            diskMonitor = disk
            gpuMonitor = gpu
            powerMonitor = power
            sensorMonitor = sensors
        } catch {
            monitor = nil
            processMonitor = nil
            networkMonitor = nil
            diskMonitor = nil
            gpuMonitor = nil
            powerMonitor = nil
            sensorMonitor = nil
            collectionError = "Cannot initialize monitoring: \(error)"
        }
    }

    init(
        monitor: SystemMonitor, interval: Duration,
        processMonitor: ProcessMonitor? = nil, processInterval: Duration = .seconds(2),
        networkMonitor: NetworkMonitor? = nil, diskMonitor: DiskMonitor? = nil,
        gpuMonitor: GPUMonitor? = nil, powerMonitor: PowerMonitor? = nil,
        sensorMonitor: SensorMonitor? = nil, controller: ProcessController = ProcessController()
    ) {
        self.controller = controller
        self.monitor = monitor
        self.interval = interval
        self.processMonitor = processMonitor
        self.processInterval = processInterval
        self.networkMonitor = networkMonitor
        self.diskMonitor = diskMonitor
        self.gpuMonitor = gpuMonitor
        self.powerMonitor = powerMonitor
        self.sensorMonitor = sensorMonitor
    }

    deinit { worker?.cancel() }

    public var latest: CapturedSnapshot? { frames.last }

    // A cursor reads the nearest sample within these windows, or nothing.
    private static let cursorTolerance: TimeInterval = 1.5
    private static let contributorTolerance: TimeInterval = 2.5
    /// One hour of two-second process samples, matching live history.
    private static let contributorCapacity = 1800

    /// Host frame at the cursor, or the latest frame without one.
    public var displayedFrame: CapturedSnapshot? { atCursor(frames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedGPUFrame: CapturedGPU? { atCursor(gpuFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedPowerFrame: CapturedPower? { atCursor(powerFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedSensorFrame: CapturedSensors? {
        atCursor(sensorFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime }
    }

    /// System draw from one qualified source (plan): an SMC rail where the
    /// Mac publishes one, otherwise battery discharge while unplugged.
    public var displayedSystemPower: DashboardReading? {
        if let rail = displayedSensorFrame?.systemPowerWatts, rail.numericValue != nil { return rail }
        return displayedPowerFrame?.systemPowerWatts ?? displayedSensorFrame?.systemPowerWatts
    }
    public var displayedContributors: ContributorSnapshot? {
        atCursor(contributorHistory, tolerance: Self.contributorTolerance) { $0.time }
    }

    private func atCursor<Frame>(
        _ frames: [Frame], tolerance: TimeInterval, time: (Frame) -> Date
    ) -> Frame? {
        guard let cursorTime else { return frames.last }
        let nearest = frames.min {
            abs(time($0).timeIntervalSince(cursorTime)) < abs(time($1).timeIntervalSince(cursorTime))
        }
        guard let nearest, abs(time(nearest).timeIntervalSince(cursorTime)) <= tolerance else { return nil }
        return nearest
    }

    public var displayedEndTime: Date? {
        [
            latest?.stamp.wallTime, networkFrames.last?.stamp.wallTime,
            diskFrames.last?.stamp.wallTime, gpuFrames.last?.stamp.wallTime,
            powerFrames.last?.stamp.wallTime, sensorFrames.last?.stamp.wallTime
        ].compactMap { $0 }.max()
    }

    public var networkReadings: [NetworkTableReading] {
        networkFrames.suffix(10).map { frame in
            let interface = networkInterface(in: frame)
            return NetworkTableReading(
                id: frame.id, time: interface?.stamp.wallTime ?? frame.stamp.wallTime,
                interfaceName: interface?.id.name,
                received: networkReading(for: .networkReceived, in: frame),
                sent: networkReading(for: .networkSent, in: frame)
            )
        }
    }

    public var diskReadings: [DiskTableReading] {
        diskFrames.suffix(10).map { frame in
            let device = storageDevice(in: frame)
            return DiskTableReading(
                id: frame.id, time: device?.stamp.wallTime ?? frame.stamp.wallTime, deviceName: device?.name,
                status: device == nil ? storageSelectionMessage(in: frame) : nil,
                read: device?.readBytesPerSecond, written: device?.writtenBytesPerSecond
            )
        }
    }

    public var gpuReadings: [GPUTableReading] {
        gpuFrames.suffix(10).flatMap { frame in
            frame.devices.map {
                GPUTableReading(
                    id: "\(frame.id)-\($0.id.registryEntryID)", time: frame.stamp.wallTime,
                    name: $0.name, device: $0
                )
            }
        }
    }

    public var storageSelectionMessage: String {
        guard let frame = diskFrames.last else { return "Collecting storage devices…" }
        return storageSelectionMessage(in: frame)
    }

    private func storageSelectionMessage(in frame: CapturedDisks) -> String {
        if let reason = frame.enumeration.reason { return reason }
        if let device = storageDevice(in: frame) {
            return device.readBytesPerSecond.reason ?? "IOKit · storage-driver byte counters"
        }
        if frame.devices.isEmpty { return "No selectable storage device was observed" }
        if case .automatic = storageScope { return "Choose a storage device" }
        return "Selected storage device is not observed"
    }

    /// Totals for the selected range, from displayed (possibly held) data.
    /// What a range report depends on. Hovering re-renders the window at
    /// pointer rate, so the report is rebuilt only when one of these changes.
    private struct RangeReportInputs: Equatable {
        let selection: ClosedRange<Date>
        let ledgerIntervals: Int
        let ledgerEnd: Date?
        let frame: UUID?
        let gpuFrame: UUID?
        let sensorFrame: UUID?
    }

    @ObservationIgnored private var rangeReportCache: (inputs: RangeReportInputs, report: RangeReport)?
    /// How many reports were built; tests check that rereading reuses one.
    @ObservationIgnored private(set) var rangeReportBuilds = 0

    public var rangeReport: RangeReport? {
        guard let selection else { return nil }
        let inputs = RangeReportInputs(
            selection: selection, ledgerIntervals: ledger.intervals.count, ledgerEnd: ledger.intervals.last?.end,
            frame: frames.last?.id, gpuFrame: gpuFrames.last?.id, sensorFrame: sensorFrames.last?.id
        )
        if let cache = rangeReportCache, cache.inputs == inputs { return cache.report }
        let report = RangeReport.make(
            range: selection, ledger: ledger, frames: frames, gpuFrames: gpuFrames, sensorFrames: sensorFrames
        )
        rangeReportCache = (inputs, report)
        rangeReportBuilds += 1
        return report
    }

    /// Also drops a drag the system cancelled before it ended, whose band
    /// would otherwise stay on every lane with no panel to clear it.
    public func clearSelection() {
        selection = nil
        draftSelection = nil
    }

    /// The selected range as an export document of displayed (possibly held) data.
    public var rangeExport: RangeExport.Document? {
        guard let selection else { return nil }
        let frames = DashboardFrames(
            host: frames, network: networkFrames, disks: diskFrames,
            gpu: gpuFrames, power: powerFrames, sensors: sensorFrames
        )
        let apps = ledger.totals(in: selection).apps.sorted { $0.cpuSeconds > $1.cpuSeconds }
        return RangeExport.document(range: selection, model: frames, apps: apps)
    }

    /// What quitting this process would do, for confirmation before sending.
    public func actionRequest(for process: ObservedProcess, mode: QuitMode) -> ProcessActionRequest {
        ProcessActions.request(for: process, mode: mode, in: processSnapshot)
    }

    /// Send a confirmed request; the identity is re-checked at the last moment.
    public func perform(_ request: ProcessActionRequest) {
        switch controller.terminate(request.target, mode: request.mode) {
        case .requested:
            let verb = request.mode == .forced ? "Force quit" : "Quit"
            markers.append(TimelineMarker(id: UUID(), time: Date(), label: "\(verb) \(request.name)"))
            actionMessage = "\(verb) requested for \(request.name) (PID \(request.target.pid))"
        case .failed(let reason):
            actionMessage = "\(request.name): \(reason)"
        }
    }

    /// Coreography's own process cost, from the latest process sample.
    public var selfCost: SelfCost? {
        SelfCost.measure(in: processSnapshot, logicalCPUCount: latest?.inventory.logicalCPUCount)
    }

    public var visibleProcessRows: [ProcessRow] {
        let rows = ProcessGroups.rows(
            in: processSnapshot, matching: processFilter, sortedBy: processSort, grouping: processGrouping
        )
        guard let scopedApp else { return rows }
        return rows.filter { $0.appName == scopedApp }
    }

    /// The scoped app's CPU share and disk rate from the ledger, for lane overlays.
    public func scopedSeries() -> (cpu: [DashboardPoint], disk: [DashboardPoint])? {
        guard let scopedApp else { return nil }
        return ledger.series(for: scopedApp)
    }

    public func start() {
        guard worker == nil, let monitor else { return }
        let run = UUID()
        generation = run
        collectionError = nil
        let processMonitor = processMonitor
        let processInterval = processInterval
        let networkMonitor = networkMonitor
        let diskMonitor = diskMonitor
        let gpuMonitor = gpuMonitor
        let powerMonitor = powerMonitor
        let sensorMonitor = sensorMonitor

        worker = Task { [weak self] in
            defer {
                if let self, self.generation == run { self.worker = nil }
            }
            await monitor.reset()
            await processMonitor?.reset()
            await networkMonitor?.reset()
            await diskMonitor?.reset()
            await gpuMonitor?.reset()
            await powerMonitor?.reset()
            await sensorMonitor?.reset()
            var nextProcessSample = ContinuousClock.now
            while !Task.isCancelled {
                do {
                    _ = try await monitor.sample()
                    let history = await monitor.history()
                    var network: [CapturedNetwork]?
                    if let networkMonitor {
                        _ = try await networkMonitor.sample()
                        network = await networkMonitor.history()
                    }
                    var disks: [CapturedDisks]?
                    if let diskMonitor {
                        _ = try await diskMonitor.sample()
                        disks = await diskMonitor.history()
                    }
                    var gpus: [CapturedGPU]?
                    if let gpuMonitor {
                        _ = try await gpuMonitor.sample()
                        gpus = await gpuMonitor.history()
                    }
                    var power: [CapturedPower]?
                    if let powerMonitor {
                        _ = try await powerMonitor.sample()
                        power = await powerMonitor.history()
                    }
                    var sensors: [CapturedSensors]?
                    if let sensorMonitor {
                        _ = try await sensorMonitor.sample()
                        sensors = await sensorMonitor.history()
                    }
                    var processes: CapturedProcesses?
                    if let processMonitor, ContinuousClock.now >= nextProcessSample {
                        processes = try await processMonitor.sample()
                        nextProcessSample = ContinuousClock.now.advanced(by: processInterval)
                    }
                    guard let self, self.generation == run, !Task.isCancelled else { return }
                    self.liveFrames = history
                    if let processes {
                        self.liveProcesses = processes
                        self.liveContributorHistory.append(Contributors.snapshot(from: processes))
                        self.liveContributorHistory = Array(self.liveContributorHistory.suffix(Self.contributorCapacity))
                        self.liveLedger.record(processes, logicalCPUCount: history.last?.inventory.logicalCPUCount)
                    }
                    if let network { self.liveNetworkFrames = network }
                    if let disks { self.liveDiskFrames = disks }
                    if let gpus { self.liveGPUFrames = gpus }
                    if let power { self.livePowerFrames = power }
                    if let sensors { self.liveSensorFrames = sensors }
                    if self.displayMode == .live {
                        self.frames = history
                        if let processes {
                            self.processSnapshot = processes
                            self.contributorHistory = self.liveContributorHistory
                            self.ledger = self.liveLedger
                        }
                        if let network { self.networkFrames = network }
                        if let disks { self.diskFrames = disks }
                        if let gpus { self.gpuFrames = gpus }
                        if let power { self.powerFrames = power }
                        if let sensors { self.sensorFrames = sensors }
                    }
                    try await Task.sleep(for: self.interval)
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, self.generation == run else { return }
                    self.collectionError = "Collection failed: \(error)"
                    return
                }
            }
        }
    }

    public func stop() {
        generation = UUID()
        worker?.cancel()
        worker = nil
    }

    public func toggleDisplayHold() {
        if displayMode == .live {
            displayMode = .held
            return
        }
        displayMode = .live
        frames = liveFrames
        processSnapshot = liveProcesses
        contributorHistory = liveContributorHistory
        ledger = liveLedger
        networkFrames = liveNetworkFrames
        diskFrames = liveDiskFrames
        gpuFrames = liveGPUFrames
        powerFrames = livePowerFrames
        sensorFrames = liveSensorFrames
    }

    public func reading(for metric: DashboardMetric) -> DashboardReading? {
        switch metric {
        case .cpu: return displayedFrame?.cpuPercentOfMachine
        case .memory: return displayedFrame?.memoryUsedBytes
        case .networkReceived, .networkSent:
            guard let frame = atCursor(networkFrames, tolerance: Self.cursorTolerance, time: { $0.stamp.wallTime })
            else { return nil }
            return networkReading(for: metric, in: frame)
        case .diskRead, .diskWritten:
            guard let frame = atCursor(diskFrames, tolerance: Self.cursorTolerance, time: { $0.stamp.wallTime })
            else { return nil }
            if let device = storageDevice(in: frame) {
                return metric == .diskRead ? device.readBytesPerSecond : device.writtenBytesPerSecond
            }
            return frame.enumeration.numericValue == nil ? frame.enumeration : nil
        }
    }

    public func points(for metric: DashboardMetric) -> [DashboardPoint] {
        if metric == .networkReceived || metric == .networkSent { return networkPoints(for: metric) }
        if metric == .diskRead || metric == .diskWritten { return diskPoints(for: metric) }
        var result: [DashboardPoint] = []
        var segment = 0
        for frame in frames {
            if frame.continuity == .interrupted { segment += 1 }
            let reading = metric == .cpu ? frame.cpuPercentOfMachine : frame.memoryUsedBytes
            guard let value = reading.numericValue else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(
                id: frame.id, time: frame.stamp.wallTime, value: value, segment: segment
            ))
        }
        return result
    }

    /// Stack only frames with every layer known; any missing layer is a gap.
    public func memoryStack() -> [MemoryStackPoint] {
        var result: [MemoryStackPoint] = []
        var segment = 0
        for frame in frames {
            if frame.continuity == .interrupted { segment += 1 }
            let detail = frame.memory
            let layers: [(MemoryCategory, MetricReading)] = [
                (.app, detail.appBytes), (.wired, detail.wiredBytes),
                (.compressed, detail.compressedBytes), (.cached, detail.cachedBytes)
            ]
            let values = layers.compactMap { $0.1.numericValue }
            guard values.count == layers.count else {
                segment += 1
                continue
            }

            var lower = 0.0
            for ((category, _), value) in zip(layers, values) {
                result.append(MemoryStackPoint(
                    id: "\(frame.id)-\(category.rawValue)", time: frame.stamp.wallTime,
                    category: category, lower: lower, upper: lower + value, segment: segment
                ))
                lower += value
            }
        }
        return result
    }

    public func memoryPressureSpans() -> [MemoryPressureSpan] {
        levelSpans { $0.memory.pressureLevel }.map {
            MemoryPressureSpan(id: $0.id, start: $0.start, end: $0.end, level: $0.level)
        }
    }

    public func thermalPressureSpans() -> [ThermalPressureSpan] {
        levelSpans { ThermalPressureLevel(reading: $0.thermalPressure) }.map {
            ThermalPressureSpan(id: $0.id, start: $0.start, end: $0.end, level: $0.level)
        }
    }

    /// Span consecutive known levels; interruptions and missing levels break the band.
    private func levelSpans<Level: Equatable>(
        _ level: (CapturedSnapshot) -> Level?
    ) -> [(id: UUID, start: Date, end: Date, level: Level)] {
        var result: [(id: UUID, start: Date, end: Date, level: Level)] = []
        var previousTime: Date?
        for frame in frames {
            if frame.continuity == .interrupted { previousTime = nil }
            guard let current = level(frame) else {
                previousTime = nil
                continue
            }
            if let previousTime {
                // Contiguous spans at one level merge, so an hour stays a few rectangles.
                if let last = result.last, last.end == previousTime, last.level == current {
                    result[result.count - 1].end = frame.stamp.wallTime
                } else {
                    result.append((id: frame.id, start: previousTime, end: frame.stamp.wallTime, level: current))
                }
            }
            previousTime = frame.stamp.wallTime
        }
        return result
    }

    /// Hottest-sensor history; a new hottest key starts a new segment, so a
    /// change of sensor never reads as a temperature trend.
    public func hottestTemperaturePoints() -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        var previousKey: String?
        for frame in sensorFrames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let hottest = frame.hottest, let value = hottest.celsius.numericValue else {
                segment += 1
                previousKey = nil
                continue
            }
            if let previousKey, previousKey != hottest.key { segment += 1 }
            previousKey = hottest.key
            result.append(DashboardPoint(id: frame.id, time: frame.stamp.wallTime, value: value, segment: segment))
        }
        return result
    }

    /// Battery charge history; a missing reading or interruption splits the line.
    public func batteryChargePoints() -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        for frame in powerFrames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let value = frame.batteryChargePercent.numericValue else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(id: frame.id, time: frame.stamp.wallTime, value: value, segment: segment))
        }
        return result
    }

    /// Spans ending at samples taken on external power; unknown sources break the band.
    public func externalPowerSpans() -> [ExternalPowerSpan] {
        var result: [ExternalPowerSpan] = []
        var previousTime: Date?
        for frame in powerFrames {
            if frame.continuity == .interrupted { previousTime = nil }
            guard let source = frame.powerSource else {
                previousTime = nil
                continue
            }
            if source == .externalPower, let previousTime {
                if let last = result.last, last.end == previousTime {
                    result[result.count - 1] = ExternalPowerSpan(id: last.id, start: last.start, end: frame.stamp.wallTime)
                } else {
                    result.append(ExternalPowerSpan(id: frame.id, start: previousTime, end: frame.stamp.wallTime))
                }
            }
            previousTime = frame.stamp.wallTime
        }
        return result
    }

    /// One series per observed GPU, in first-seen order.
    public func gpuSeries() -> [GPUSeries] {
        var order: [GPUDeviceID] = []
        var names: [GPUDeviceID: String] = [:]
        var points: [GPUDeviceID: [DashboardPoint]] = [:]
        var segments: [GPUDeviceID: Int] = [:]
        var interruptions = 0
        for frame in gpuFrames {
            if frame.continuity == .interrupted { interruptions += 1 }
            let present = Set(frame.devices.map(\.id))
            // A device absent from a frame must not be bridged across it.
            for id in order where !present.contains(id) { segments[id, default: 0] += 1 }
            for device in frame.devices {
                if names[device.id] == nil { order.append(device.id) }
                names[device.id] = device.name
                guard let value = device.utilizationPercent.numericValue else {
                    segments[device.id, default: 0] += 1
                    continue
                }
                points[device.id, default: []].append(DashboardPoint(
                    id: frame.id, time: frame.stamp.wallTime, value: value,
                    segment: interruptions + segments[device.id, default: 0]
                ))
            }
        }
        return order.map { GPUSeries(id: $0, name: names[$0] ?? "GPU", points: points[$0] ?? []) }
    }

    private func networkInterface(in frame: CapturedNetwork) -> CapturedInterface? {
        let identity: CapturedInterfaceID?
        switch networkScope {
        case .primary: identity = frame.primaryInterface
        case .interface(let selected): identity = selected
        }
        return frame.interfaces.first { $0.id == identity }
    }

    private func networkReading(for metric: DashboardMetric, in frame: CapturedNetwork) -> DashboardReading {
        if let interface = networkInterface(in: frame) {
            return metric == .networkReceived
                ? interface.receivedBytesPerSecond : interface.sentBytesPerSecond
        }
        if frame.enumeration.numericValue == nil { return frame.enumeration }
        if networkScope == .primary, let issue = frame.primaryIssue { return issue }
        return .gap(reason: "Selected interface is not observed; choose an available interface")
    }

    private func networkPoints(for metric: DashboardMetric) -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        var previousInterface: CapturedInterfaceID?
        for frame in networkFrames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let interface = networkInterface(in: frame) else {
                segment += 1
                continue
            }
            if let previousInterface, previousInterface != interface.id { segment += 1 }
            previousInterface = interface.id
            let reading = metric == .networkReceived
                ? interface.receivedBytesPerSecond : interface.sentBytesPerSecond
            guard let value = reading.numericValue else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(
                id: frame.id, time: interface.stamp.wallTime, value: value, segment: segment
            ))
        }
        return result
    }

    private func storageDevice(in frame: CapturedDisks) -> CapturedStorageDevice? {
        switch storageScope {
        case .automatic:
            guard frame.devices.count == 1, frame.issues.isEmpty, !frame.enumerationTruncated else { return nil }
            return frame.devices.first
        case .device(let selected): return frame.devices.first { $0.id == selected }
        }
    }

    private func diskPoints(for metric: DashboardMetric) -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        var previousDevice: CapturedStorageID?
        for frame in diskFrames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let device = storageDevice(in: frame) else {
                segment += 1
                continue
            }
            if let previousDevice, previousDevice != device.id { segment += 1 }
            previousDevice = device.id
            let reading = metric == .diskRead ? device.readBytesPerSecond : device.writtenBytesPerSecond
            guard let value = reading.numericValue else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(
                id: frame.id, time: device.stamp.wallTime, value: value, segment: segment
            ))
        }
        return result
    }
}
