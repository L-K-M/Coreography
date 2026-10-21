import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One raw reply from the release feed; parsing stays with the caller.
public struct ReleaseFeedReply: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol ReleaseFeedFetching: Sendable {
    func fetchLatest() async throws -> ReleaseFeedReply
}

/// GETs the newest published release from the GitHub REST API. The
/// request carries no identifiers beyond what any HTTPS request does.
public struct GitHubReleaseDriver: ReleaseFeedFetching {
    /// `/releases/latest` skips drafts and prereleases.
    private static let endpoint = URL(string: "https://api.github.com/repos/L-K-M/Coreography/releases/latest")!
    private static let apiVersion = "2022-11-28"
    private static let timeout: TimeInterval = 30

    public init() {}

    public func fetchLatest() async throws -> ReleaseFeedReply {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "x-github-api-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return ReleaseFeedReply(status: http.statusCode, body: data)
    }
}
