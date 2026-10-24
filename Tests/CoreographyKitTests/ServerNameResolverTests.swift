import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class ServerNameResolverTests: XCTestCase {
    func testAnswersCacheAndUnanswerablePeersAreNotReasked() async {
        let driver = StubResolver(names: ["17.0.0.1": "apple.com", "1.1.1.1": "one.one.one.one"])
        let resolver = ServerNameResolver(driver: driver)

        let first = await resolver.resolve(["17.0.0.1", "10.0.0.9"])
        XCTAssertEqual(first, ["17.0.0.1": "apple.com"])

        let second = await resolver.resolve(["17.0.0.1", "10.0.0.9", "1.1.1.1"])
        XCTAssertEqual(second["1.1.1.1"], "one.one.one.one")
        let lookups = await driver.lookups
        XCTAssertEqual(lookups, 3, "answered and unanswerable peers are each asked once")
    }

    func testBatchesAreCapped() async {
        let driver = StubResolver(names: [:])
        let resolver = ServerNameResolver(driver: driver)
        _ = await resolver.resolve((1...200).map { "10.0.\($0 / 256).\($0 % 256)" })
        let lookups = await driver.lookups
        XCTAssertEqual(lookups, ServerNameResolver.batchLimit)
    }
}

private actor StubResolver: ServerNameResolving {
    private let names: [String: String]
    private(set) var lookups = 0

    init(names: [String: String]) { self.names = names }

    func lookup(_ address: String) -> String? {
        lookups += 1
        return names[address]
    }
}
