import Foundation
import CoreographyDrivers

/// Who runs a startup item and when; declared in listing order, the
/// user's own first.
public enum StartupItemKind: String, Codable, CaseIterable, Sendable {
    case userAgent, agent, daemon, systemAgent, systemDaemon
}

public enum StartupEnabledState: String, Codable, Sendable {
    case enabled, disabled
    /// launchd's overrides could not be read, so the plist's own flag may be stale.
    case unconfirmed
}

/// One launchd job that can start without being opened.
public struct StartupItem: Identifiable, Codable, Sendable {
    public var id: String { plistPath }
    public let label: String
    public let kind: StartupItemKind
    public let plistPath: String
    public let program: String?
    public let runsAtLoad: Bool
    public let keepsAlive: Bool
    public let state: StartupEnabledState
    /// Apple's own: in the sealed system folders, or signed by Apple.
    public let isApple: Bool
}

public struct StartupInventory: Sendable {
    public let takenAt: Date
    public let items: [StartupItem]
    public let unreadableDefinitions: Int
    /// Why enabled states are unconfirmed, when they are.
    public let stateProblem: String?
    /// Login and background items need the helper (`sfltool dumpbtm` runs as root).
    public static let loginItemsUnavailable = "Login and background items need the helper"
}

/// Reads startup items on request; definitions change rarely, so nothing polls.
public struct StartupProvider: Sendable {
    private let driver: any LaunchJobReading

    public init() { self.init(driver: LaunchJobDriver()) }

    init(driver: any LaunchJobReading) { self.driver = driver }

    public func load(at time: Date = Date()) async -> StartupInventory {
        let raw = await driver.read()
        let items = raw.jobs.map { job in
            StartupItem(
                label: job.label, kind: Self.kind(job.domain), plistPath: job.plistPath, program: job.program,
                runsAtLoad: job.runAtLoad, keepsAlive: job.keepAlive,
                state: Self.state(job, overrides: raw.overrides, readable: raw.overridesProblem == nil),
                isApple: job.domain == .systemAgents || job.domain == .systemDaemons || job.signature == .apple
            )
        }
        .sorted { (Self.order($0.kind), $0.label) < (Self.order($1.kind), $1.label) }
        return StartupInventory(
            takenAt: time, items: items, unreadableDefinitions: raw.unreadable, stateProblem: raw.overridesProblem
        )
    }

    private static func order(_ kind: StartupItemKind) -> Int {
        StartupItemKind.allCases.firstIndex(of: kind) ?? StartupItemKind.allCases.count
    }

    private static func kind(_ domain: LaunchDomain) -> StartupItemKind {
        switch domain {
        case .userAgents: .userAgent
        case .agents: .agent
        case .daemons: .daemon
        case .systemAgents: .systemAgent
        case .systemDaemons: .systemDaemon
        }
    }

    /// launchd's override wins over the plist's own Disabled key.
    private static func state(_ job: RawLaunchJob, overrides: [String: Bool], readable: Bool) -> StartupEnabledState {
        if let disabled = overrides[job.label] { return disabled ? .disabled : .enabled }
        guard readable else { return .unconfirmed }
        return job.disabledInPlist ? .disabled : .enabled
    }
}
