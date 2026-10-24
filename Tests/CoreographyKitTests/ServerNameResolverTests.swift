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

    func testDepartedPeersAreRemovedAndMayBeResolvedAgain() async {
        let driver = StubResolver(names: ["17.0.0.1": "apple.com", "1.1.1.1": "one.one.one.one"])
        let resolver = ServerNameResolver(driver: driver)
        _ = await resolver.resolve(["17.0.0.1"])
        let second = await resolver.resolve(["1.1.1.1"])
        XCTAssertEqual(second, ["1.1.1.1": "one.one.one.one"])
        _ = await resolver.resolve(["17.0.0.1"])
        let count = await driver.lookups
        XCTAssertEqual(count, 3, "departed peers cannot keep stale PTR answers forever")
    }

    func testBlockingLookupsHaveABoundedFanout() async {
        let driver = SlowResolver()
        let resolver = ServerNameResolver(driver: driver)
        _ = await resolver.resolve((1...ServerNameResolver.batchLimit).map { "10.0.0.\($0)" })
        let peak = await driver.peak
        XCTAssertLessThanOrEqual(peak, 4, "a table must not start dozens of simultaneous DNS calls")
    }
}

private actor SlowResolver: ServerNameResolving {
    private var active = 0
    private(set) var peak = 0

    func lookup(_ address: String) async -> String? {
        active += 1
        peak = max(peak, active)
        try? await Task.sleep(for: .milliseconds(20))
        active -= 1
        return nil
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
