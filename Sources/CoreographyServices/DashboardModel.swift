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

    @ObservationIgnored private let monitor: SystemMonitor?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var liveFrames: [CapturedSnapshot] = []

    public init() {
        interval = .seconds(1)
        do {
            monitor = try SystemMonitor()
        } catch {
            monitor = nil
            collectionError = "Cannot initialize monitoring: \(error)"
        }
    }

    init(monitor: SystemMonitor, interval: Duration) {
        self.monitor = monitor
        self.interval = interval
    }

    deinit { worker?.cancel() }

    public var latest: CapturedSnapshot? { frames.last }

    public func start() {
        guard worker == nil, let monitor else { return }
        let run = UUID()
        generation = run
        collectionError = nil

        worker = Task { [weak self] in
            defer {
                if let self, self.generation == run { self.worker = nil }
            }
            await monitor.reset()
            while !Task.isCancelled {
                do {
                    _ = try await monitor.sample()
                    let history = await monitor.history()
                    guard let self, self.generation == run, !Task.isCancelled else { return }
                    self.liveFrames = history
                    if self.displayMode == .live { self.frames = history }
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
