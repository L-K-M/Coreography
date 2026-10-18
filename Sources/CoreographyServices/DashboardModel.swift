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
    public var processFilter = ""
    public var processSort: ProcessSort = .cpu
    public var processGrouping: ProcessGrouping = .app

    @ObservationIgnored private let monitor: SystemMonitor?
    @ObservationIgnored private let processMonitor: ProcessMonitor?
    @ObservationIgnored private let networkMonitor: NetworkMonitor?
    @ObservationIgnored private let diskMonitor: DiskMonitor?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let processInterval: Duration
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var liveFrames: [CapturedSnapshot] = []
    @ObservationIgnored private var liveProcesses: CapturedProcesses?
    @ObservationIgnored private var liveNetworkFrames: [CapturedNetwork] = []
    @ObservationIgnored private var liveDiskFrames: [CapturedDisks] = []

    public init() {
        interval = .seconds(1)
        processInterval = .seconds(2)
        do {
            let system = try SystemMonitor()
            let processes = try ProcessMonitor()
            let network = try NetworkMonitor()
            let disk = try DiskMonitor()
            monitor = system
            processMonitor = processes
            networkMonitor = network
            diskMonitor = disk
        } catch {
            monitor = nil
            processMonitor = nil
            networkMonitor = nil
            diskMonitor = nil
            collectionError = "Cannot initialize monitoring: \(error)"
        }
    }

    init(
        monitor: SystemMonitor, interval: Duration,
        processMonitor: ProcessMonitor? = nil, processInterval: Duration = .seconds(2),
        networkMonitor: NetworkMonitor? = nil, diskMonitor: DiskMonitor? = nil
    ) {
        self.monitor = monitor
        self.interval = interval
        self.processMonitor = processMonitor
        self.processInterval = processInterval
        self.networkMonitor = networkMonitor
        self.diskMonitor = diskMonitor
    }

    deinit { worker?.cancel() }

    public var latest: CapturedSnapshot? { frames.last }

    public var displayedEndTime: Date? {
        [latest?.stamp.wallTime, networkFrames.last?.stamp.wallTime, diskFrames.last?.stamp.wallTime]
            .compactMap { $0 }.max()
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

    public var visibleProcessRows: [ProcessRow] {
        ProcessGroups.rows(
            in: processSnapshot, matching: processFilter, sortedBy: processSort, grouping: processGrouping
        )
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

        worker = Task { [weak self] in
            defer {
                if let self, self.generation == run { self.worker = nil }
            }
            await monitor.reset()
            await processMonitor?.reset()
            await networkMonitor?.reset()
            await diskMonitor?.reset()
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
                    var processes: CapturedProcesses?
                    if let processMonitor, ContinuousClock.now >= nextProcessSample {
                        processes = try await processMonitor.sample()
                        nextProcessSample = ContinuousClock.now.advanced(by: processInterval)
                    }
                    guard let self, self.generation == run, !Task.isCancelled else { return }
                    self.liveFrames = history
                    if let processes { self.liveProcesses = processes }
                    if let network { self.liveNetworkFrames = network }
                    if let disks { self.liveDiskFrames = disks }
                    if self.displayMode == .live {
                        self.frames = history
                        if let processes { self.processSnapshot = processes }
                        if let network { self.networkFrames = network }
                        if let disks { self.diskFrames = disks }
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
        networkFrames = liveNetworkFrames
        diskFrames = liveDiskFrames
    }

    public func reading(for metric: DashboardMetric) -> DashboardReading? {
        switch metric {
        case .cpu: return latest?.cpuPercentOfMachine
        case .memory: return latest?.memoryUsedBytes
        case .networkReceived, .networkSent:
            guard let latestNetwork = networkFrames.last else { return nil }
            return networkReading(for: metric, in: latestNetwork)
        case .diskRead, .diskWritten:
            guard let frame = diskFrames.last else { return nil }
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
        var result: [MemoryPressureSpan] = []
        var previousTime: Date?
        for frame in frames {
            if frame.continuity == .interrupted { previousTime = nil }
            guard let level = frame.memory.pressureLevel else {
                previousTime = nil
                continue
            }
            if let previousTime {
                result.append(MemoryPressureSpan(
                    id: frame.id, start: previousTime, end: frame.stamp.wallTime, level: level
                ))
            }
            previousTime = frame.stamp.wallTime
        }
        return result
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
