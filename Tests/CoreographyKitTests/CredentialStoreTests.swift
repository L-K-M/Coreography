import Foundation
import XCTest
import CoreographyDrivers

final class CredentialStoreTests: XCTestCase {
    /// A second save replaces the first in place; reading returns the newest key.
    func testSavingAgainReplacesTheKeyInPlace() throws {
        #if os(macOS)
        let store = KeychainCredentialStore(service: "ch.lkmc.Coreography.tests.\(UUID().uuidString)", account: "test")
        defer { try? store.delete() }
        do {
            try store.save("first")
        } catch {
            throw XCTSkip("This runner's keychain refused a write (\(error)); the replacement path is unverified here")
        }
        try store.save("second")
        XCTAssertEqual(try store.read(), "second")
        try store.delete()
        XCTAssertNil(try store.read())
        #else
        throw XCTSkip("The Keychain needs macOS")
        #endif
    }
}
