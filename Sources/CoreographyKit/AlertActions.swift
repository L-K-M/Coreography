import Foundation
import CoreographyDrivers

/// The startup volume's free share, for the low-disk alert.
public struct StartupVolumeMonitor: Sendable {
    private let driver: any VolumeCapacityReading

    public init() { self.init(driver: VolumeCapacityDriver()) }

    init(driver: any VolumeCapacityReading) { self.driver = driver }

    /// Available bytes over total, 0...1; nil when it cannot be read.
    public func freeFraction() async -> Double? {
        guard case .success(let capacity) = await driver.startupVolume(), capacity.totalBytes > 0 else { return nil }
        return min(max(Double(capacity.availableBytes) / Double(capacity.totalBytes), 0), 1)
    }
}

/// Why a Shortcut did not run to completion.
public enum ShortcutFailure: Error, Equatable, Sendable {
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
