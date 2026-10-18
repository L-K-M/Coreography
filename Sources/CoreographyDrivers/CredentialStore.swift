import Foundation
#if os(macOS)
import Security
#endif

public enum CredentialStoreError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case keychain(status: Int32)
}

public protocol CredentialStoring: Sendable {
    func read() throws -> String?
    func save(_ secret: String) throws
    func delete() throws
}

/// The provider key lives only in the login Keychain: never in preferences,
/// history, logs, exports or MCP results (plan: in-app assistant credentials).
public struct KeychainCredentialStore: CredentialStoring {
    private let service: String
    private let account: String

    public init(service: String = "ch.lkmc.Coreography.provider", account: String = "anthropic") {
        self.service = service
        self.account = account
    }

    public func read() throws -> String? {
        #if os(macOS)
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw CredentialStoreError.keychain(status: status) }
        return String(decoding: data, as: UTF8.self)
        #else
        throw CredentialStoreError.unsupportedPlatform
        #endif
    }

    public func save(_ secret: String) throws {
        #if os(macOS)
        try delete()
        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(secret.utf8)
        // Readable only while this Mac is unlocked, and never synced to other devices.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status) }
        #else
        throw CredentialStoreError.unsupportedPlatform
        #endif
    }

    public func delete() throws {
        #if os(macOS)
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status: status)
        }
        #else
        throw CredentialStoreError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    #endif
}
