import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class ReleaseFeedTests: XCTestCase {
    func testVersionsParseReleaseTagsOnly() {
        XCTAssertEqual(AppVersion("v0.2.1")?.description, "0.2.1")
        XCTAssertEqual(AppVersion("0.2")?.description, "0.2")
        for text in ["development", "1", "1.0-beta", "1.2.3.4", "+1.0", "v", "1..2", "99999999999999999999.0"] {
            XCTAssertNil(AppVersion(text), text)
        }
    }

    func testVersionsCompareNumericallyWithMissingPartsAsZero() throws {
        let order = try ["0.1", "0.1.1", "0.2.0", "0.10.0", "1.0"].map { try XCTUnwrap(AppVersion($0)) }
        XCTAssertEqual(order, order.sorted())
        XCTAssertEqual(AppVersion("0.2"), AppVersion("v0.2.0"))
        XCTAssertFalse(try XCTUnwrap(AppVersion("0.2.0")) > XCTUnwrap(AppVersion("0.2")))
    }

    func testLatestReadsTheReleaseTagAndPage() async throws {
        let feed = ReleaseFeed(transport: Reply(status: 200, release(tag: "v0.3.0")))
        let release = try await feed.latest()
        XCTAssertEqual(release.version, AppVersion("0.3.0"))
        XCTAssertEqual(release.page.absoluteString, "https://github.com/L-K-M/Coreography/releases/tag/v0.3.0")
    }

    func testLatestMapsFailures() async {
        let cases: [(ReleaseFeedFetching, ReleaseFeedFailure)] = [
            (Reply(status: 404, Data()), .noRelease),
            (Reply(status: 403, Data()), .rateLimited),
            (Reply(status: 429, Data()), .rateLimited),
            (Reply(status: 502, Data()), .server(status: 502)),
            (Reply(status: 200, Data("{}".utf8)), .malformedResponse),
            (Reply(status: 200, release(tag: "nightly")), .malformedResponse),
            (Unreachable(), .unreachable("offline"))
        ]
        for (transport, expected) in cases {
            do {
                _ = try await ReleaseFeed(transport: transport).latest()
                XCTFail("\(expected) expected")
            } catch {
                XCTAssertEqual(error, expected)
            }
        }
    }

    func testLatestRejectsALinkOutsideThisRepository() async {
        let elsewhere = release(tag: "v9.0.0", page: "https://example.com/L-K-M/Coreography/releases/tag/v9.0.0")
        do {
            _ = try await ReleaseFeed(transport: Reply(status: 200, elsewhere)).latest()
            XCTFail("a foreign link must not be shown")
        } catch {
            XCTAssertEqual(error, .malformedResponse)
        }
    }

    private func release(tag: String, page: String? = nil) -> Data {
        let page = page ?? "https://github.com/L-K-M/Coreography/releases/tag/\(tag)"
        return Data(#"{"tag_name": "\#(tag)", "html_url": "\#(page)", "draft": false}"#.utf8)
    }
}

private struct Reply: ReleaseFeedFetching {
    let reply: ReleaseFeedReply
    init(status: Int, _ body: Data) { reply = ReleaseFeedReply(status: status, body: body) }
    func fetchLatest() async throws -> ReleaseFeedReply { reply }
}

private struct Unreachable: ReleaseFeedFetching {
    struct Offline: LocalizedError { var errorDescription: String? { "offline" } }
    func fetchLatest() async throws -> ReleaseFeedReply { throw Offline() }
}
