import Foundation
import CoreographyDrivers

/// A release version: "0.2" or "0.2.1", with or without a leading "v".
/// Missing parts count as zero, so 0.2 == 0.2.0.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    private let parts: [Int]
    public let description: String

    /// Nil for anything else, such as "development" or "1.0-beta".
    public init?(_ text: String) {
        let bare = text.hasPrefix("v") ? String(text.dropFirst()) : text
        guard bare.wholeMatch(of: /\d+\.\d+(\.\d+)?/) != nil else { return nil }
        let parts = bare.split(separator: ".").compactMap { Int($0) }
        // A part too large for Int fails to parse.
        guard parts.count == bare.split(separator: ".").count else { return nil }
        self.parts = parts
        description = bare
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.padded == rhs.padded }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.padded.lexicographicallyPrecedes(rhs.padded) }

    private var padded: [Int] { parts + Array(repeating: 0, count: 3 - parts.count) }
}

/// The newest published release and the page that offers its download.
public struct PublishedRelease: Equatable, Sendable {
    public let version: AppVersion
    public let page: URL
}

public enum ReleaseFeedFailure: Error, Equatable, Sendable {
    /// Nothing is published yet.
    case noRelease
    case rateLimited
    case server(status: Int)
    case malformedResponse
    case unreachable(String)
}

/// Reads the newest release from GitHub. The reply is untrusted: only a
/// release page of this repository is accepted as the link to show.
public struct ReleaseFeed: Sendable {
    private static let pagePrefix = "https://github.com/L-K-M/Coreography/releases/"
    private let transport: any ReleaseFeedFetching

    public init() { self.init(transport: GitHubReleaseDriver()) }

    init(transport: any ReleaseFeedFetching) { self.transport = transport }

    public func latest() async throws(ReleaseFeedFailure) -> PublishedRelease {
        let reply: ReleaseFeedReply
        do { reply = try await transport.fetchLatest() } catch { throw .unreachable(error.localizedDescription) }

        switch reply.status {
        case 200: break
        case 404: throw .noRelease
        // GitHub answers an exhausted anonymous quota with 403 or 429.
        case 403, 429: throw .rateLimited
        default: throw .server(status: reply.status)
        }

        struct Release: Decodable { let tag_name: String; let html_url: String }
        guard let release = try? JSONDecoder().decode(Release.self, from: reply.body),
              let version = AppVersion(release.tag_name),
              release.html_url.hasPrefix(Self.pagePrefix),
              let page = URL(string: release.html_url) else { throw .malformedResponse }
        return PublishedRelease(version: version, page: page)
    }
}
