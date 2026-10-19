import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class StoredContributorsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plan P3: scrubbing to a past moment names who led then, from what
    /// retention kept. The stored ledger keeps CPU, disk and network per app;
    /// memory, GPU and power were never stored per app and say so.
    func testTheStoredIntervalUnderTheCursorNamesItsLeaders() throws {
        let ledger = AppLedger(stored: [
            LedgerInterval(start: epoch, end: epoch.addingTimeInterval(2), cores: 4, coversNetwork: true, entries: [
                LedgerEntry(app: "Xcode", cpuSeconds: 4, diskBytes: 2_000, networkBytes: 0, isLowerBound: false),
                LedgerEntry(app: "Safari", cpuSeconds: 1, diskBytes: 0, networkBytes: 6_000, isLowerBound: true)
            ]),
            LedgerInterval(start: epoch.addingTimeInterval(10), end: epoch.addingTimeInterval(12), cores: 4, entries: [
                LedgerEntry(app: "Mail", cpuSeconds: 2, diskBytes: 0, isLowerBound: false)
            ])
        ])
        let snapshot = try XCTUnwrap(ledger.contributors(at: epoch.addingTimeInterval(1)))
        XCTAssertEqual(snapshot.origin, .storedLedger)
        XCTAssertEqual(snapshot.time, epoch.addingTimeInterval(2), "the interval's end, as a live sample would be")
        XCTAssertEqual(snapshot.cpu.map(\.name), ["Xcode", "Safari"])
        XCTAssertEqual(snapshot.cpu.first?.value, 50, "4 CPU-seconds over 2 s of 4 cores")
        XCTAssertEqual(snapshot.cpu.last?.isEstimate, true, "a lower bound is marked")
        XCTAssertEqual(snapshot.disk.map(\.value), [1_000])
        XCTAssertEqual(snapshot.network.map(\.name), ["Safari"])
        XCTAssertTrue(snapshot.memory.isEmpty && snapshot.gpu.isEmpty && snapshot.power.isEmpty)

        let unread = try XCTUnwrap(ledger.contributors(at: epoch.addingTimeInterval(11)))
        XCTAssertTrue(unread.network.isEmpty, "an interval that did not read network names no one")
        XCTAssertNil(ledger.contributors(at: epoch.addingTimeInterval(6)), "between intervals nothing was observed")
    }
}
