import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUpWithError() throws {
        suite = "UpdateCheckerTests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testANewerReleaseIsAnnouncedOncePerVersion() async {
        let announced = Announced()
        let checker = makeChecker(version: "0.1.0", feed: .tag("v0.2.0"), announced: announced)

        checker.start()
        // The flag is written after the notification, so it marks a finished check.
        await waitUntil { self.defaults.string(forKey: "updateAnnouncedVersion") != nil }
        guard case .available(let release) = checker.status else { return XCTFail("\(checker.status)") }
        XCTAssertEqual(release.version, AppVersion("0.2.0"))
        let first = await announced.versions
        XCTAssertEqual(first, ["0.2.0"])

        // A relaunch finds the same release and stays quiet.
        let relaunched = makeChecker(version: "0.1.0", feed: .tag("v0.2.0"), announced: announced)
        relaunched.start()
        await waitUntil { relaunched.status != .notChecked && relaunched.status != .checking }
        XCTAssertNotNil(relaunched.lastChecked, "an already announced release still records the check")
        let second = await announced.versions
        XCTAssertEqual(second, ["0.2.0"])
    }

    @MainActor
    func testAnUndeliveredNotificationIsTriedAgain() async {
        let denied = Announced(delivers: false)
        makeChecker(version: "0.1.0", feed: .tag("v0.2.0"), announced: denied).start()
        await waitUntil { await !denied.versions.isEmpty }
        XCTAssertNil(defaults.string(forKey: "updateAnnouncedVersion"), "nothing was shown, so nothing is spent")

        let allowed = Announced()
        makeChecker(version: "0.1.0", feed: .tag("v0.2.0"), announced: allowed).start()
        await waitUntil { self.defaults.string(forKey: "updateAnnouncedVersion") != nil }
        let versions = await allowed.versions
        XCTAssertEqual(versions, ["0.2.0"])
    }

    @MainActor
    func testAManualCheckShowsTheReleaseWithoutANotification() async {
        let announced = Announced()
        let checker = makeChecker(version: "0.1.0", feed: .tag("v0.2.0"), announced: announced)

        await checker.checkNow()
        XCTAssertEqual(checker.status, .available(PublishedRelease(
            version: AppVersion("0.2.0")!, page: URL(string: "https://github.com/L-K-M/Coreography/releases/tag/v0.2.0")!
        )))
        let versions = await announced.versions
        XCTAssertEqual(versions, [])
    }

    @MainActor
    func testStatusCoversEveryAnswer() async {
        let current = makeChecker(version: "0.2", feed: .tag("v0.2.0"))
        await current.checkNow()
        XCTAssertEqual(current.status, .upToDate)

        let older = makeChecker(version: "0.3.0", feed: .tag("v0.2.0"))
        await older.checkNow()
        XCTAssertEqual(older.status, .upToDate, "a newer local build is not offered an older release")

        let none = makeChecker(version: "0.1.0", feed: .status(404))
        await none.checkNow()
        XCTAssertEqual(none.status, .noRelease)
        XCTAssertNotNil(none.lastChecked, "no release is still an answer")

        let failing = makeChecker(version: "0.1.0", feed: .status(503))
        await failing.checkNow()
        XCTAssertEqual(failing.status, .failed("GitHub answered with status 503."))
        XCTAssertNil(failing.lastChecked, "a failure is retried at the next poll")

        let development = makeChecker(version: "development", feed: .tag("v0.2.0"))
        await development.checkNow()
        XCTAssertEqual(development.status, .unversioned)
    }

    @MainActor
    func testTurningAutomaticChecksOffIsRemembered() {
        let checker = makeChecker(version: "0.1.0", feed: .tag("v0.2.0"))
        XCTAssertTrue(checker.isAutomatic, "on by default")
        checker.setAutomatic(false)
        XCTAssertFalse(makeChecker(version: "0.1.0", feed: .tag("v0.2.0")).isAutomatic)
    }

    @MainActor
    func testAutomaticChecksOffMakeNoRequest() async throws {
        let feed = Feed.tag("v0.2.0")
        let checker = makeChecker(version: "0.1.0", feed: feed)
        checker.setAutomatic(false)
        checker.start()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(checker.status, .notChecked)
        let requests = await feed.counter.count
        XCTAssertEqual(requests, 0)
    }

    @MainActor
    private func makeChecker(version: String, feed: Feed, announced: Announced = Announced()) -> UpdateChecker {
        UpdateChecker(version: version, feed: ReleaseFeed(transport: feed), defaults: defaults, now: Date.init) {
            await announced.add($0.version.description)
            return announced.delivers
        }
    }

    @MainActor
    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out waiting for the check")
    }
}

private actor Announced {
    /// False plays notifications being denied.
    nonisolated let delivers: Bool
    private(set) var versions: [String] = []

    init(delivers: Bool = true) { self.delivers = delivers }

    func add(_ version: String) { versions.append(version) }
}

private actor Counter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private struct Feed: ReleaseFeedFetching {
    let reply: ReleaseFeedReply
    let counter = Counter()

    static func tag(_ tag: String) -> Feed {
        let body = #"{"tag_name": "\#(tag)", "html_url": "https://github.com/L-K-M/Coreography/releases/tag/\#(tag)"}"#
        return Feed(reply: ReleaseFeedReply(status: 200, body: Data(body.utf8)))
    }

    static func status(_ status: Int) -> Feed { Feed(reply: ReleaseFeedReply(status: status, body: Data())) }

    func fetchLatest() async throws -> ReleaseFeedReply {
        await counter.increment()
        return reply
    }
}
