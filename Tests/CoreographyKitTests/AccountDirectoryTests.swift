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

    func testTheRealDirectoryNamesRoot() {
        XCTAssertEqual(AccountDirectory().names(for: [0])[0], "root")
    }
}

private final class Reader: AccountNameReading, @unchecked Sendable {
    private let table: [String: String]
    private let lock = NSLock()
    private var count = 0

    init(_ table: [String: String]) { self.table = table }

    var lookups: Int { lock.withLock { count } }

    func name(of uid: UInt32) -> String? {
        lock.withLock { count += 1 }
        return table["\(uid)"]
    }
}
