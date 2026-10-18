import Foundation
import XCTest
import CoreographyDrivers
#if os(macOS)
import Security
#endif

final class CredentialStoreTests: XCTestCase {
    /// A second save replaces the first in place; reading returns the newest key.
    func testSavingAgainReplacesTheKeyInPlace() throws {
        #if os(macOS)
        let service = "ch.lkmc.Coreography.tests.\(UUID().uuidString)"
        let store = KeychainCredentialStore(service: service, account: "test")
        defer { try? store.delete() }
        do {
            try store.save("first")
        } catch {
            throw XCTSkip("This runner's keychain refused a write (\(error)); the replacement path is unverified here")
        }
        try store.save("second")
        XCTAssertEqual(try store.read(), "second")
        // In place: still one item, not the old and the new side by side.
        let everyItem: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "test", kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var items: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(everyItem as CFDictionary, &items), errSecSuccess)
        XCTAssertEqual((items as? [Any])?.count, 1)
        try store.delete()
        XCTAssertNil(try store.read())
        #else
        throw XCTSkip("The Keychain needs macOS")
        #endif
    }
}
