import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class AccountDirectoryTests: XCTestCase {
    func testNamesAreReadOnceAndMissingAccountsStayUnnamed() {
        let reader = Reader(["0": "root", "501": "alice"])
        let directory = AccountDirectory(reader: reader)
        XCTAssertEqual(directory.names(for: [0, 501, 777]), [0: "root", 501: "alice"])
        XCTAssertEqual(directory.names(for: [501, 777]), [501: "alice"])
        XCTAssertEqual(reader.lookups, 3, "each UID is read once, found or not")
    }

    /// A directory service that fails once must be asked again, not remembered as "no account".
    func testAFailedLookupIsTriedAgain() {
        let reader = Reader(["501": "alice"], failuresFirst: 1)
        let directory = AccountDirectory(reader: reader)
        XCTAssertEqual(directory.names(for: [501]), [:])
        XCTAssertEqual(directory.names(for: [501]), [501: "alice"])
    }

    func testTheRealDirectoryNamesRoot() {
        XCTAssertEqual(AccountDirectory().names(for: [0])[0], "root")
    }
}

private final class Reader: AccountNameReading, @unchecked Sendable {
    private let table: [String: String]
    private let lock = NSLock()
    private var count = 0
    private var failures: Int

    init(_ table: [String: String], failuresFirst: Int = 0) {
        self.table = table
        failures = failuresFirst
    }

    var lookups: Int { lock.withLock { count } }

    func name(of uid: UInt32) throws -> String? {
        try lock.withLock {
            count += 1
            if failures > 0 {
                failures -= 1
                throw AccountLookupError(code: 5)
            }
        }
        return table["\(uid)"]
    }
}
