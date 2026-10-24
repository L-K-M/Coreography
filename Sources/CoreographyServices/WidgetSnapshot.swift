import Foundation
import CoreographyKit

/// A short, on-demand sample. Widgets need no running app or persistent collector.
public struct WidgetSnapshot: Sendable {
    public let host: CapturedSnapshot
    public let network: CapturedNetwork

    public var sampledAt: Date { max(host.stamp.wallTime, network.stamp.wallTime) }

    /// Keep the primary interface's scope, rather than double-counting tunnels.
    public var primaryInterface: CapturedInterface? {
        network.interfaces.first { $0.id == network.primaryInterface }
    }

    public var memoryFraction: Double? {
        let capacity = Double(host.inventory.physicalMemoryBytes)
        guard capacity > 0, let used = host.memoryUsedBytes.numericValue,
              used >= 0, used <= capacity else { return nil }
        return used / capacity
    }
}

public struct WidgetSampler: Sendable {
    private let host: SystemMonitor
    private let network: NetworkMonitor
    private let waitForInterval: @Sendable () async throws -> Void

    public init() throws {
        try self.init(host: SystemMonitor(), network: NetworkMonitor()) {
            try await Task.sleep(for: .seconds(1))
        }
    }

    init(
        host: SystemMonitor, network: NetworkMonitor,
        waitForInterval: @escaping @Sendable () async throws -> Void
    ) {
        self.host = host
        self.network = network
        self.waitForInterval = waitForInterval
    }

    public func sample() async throws -> WidgetSnapshot {
        // Establish fresh baselines on every refresh; suspended time is never a rate.
        await host.reset()
        await network.reset()
        async let hostBaseline = host.sample()
        async let networkBaseline = network.sample()
        _ = try await (hostBaseline, networkBaseline)
        try await waitForInterval()

        async let hostSample = host.sample()
        async let networkSample = network.sample()
        return try await WidgetSnapshot(host: hostSample, network: networkSample)
    }
}
