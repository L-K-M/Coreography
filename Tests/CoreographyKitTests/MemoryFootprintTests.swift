import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class MemoryFootprintTests: XCTestCase {
    func testCompositionSubtractsCachedPagesBeforeConvertingUnits() throws {
        let pages = MemoryPages(
            active: 100, inactive: 50, speculative: 10,
            wired: 20, compressed: 30, compressorContents: 90, purgeable: 5,
            fileBacked: 25, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 16_384
        )
        XCTAssertEqual(
            try MemoryFootprint.usedBytes(from: pages, physicalBytes: 4_194_304),
            2_949_120
        )
    }

    func testAppAndCachedMemoryMatchActivityMonitorCategories() throws {
        let pages = MemoryPages(
            active: 100, inactive: 50, speculative: 10,
            wired: 20, compressed: 30, compressorContents: 90, purgeable: 5,
            fileBacked: 25, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 16_384
        )
        // used 180 pages = app 130 + wired 20 + compressed 30; cached 5 + 25.
        XCTAssertEqual(try MemoryFootprint.appBytes(from: pages, physicalBytes: 4_194_304), 130 * 16_384)
        XCTAssertEqual(try MemoryFootprint.cachedBytes(from: pages, physicalBytes: 4_194_304), 30 * 16_384)
    }

    func testAppMemoryBelowZeroIsInconsistent() {
        // 10 resident pages minus 1 file-backed page cannot hold 10 wired pages.
        let pages = MemoryPages(
            active: 0, inactive: 0, speculative: 0,
            wired: 10, compressed: 0, compressorContents: 0, purgeable: 0,
            fileBacked: 1, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
        )
        XCTAssertNoThrow(try MemoryFootprint.usedBytes(from: pages, physicalBytes: 1_048_576))
        XCTAssertThrowsError(try MemoryFootprint.appBytes(from: pages, physicalBytes: 1_048_576))
    }

    func testInconsistentAndOverflowingCountersAreErrors() {
        let invalid = MemoryPages(
            active: 0, inactive: 0, speculative: 0,
            wired: 0, compressed: 0, compressorContents: 0, purgeable: 1,
            fileBacked: 0, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
        )
        XCTAssertThrowsError(try MemoryFootprint.usedBytes(from: invalid, physicalBytes: 4096))

        let overflow = MemoryPages(
            active: .max, inactive: 1, speculative: 0,
            wired: 0, compressed: 0, compressorContents: 0, purgeable: 0,
            fileBacked: 0, pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
        )
        XCTAssertThrowsError(try MemoryFootprint.usedBytes(from: overflow, physicalBytes: .max))
    }
}
