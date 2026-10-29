import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class SpaceSurveyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("space-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, kilobytes: Int) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Random bytes, so a compressing file system cannot shrink them.
        try Data((0..<kilobytes * 1024).map { _ in UInt8.random(in: 0...255) }).write(to: url)
    }

    private var later: ContinuousClock.Instant { .now + .seconds(60) }

    func testDriverSumsEachFirstLevelChildAndSkipsWhatItIsTold() async throws {
        try write("Big.app/Contents/MacOS/Big", kilobytes: 256)
        try write("Big.app/Contents/Resources/art", kilobytes: 128)
        try write("Small.app/Contents/MacOS/Small", kilobytes: 32)
        try write("Skipped/inside", kilobytes: 512)

        let size = await FolderSizeDriver().size(
            of: [FolderRoot(root.path), FolderRoot(root.path + "/missing"), FolderRoot(root.path)],
            skipping: [root.path + "/Skipped"], deadline: later
        )
        XCTAssertEqual(size.ending, .complete)
        XCTAssertEqual(size.files, 3, "a skipped folder's files are never read")
        let big = try XCTUnwrap(size.children["Big.app"])
        let small = try XCTUnwrap(size.children["Small.app"])
        // Only the split is checked: some file systems (ZFS) allocate new files lazily.
        XCTAssertGreaterThan(big, 0)
        XCTAssertGreaterThan(small, 0)
        XCTAssertNil(size.children["Skipped"])
        XCTAssertEqual(size.bytes, big + small, "a root given twice is walked once")
    }

    func testDriverCountsAWholeRootAsOneItem() async throws {
        try write("Photos Library.photoslibrary/originals/a", kilobytes: 16)
        try write("Photos Library.photoslibrary/resources/b", kilobytes: 16)
        let size = await FolderSizeDriver().size(
            of: [FolderRoot(root.path + "/Photos Library.photoslibrary", breakdown: .whole)], skipping: [], deadline: later
        )
        XCTAssertEqual(Array(size.children.keys), ["Photos Library.photoslibrary"])
        XCTAssertEqual(size.files, 2)
    }

    func testDriverCountsAHardLinkedFileOnce() async throws {
        try write("a/file", kilobytes: 128)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("b"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: root.appendingPathComponent("a/file"), to: root.appendingPathComponent("b/link"))

        let size = await FolderSizeDriver().size(of: [FolderRoot(root.path)], skipping: [], deadline: later)
        XCTAssertEqual(size.files, 1)
        XCTAssertEqual(size.children.count, 1, "whichever link the walk meets first owns the file")
        XCTAssertEqual(size.bytes, size.children.values.first)
    }

    func testDriverStopsAtItsDeadline() async throws {
        let many = root.appendingPathComponent("many")
        try FileManager.default.createDirectory(at: many, withIntermediateDirectories: true)
        for index in 0..<600 { FileManager.default.createFile(atPath: many.path + "/\(index)", contents: nil) }
        let size = await FolderSizeDriver().size(of: [FolderRoot(root.path)], skipping: [], deadline: .now - .seconds(1))
        XCTAssertEqual(size.ending, .timedOut)
        XCTAssertLessThan(size.files, 600)
    }

    func testSurveyWalksEachAreaWithoutCountingAnotherOne() async throws {
        let driver = Recorder()
        let survey = SpaceSurvey(driver: driver, home: "/Users/me")

        _ = await survey.measure(.applications)
        _ = await survey.measure(.library)
        _ = await survey.measure(.otherHome)
        _ = await survey.measure(.pictures)
        _ = await survey.measure(.appData)
        let calls = await driver.calls
        XCTAssertEqual(calls[0].roots.map(\.path), ["/Applications", "/Users/me/Applications"])
        XCTAssertEqual(calls[1].roots.map(\.path), ["/Users/me/Library"])
        XCTAssertEqual(calls[1].skipping, [
            "/Users/me/Library/Containers", "/Users/me/Library/Group Containers",
            "/Users/me/Library/Mobile Documents", "/Users/me/Library/CloudStorage",
            "/Users/me/Library/Application Support/AddressBook", "/Users/me/Library/Calendars",
            "/Users/me/Pictures/Photos Library.photoslibrary"
        ], "app data, private stores and cloud drives are their own areas, which ask macOS first")
        XCTAssertEqual(calls[2].roots.map(\.path), ["/Users/me"])
        XCTAssertTrue(calls[2].skipping.isSuperset(of: [
            "/Users/me/Library", "/Users/me/Desktop", "/Users/me/Documents", "/Users/me/Downloads", "/Users/me/Applications"
        ]), "the rest of home never walks into a named area")
        XCTAssertTrue(calls[3].skipping.contains("/Users/me/Pictures/Photos Library.photoslibrary"),
                      "the Photos library can raise a prompt, so Pictures leaves it to app data")
        XCTAssertEqual(calls[4].roots.filter { $0.breakdown == .whole }.map(\.path), [
            "/Users/me/Pictures/Photos Library.photoslibrary", "/Users/me/Library/Application Support/AddressBook",
            "/Users/me/Library/Calendars"
        ])
    }

    func testSurveyNamesTheLargestItemsAndKeepsLowerBounds() async {
        let survey = SpaceSurvey(driver: Recorder(), home: "/Users/me")
        let size = await survey.measure(.applications)
        XCTAssertEqual(size.bytes, 1_000)
        XCTAssertEqual(size.largest.map(\.name), ["Xcode", "Docker", "Mail"], "largest first, without .app")
        XCTAssertEqual(size.completeness, .unreadable(2))
        XCTAssertTrue(size.isLowerBound)
        XCTAssertEqual(size.path, "/Applications")
    }

    func testOnlyProtectedAreasAskMacOS() {
        XCTAssertEqual(SpaceArea.allCases.filter(\.asksMacOS), [.desktop, .documents, .downloads, .appData, .cloud])
        XCTAssertEqual(Set(SpaceSurvey.order), Set(SpaceArea.allCases), "a survey walks every area once")
        XCTAssertEqual(SpaceSurvey.order.count, SpaceArea.allCases.count)
    }
}

private actor Recorder: FolderSizing {
    struct Call { let roots: [FolderRoot]; let skipping: Set<String> }
    private(set) var calls: [Call] = []

    func size(of roots: [FolderRoot], skipping: Set<String>, deadline: ContinuousClock.Instant) async -> RawFolderSize {
        calls.append(Call(roots: roots, skipping: skipping))
        return RawFolderSize(
            bytes: 1_000, children: ["Xcode.app": 600, "Mail.app": 50, "Docker.app": 300, "tiny.photoslibrary": 50],
            unreadable: 2, files: 4, ending: .complete
        )
    }
}
