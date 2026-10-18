import Foundation
import CoreographyDrivers

/// Why a provider exchange failed, in terms a person can act on.
public enum AssistantProviderFailure: Error, Equatable, Sendable {
    case noKey
    case invalidKey
    case rateLimited(retryAfter: String?)
    case overloaded
    case badRequest(String)
    case server(status: Int, message: String)
    case malformedResponse
    case credentials(String)
}

/// One model provider: the Keychain-held key and the Messages API exchange.
/// The key is read per request and sent only to the provider.
public actor AssistantProvider {
    private let credentials: any CredentialStoring
    private let transport: any ModelTransport

    public init() {
        self.init(credentials: KeychainCredentialStore(), transport: AnthropicMessagesDriver())
    }

    init(credentials: any CredentialStoring, transport: any ModelTransport) {
        self.credentials = credentials
        self.transport = transport
    }

    public func hasKey() -> Bool { (try? credentials.read()).flatMap { $0 }?.isEmpty == false }

    public func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AssistantProviderFailure.noKey }
        do { try credentials.save(trimmed) } catch { throw AssistantProviderFailure.credentials("\(error)") }
    }

    public func removeKey() throws {
        do { try credentials.delete() } catch { throw AssistantProviderFailure.credentials("\(error)") }
    }

    /// POST one request body; returns the body of a successful reply.
    public func send(_ body: Data, betas: [String]) async throws -> Data {
        let key: String
        do {
            guard let stored = try credentials.read(), !stored.isEmpty else { throw AssistantProviderFailure.noKey }
            key = stored
        } catch let failure as AssistantProviderFailure {
            throw failure
        } catch {
            throw AssistantProviderFailure.credentials("\(error)")
        }

        let response = try await transport.post(body, apiKey: key, betas: betas)
        let json = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        let detail = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "no detail"
        switch response.status {
        case 200:
            guard json != nil else { throw AssistantProviderFailure.malformedResponse }
            return response.body
        case 401, 403: throw AssistantProviderFailure.invalidKey
        case 429: throw AssistantProviderFailure.rateLimited(retryAfter: response.retryAfter)
        case 529: throw AssistantProviderFailure.overloaded
        case 400..<500: throw AssistantProviderFailure.badRequest(detail)
        default: throw AssistantProviderFailure.server(status: response.status, message: detail)
        }
    }
}
