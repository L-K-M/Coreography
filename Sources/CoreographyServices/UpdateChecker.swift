import Foundation
import Observation
import CoreographyKit

/// What the last update check found.
public enum UpdateStatus: Equatable, Sendable {
    case notChecked
    case checking
    case upToDate
    case available(PublishedRelease)
    case noRelease
    case failed(String)
    /// A build without a release version has nothing to compare.
    case unversioned
}

/// Notify-only updates: Coreography asks GitHub for the newest release and
/// links to it; downloading and installing stay with the person.
///
/// ```text
/// launch, then hourly ──due (a day since the last answer)?──> ReleaseFeed
///                                                             ├─> newer: status + one notification per version
///                                                             └─> failed: retried next hour
/// ```
@MainActor
@Observable
public final class UpdateChecker {
    static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let pollInterval: Duration = .seconds(60 * 60)
    private static let automaticKey = "updateCheckAutomatic"
    private static let announcedKey = "updateAnnouncedVersion"

    private enum Trigger { case automatic, manual }

    public private(set) var status: UpdateStatus = .notChecked
    /// When GitHub last answered; failed checks leave it unchanged.
    public private(set) var lastChecked: Date?
    public private(set) var isAutomatic: Bool
    public let currentVersion: String

    @ObservationIgnored private let version: AppVersion?
    @ObservationIgnored private let feed: ReleaseFeed
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let announce: @Sendable (PublishedRelease) async -> Void
    @ObservationIgnored private var loop: Task<Void, Never>?

    public convenience init(version: String) {
        let delivery = AlertDelivery()
        self.init(version: version, feed: ReleaseFeed(), defaults: .standard, now: Date.init) { release in
            await delivery.deliver(
                ruleID: "update", title: "Coreography \(release.version) is available",
                body: "Open Settings > Updates to view the release."
            )
        }
    }

    init(
        version: String, feed: ReleaseFeed, defaults: UserDefaults, now: @escaping @Sendable () -> Date,
        announce: @escaping @Sendable (PublishedRelease) async -> Void
    ) {
        currentVersion = version
        self.version = AppVersion(version)
        self.feed = feed
        self.defaults = defaults
        self.now = now
        self.announce = announce
        isAutomatic = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
    }

    /// Checks at launch and then whenever a day has passed, while automatic checks are on.
    public func start() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                if isAutomatic, isDue { await check(.automatic) }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    public func setAutomatic(_ automatic: Bool) {
        guard automatic != isAutomatic else { return }
        isAutomatic = automatic
        defaults.set(automatic, forKey: Self.automaticKey)
        if automatic, isDue { Task { await check(.automatic) } }
    }

    /// A check asked for in Settings; it never posts a notification.
    public func checkNow() async { await check(.manual) }

    private var isDue: Bool {
        guard let lastChecked else { return true }
        return now().timeIntervalSince(lastChecked) >= Self.checkInterval
    }

    private func check(_ trigger: Trigger) async {
        guard status != .checking else { return }
        guard let version else {
            status = .unversioned
            return
        }

        status = .checking
        let release: PublishedRelease
        do {
            release = try await feed.latest()
        } catch .noRelease {
            lastChecked = now()
            status = .noRelease
            return
        } catch {
            status = .failed(Self.message(error))
            return
        }

        lastChecked = now()
        guard release.version > version else {
            status = .upToDate
            return
        }
        status = .available(release)

        // One notification per version; a manual check shows it in Settings instead.
        guard defaults.string(forKey: Self.announcedKey) != release.version.description else { return }
        defaults.set(release.version.description, forKey: Self.announcedKey)
        if trigger == .automatic { await announce(release) }
    }

    private static func message(_ failure: ReleaseFeedFailure) -> String {
        switch failure {
        case .noRelease: "No release is published yet."
        case .rateLimited: "GitHub is limiting requests; try again later."
        case .server(let status): "GitHub answered with status \(status)."
        case .malformedResponse: "GitHub returned a release Coreography could not read."
        case .unreachable(let detail): "GitHub could not be reached: \(detail)"
        }
    }
}
