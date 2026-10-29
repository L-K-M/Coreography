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
        // Some file systems (ZFS) settle a new file's allocation only once written out.
        sync()

        let size = await FolderSizeDriver().size(
            of: [root.path, root.path + "/missing"], skipping: [root.path + "/Skipped"], deadline: later
        )
        XCTAssertEqual(size.ending, .complete)
        XCTAssertEqual(size.files, 3, "a skipped folder's files are never read")
        let big = try XCTUnwrap(size.children["Big.app"])
        let small = try XCTUnwrap(size.children["Small.app"])
        XCTAssertGreaterThan(big, small)
        XCTAssertNil(size.children["Skipped"])
        XCTAssertEqual(size.bytes, big + small)
    }

    func testDriverCountsAHardLinkedFileOnce() async throws {
        try write("a/file", kilobytes: 128)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("b"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: root.appendingPathComponent("a/file"), to: root.appendingPathComponent("b/link"))

        let size = await FolderSizeDriver().size(of: [root.path], skipping: [], deadline: later)
        XCTAssertEqual(size.files, 1)
        XCTAssertEqual(size.children.count, 1, "whichever link the walk meets first owns the file")
        XCTAssertEqual(size.bytes, size.children.values.first)
    }

    func testDriverStopsAtItsDeadline() async throws {
        let many = root.appendingPathComponent("many")
        try FileManager.default.createDirectory(at: many, withIntermediateDirectories: true)
        for index in 0..<600 { FileManager.default.createFile(atPath: many.path + "/\(index)", contents: nil) }
        let size = await FolderSizeDriver().size(of: [root.path], skipping: [], deadline: .now - .seconds(1))
        XCTAssertEqual(size.ending, .timedOut)
        XCTAssertLessThan(size.files, 600)
    }

    func testSurveyWalksEachAreaWithoutCountingAnotherOne() async throws {
        let driver = Recorder()
        let survey = SpaceSurvey(driver: driver, home: "/Users/me")

        _ = await survey.measure(.applications)
        _ = await survey.measure(.library)
        _ = await survey.measure(.otherHome)
        let calls = await driver.calls
        XCTAssertEqual(calls[0].roots, ["/Applications", "/Users/me/Applications"])
        XCTAssertEqual(calls[1].roots, ["/Users/me/Library"])
        XCTAssertEqual(calls[1].skipping, [
            "/Users/me/Library/Containers", "/Users/me/Library/Group Containers",
            "/Users/me/Library/Mobile Documents", "/Users/me/Library/CloudStorage"
        ], "app data and cloud drives are their own areas, which ask macOS first")
        XCTAssertEqual(calls[2].roots, ["/Users/me"])
        XCTAssertTrue(calls[2].skipping.isSuperset(of: [
            "/Users/me/Library", "/Users/me/Desktop", "/Users/me/Documents", "/Users/me/Downloads", "/Users/me/Applications"
        ]), "the rest of home never walks into a named area")
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
    struct Call { let roots: [String]; let skipping: Set<String> }
    private(set) var calls: [Call] = []

    func size(of roots: [String], skipping: Set<String>, deadline: ContinuousClock.Instant) async -> RawFolderSize {
        calls.append(Call(roots: roots, skipping: skipping))
        return RawFolderSize(
            bytes: 1_000, children: ["Xcode.app": 600, "Mail.app": 50, "Docker.app": 300, "tiny": 50],
            unreadable: 2, files: 4, ending: .complete
        )
    }
}
