import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One raw HTTP exchange with a model provider; parsing stays with the caller.
public struct ProviderResponse: Sendable {
    public let status: Int
    public let body: Data
    /// Seconds to wait, when the provider sent `retry-after`.
    public let retryAfter: String?

    public init(status: Int, body: Data, retryAfter: String?) {
        self.status = status
        self.body = body
        self.retryAfter = retryAfter
    }
}

public protocol ModelTransport: Sendable {
    func post(_ body: Data, apiKey: String, betas: [String]) async throws -> ProviderResponse
}

/// POSTs to the Anthropic Messages API. The key goes only in `x-api-key`,
/// never in logs or the URL; requests go straight to the provider.
public struct AnthropicMessagesDriver: ModelTransport {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"
    /// Generous for non-streaming tool turns; the caller can cancel sooner.
    private static let timeout: TimeInterval = 120

    public init() {}

    public func post(_ body: Data, apiKey: String, betas: [String]) async throws -> ProviderResponse {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty { request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return ProviderResponse(
            status: http?.statusCode ?? 0, body: data, retryAfter: http?.value(forHTTPHeaderField: "retry-after")
        )
    }
}

/// POSTs to an OpenAI-compatible `chat/completions` endpoint, such as
/// DeepSeek's. The key goes only in the Authorization header, to the base
/// URL the person configured; `betas` has no meaning there and is ignored.
public struct ChatCompletionsDriver: ModelTransport {
    private let endpoint: URL
    /// A short single-turn request; the caller can cancel sooner.
    private static let timeout: TimeInterval = 60

    public init(baseURL: URL) { endpoint = baseURL.appendingPathComponent("chat/completions") }

    public func post(_ body: Data, apiKey: String, betas: [String]) async throws -> ProviderResponse {
        var request = URLRequest(url: endpoint, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return ProviderResponse(
            status: http?.statusCode ?? 0, body: data, retryAfter: http?.value(forHTTPHeaderField: "retry-after")
        )
    }
}
