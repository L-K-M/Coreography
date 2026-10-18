import Foundation
import Observation
import CoreographyKit

public enum DashboardMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case networkReceived
    case networkSent

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

@MainActor
@Observable
public final class DashboardModel {
    public private(set) var frames: [CapturedSnapshot] = []
    public private(set) var displayMode: DashboardDisplayMode = .live
    public private(set) var collectionError: String?
    public private(set) var processSnapshot: CapturedProcesses?
    public private(set) var networkFrames: [CapturedNetwork] = []
    public var networkScope: NetworkScope = .primary
    public var processFilter = ""
    public var processSort: ProcessSort = .cpu

    @ObservationIgnored private let monitor: SystemMonitor?
    @ObservationIgnored private let processMonitor: ProcessMonitor?
    @ObservationIgnored private let networkMonitor: NetworkMonitor?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let processInterval: Duration
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var liveFrames: [CapturedSnapshot] = []
    @ObservationIgnored private var liveProcesses: CapturedProcesses?
    @ObservationIgnored private var liveNetworkFrames: [CapturedNetwork] = []

    public init() {
        interval = .seconds(1)
        processInterval = .seconds(2)
        do {
            let system = try SystemMonitor()
            let processes = try ProcessMonitor()
            let network = try NetworkMonitor()
            monitor = system
            processMonitor = processes
            networkMonitor = network
        } catch {
            monitor = nil
            processMonitor = nil
            networkMonitor = nil
            collectionError = "Cannot initialize monitoring: \(error)"
        }
    }

    init(
        monitor: SystemMonitor, interval: Duration,
        processMonitor: ProcessMonitor? = nil, processInterval: Duration = .seconds(2),
        networkMonitor: NetworkMonitor? = nil
    ) {
        self.monitor = monitor
        self.interval = interval
        self.processMonitor = processMonitor
        self.processInterval = processInterval
        self.networkMonitor = networkMonitor
    }

    deinit { worker?.cancel() }

    public var latest: CapturedSnapshot? { frames.last }

    public var displayedEndTime: Date? {
        [latest?.stamp.wallTime, networkFrames.last?.stamp.wallTime].compactMap { $0 }.max()
    }

    public var selectedNetworkInterface: CapturedInterface? {
        networkFrames.last.flatMap(networkInterface(in:))
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

    public var visibleProcesses: [ObservedProcess] {
        ProcessList.rows(in: processSnapshot, matching: processFilter, sortedBy: processSort)
    }

    public func start() {
        guard worker == nil, let monitor else { return }
        let run = UUID()
        generation = run
        collectionError = nil
        let processMonitor = processMonitor
        let processInterval = processInterval
        let networkMonitor = networkMonitor

        worker = Task { [weak self] in
            defer {
                if let self, self.generation == run { self.worker = nil }
            }
            await monitor.reset()
            await processMonitor?.reset()
            await networkMonitor?.reset()
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
                    var processes: CapturedProcesses?
                    if let processMonitor, ContinuousClock.now >= nextProcessSample {
                        processes = try await processMonitor.sample()
                        nextProcessSample = ContinuousClock.now.advanced(by: processInterval)
                    }
                    guard let self, self.generation == run, !Task.isCancelled else { return }
                    self.liveFrames = history
                    if let processes { self.liveProcesses = processes }
                    if let network { self.liveNetworkFrames = network }
                    if self.displayMode == .live {
                        self.frames = history
                        if let processes { self.processSnapshot = processes }
                        if let network { self.networkFrames = network }
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
    }

    public func reading(for metric: DashboardMetric) -> DashboardReading? {
        switch metric {
        case .cpu: return latest?.cpuPercentOfMachine
        case .memory: return latest?.memoryUsedBytes
        case .networkReceived, .networkSent:
            guard let latestNetwork = networkFrames.last else { return nil }
            return networkReading(for: metric, in: latestNetwork)
        }
    }

    public func points(for metric: DashboardMetric) -> [DashboardPoint] {
        if metric == .networkReceived || metric == .networkSent { return networkPoints(for: metric) }
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
}
