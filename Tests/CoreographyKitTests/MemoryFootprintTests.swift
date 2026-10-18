import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class MemoryFootprintTests: XCTestCase {
    func testCompositionSubtractsCachedPagesBeforeConvertingUnits() throws {
        let pages = MemoryPages(
            active: 100, inactive: 50, speculative: 10,
            wired: 20, compressed: 30, purgeable: 5,
            fileBacked: 25, pageSizeBytes: 16_384
        )
        XCTAssertEqual(
            try MemoryFootprint.usedBytes(from: pages, physicalBytes: 4_194_304),
            2_949_120
        )
    }

    func testInconsistentAndOverflowingCountersAreErrors() {
        let invalid = MemoryPages(
            active: 0, inactive: 0, speculative: 0,
            wired: 0, compressed: 0, purgeable: 1,
            fileBacked: 0, pageSizeBytes: 4096
        )
        XCTAssertThrowsError(try MemoryFootprint.usedBytes(from: invalid, physicalBytes: 4096))

        let overflow = MemoryPages(
            active: .max, inactive: 1, speculative: 0,
            wired: 0, compressed: 0, purgeable: 0,
            fileBacked: 0, pageSizeBytes: 4096
        )
        XCTAssertThrowsError(try MemoryFootprint.usedBytes(from: overflow, physicalBytes: .max))
    }
}
