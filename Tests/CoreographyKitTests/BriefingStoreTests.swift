import Foundation
import XCTest
@testable import CoreographyKit

final class BriefingStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testBriefingsRoundTripAndAbsenceIsNotAFailure() throws {
        let store = BriefingStore(directory: directory.appendingPathComponent("Widgets"))
        XCTAssertEqual(store.read(), .success(nil), "no file means briefings are off, not broken")

        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let briefing = Briefing(
            outcome: .text("Quiet."), model: "claude-haiku-5-5", windowStart: epoch, windowEnd: epoch.addingTimeInterval(300)
        )
        try store.write(briefing)
        XCTAssertEqual(store.read(), .success(briefing))

        let failed = Briefing(outcome: .failed("No key"), model: "m", windowStart: epoch, windowEnd: epoch)
        try store.write(failed)
        XCTAssertEqual(store.read(), .success(failed), "a newer write replaces the file")

        try store.remove()
        try store.remove()
        XCTAssertEqual(store.read(), .success(nil), "removing twice is fine")
    }

    func testForeignOrOversizedFilesAreUnreadableNotBriefings() throws {
        let store = BriefingStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.read(), .failure(.unreadable("The briefing file is not a briefing")))

        try Data(repeating: 32, count: 64 * 1024 + 1).write(to: store.fileURL)
        XCTAssertEqual(store.read(), .failure(.unreadable("The briefing file is too large")))
    }

    func testTheDefaultFileIsUnderTheRealHomeAtTheEntitledPath() {
        // The widget's sandbox exception names this home-relative directory.
        XCTAssertTrue(BriefingStore().fileURL.path.hasSuffix("/Library/Application Support/Coreography/Widgets/briefing.json"))
        XCTAssertFalse(BriefingStore().fileURL.path.contains("/Containers/"))
    }
}
