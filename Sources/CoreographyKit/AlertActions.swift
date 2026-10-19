import Foundation
import CoreographyDrivers

/// The startup volume's free share, for the low-disk alert.
public struct VolumeMonitor: Sendable {
    private let driver: any VolumeCapacityReading

    public init() { self.init(driver: VolumeCapacityDriver()) }

    init(driver: any VolumeCapacityReading) { self.driver = driver }

    /// The startup volume's available bytes over total, 0...1; nil when it cannot be read.
    public func freeFraction() async -> Double? {
        guard case .success(let capacity) = await driver.startupVolume(), capacity.totalBytes > 0 else { return nil }
        return min(max(Double(capacity.availableBytes) / Double(capacity.totalBytes), 0), 1)
    }

    /// Visible volumes, startup first, then internal, external and network, by name.
    public func volumes() async -> VolumeList {
        switch await driver.mountedVolumes() {
        case .failure(.unsupportedPlatform): return VolumeList(volumes: [], problem: "Volumes need macOS")
        case .failure(.unavailable(let reason)): return VolumeList(volumes: [], problem: reason)
        case .success(let raw):
            let order: [RawVolumeKind] = [.internal, .external, .network]
            let volumes = raw.filter { $0.capacity.totalBytes > 0 }.map(VolumeCapacity.init).sorted { lhs, rhs in
                if lhs.isStartup != rhs.isStartup { return lhs.isStartup }
                let left = order.firstIndex(of: lhs.kind) ?? order.count
                let right = order.firstIndex(of: rhs.kind) ?? order.count
                if left != right { return left < right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return VolumeList(volumes: volumes, problem: nil)
        }
    }
}

public typealias VolumeKind = RawVolumeKind

/// One volume's size and space available for important use.
public struct VolumeCapacity: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let kind: VolumeKind
    public let isStartup: Bool
    public let totalBytes: Int64
    public let availableBytes: Int64

    init(_ raw: RawVolume) {
        path = raw.path
        name = raw.name
        kind = raw.kind
        isStartup = raw.isStartup
        totalBytes = raw.capacity.totalBytes
        availableBytes = raw.capacity.availableBytes
    }

    /// Used share, 0...1.
    public var usedFraction: Double { min(max(1 - Double(availableBytes) / Double(totalBytes), 0), 1) }
}

public struct VolumeList: Codable, Equatable, Sendable {
    public let volumes: [VolumeCapacity]
    /// Why nothing could be listed, when nothing could.
    public let problem: String?
}

/// Why a Shortcut did not run to completion.
public enum ShortcutFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidName
    case unavailable(String)
    case failed(Int32)
    case timedOut

    public var description: String {
        switch self {
        case .invalidName: "the name is not a Shortcut name"
        case .unavailable(let reason): reason
        case .failed(let status): "it exited with status \(status)"
        case .timedOut: "it ran past its 60-second limit and was stopped"
        }
    }
}

/// Lists and runs the person's own Shortcuts (plan: alert actions).
public struct ShortcutLauncher: Sendable {
    private let runner: any ShortcutRunning

    public init() { self.init(runner: ShortcutRunner()) }

    init(runner: any ShortcutRunning) { self.runner = runner }

    public func list() async -> Result<[String], ShortcutFailure> {
        await runner.list().mapError(Self.failure)
    }

    public func run(_ name: String) async -> Result<Void, ShortcutFailure> {
        await runner.run(name).mapError(Self.failure)
    }

    private static func failure(_ error: ShortcutError) -> ShortcutFailure {
        switch error {
        case .invalidName: .invalidName
        case .unavailable(let reason): .unavailable(reason)
        case .failed(let status): .failed(status)
        case .timedOut: .timedOut
        }
    }
}
