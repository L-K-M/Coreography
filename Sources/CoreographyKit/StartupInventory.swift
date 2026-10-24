import Foundation
import CoreographyDrivers

/// Who runs a startup item and when; declared in listing order, the
/// user's own first.
public enum StartupItemKind: String, Codable, CaseIterable, Sendable {
    /// From the Background Task Management database: runs at login.
    case loginItem
    case userAgent, agent, daemon, systemAgent, systemDaemon
    /// A BTM registration that is neither a login item nor a launchd job:
    /// apps and developer records, still listed so nothing hides.
    case backgroundItem
}

public enum StartupEnabledState: String, Codable, Sendable {
    case enabled, disabled
    /// launchd's overrides could not be read, so the plist's own flag may be stale.
    case unconfirmed
}

/// One launchd job or background registration that can start without being opened.
public struct StartupItem: Identifiable, Codable, Sendable {
    public var id: String { plistPath }
    public let label: String
    public let kind: StartupItemKind
    /// The plist for a launchd job; the registering URL (or `btm:<uuid>`
    /// when a record has none) for a BTM item.
    public let plistPath: String
    public let program: String?
    public let runsAtLoad: Bool
    public let keepsAlive: Bool
    public let state: StartupEnabledState
    /// Apple's own: in the sealed system folders, or signed by Apple.
    public let isApple: Bool
    /// The user a BTM item runs for; nil for launchd items, whose owner the
    /// plist's folder already says.
    public let ownerUID: UInt?
}

public struct StartupInventory: Sendable {
    public let takenAt: Date
    public let items: [StartupItem]
    public let unreadableDefinitions: Int
    /// Why enabled states are unconfirmed, when they are.
    public let stateProblem: String?
    /// Why login and background items are missing; nil once the helper's
    /// `sfltool dumpbtm` arrives, whatever it held.
    public let loginItemsProblem: String?
    /// Login and background items need the helper (`sfltool dumpbtm` runs as root).
    public static let loginItemsUnavailable = "Login and background items need the helper"
}

/// Reads startup items on request; definitions change rarely, so nothing polls.
public struct StartupProvider: Sendable {
    private let driver: any LaunchJobReading
    /// The helper's `sfltool dumpbtm` text; nil or a failure leaves a note.
    private let backgroundDump: @Sendable () async -> Result<String, HelperReadFailure>?

    public init() {
        self.init(driver: LaunchJobDriver(), backgroundDump: { await PrivilegedHelper.shared.backgroundItems() })
    }

    init(
        driver: any LaunchJobReading,
        backgroundDump: @escaping @Sendable () async -> Result<String, HelperReadFailure>? = { nil }
    ) {
        self.driver = driver
        self.backgroundDump = backgroundDump
    }

    public func load(at time: Date = Date()) async -> StartupInventory {
        let raw = await driver.read()
        var items = raw.jobs.map { job in
            StartupItem(
                label: job.label, kind: Self.kind(job.domain), plistPath: job.plistPath, program: job.program,
                runsAtLoad: job.runAtLoad, keepsAlive: job.keepAlive,
                state: Self.state(job, overrides: raw.overrides, readable: raw.overridesProblem == nil),
                isApple: job.domain == .systemAgents || job.domain == .systemDaemons || job.signature == .apple,
                ownerUID: nil
            )
        }

        // Login and background items come from the helper's BTM dump; a
        // record already listed from its plist is skipped, which keeps
        // launchd's enabled state over the record's disposition.
        var loginItemsProblem: String? = StartupInventory.loginItemsUnavailable
        switch await backgroundDump() {
        case .success(let dump):
            loginItemsProblem = nil
            let listed = Set(items.map(\.plistPath))
            items += BackgroundItems.items(in: dump).filter { !listed.contains($0.plistPath) }
        case .failure(let error):
            loginItemsProblem = "Login and background items could not be read: \(error.reason)"
        case nil:
            break
        }

        items.sort { (Self.order($0.kind), $0.label) < (Self.order($1.kind), $1.label) }
        return StartupInventory(
            takenAt: time, items: items, unreadableDefinitions: raw.unreadable,
            stateProblem: raw.overridesProblem, loginItemsProblem: loginItemsProblem
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
    private static func state(
        _ job: RawLaunchJob, overrides: [LaunchOverrideDomain: [String: Bool]], readable: Bool
    ) -> StartupEnabledState {
        if let disabled = overrides[job.domain.overrides]?[job.label] { return disabled ? .disabled : .enabled }
        guard readable else { return .unconfirmed }
        return job.disabledInPlist ? .disabled : .enabled
    }
}
