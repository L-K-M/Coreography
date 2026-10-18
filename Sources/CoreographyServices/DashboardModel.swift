import Foundation
import Observation
import CoreographyKit

public enum DashboardMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory

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
    public var processFilter = ""
    public var processSort: ProcessSort = .cpu

    @ObservationIgnored private let monitor: SystemMonitor?
    @ObservationIgnored private let processMonitor: ProcessMonitor?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let processInterval: Duration
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var liveFrames: [CapturedSnapshot] = []
    @ObservationIgnored private var liveProcesses: CapturedProcesses?

    public init() {
        interval = .seconds(1)
        processInterval = .seconds(2)
        do {
            let system = try SystemMonitor()
            let processes = try ProcessMonitor()
            monitor = system
            processMonitor = processes
        } catch {
            monitor = nil
            processMonitor = nil
            collectionError = "Cannot initialize monitoring: \(error)"
        }
    }

    init(
        monitor: SystemMonitor, interval: Duration,
        processMonitor: ProcessMonitor? = nil, processInterval: Duration = .seconds(2)
    ) {
        self.monitor = monitor
        self.interval = interval
        self.processMonitor = processMonitor
        self.processInterval = processInterval
    }

    deinit { worker?.cancel() }

    public var latest: CapturedSnapshot? { frames.last }

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

        worker = Task { [weak self] in
            defer {
                if let self, self.generation == run { self.worker = nil }
            }
            await monitor.reset()
            await processMonitor?.reset()
            var nextProcessSample = ContinuousClock.now
            while !Task.isCancelled {
                do {
                    _ = try await monitor.sample()
                    let history = await monitor.history()
                    var processes: CapturedProcesses?
                    if let processMonitor, ContinuousClock.now >= nextProcessSample {
                        processes = try await processMonitor.sample()
                        nextProcessSample = ContinuousClock.now.advanced(by: processInterval)
                    }
                    guard let self, self.generation == run, !Task.isCancelled else { return }
                    self.liveFrames = history
                    if let processes { self.liveProcesses = processes }
                    if self.displayMode == .live {
                        self.frames = history
                        if let processes { self.processSnapshot = processes }
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
    }

    public func reading(for metric: DashboardMetric) -> DashboardReading? {
        guard let latest else { return nil }
        switch metric {
        case .cpu: return latest.cpuPercentOfMachine
        case .memory: return latest.memoryUsedBytes
        }
    }

    public func points(for metric: DashboardMetric) -> [DashboardPoint] {
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
}
