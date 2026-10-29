import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class SpaceBraidTests: XCTestCase {
    private let volume = VolumeCapacity(RawVolume(
        path: "/", name: "Macintosh HD", kind: .internal, isStartup: true,
        capacity: RawVolumeCapacity(totalBytes: 1_000, availableBytes: 200)
    ))

    private func size(_ area: SpaceArea, _ bytes: Int64, _ completeness: SpaceAreaSize.Completeness = .complete) -> SpaceAreaSize {
        SpaceAreaSize(area: area, bytes: bytes, largest: [], completeness: completeness, path: "/")
    }

    func testAreasRankLargestFirstAndTheRestExplainsTheUsedSpace() throws {
        let braid = SpaceBraid(
            volume: volume,
            sizes: [.applications: size(.applications, 100), .library: size(.library, 300), .movies: size(.movies, 0)],
            unmeasured: [], measuring: nil
        )
        XCTAssertEqual(braid.usedBytes, 800)
        XCTAssertEqual(braid.strands.map(\.kind), [.area(.library), .area(.applications), .rest], "empty areas are not strands")
        let rest = try XCTUnwrap(braid.strands.last)
        XCTAssertEqual(rest.bytes, 400)
        XCTAssertEqual(rest.share ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertFalse(rest.isUpperBound, "every area was walked completely")
        XCTAssertTrue(braid.reconciles)
        XCTAssertEqual(braid.strands.compactMap(\.share).reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertEqual(braid.spans, [0..<0.3, 0.3..<0.4, 0.4..<0.8], "the rope ends where free space begins")
    }

    func testTheRestIsAtMostWhileAnythingWasNotSeen() {
        let partial = SpaceBraid(volume: volume, sizes: [.library: size(.library, 300, .timedOut)], unmeasured: [], measuring: nil)
        XCTAssertTrue(partial.strands[0].isLowerBound)
        XCTAssertTrue(partial.strands[1].isUpperBound)

        let asking = SpaceBraid(volume: volume, sizes: [:], unmeasured: [.documents], measuring: nil)
        XCTAssertEqual(asking.strands.map(\.kind), [.rest])
        XCTAssertEqual(asking.strands[0].bytes, 800, "before any walk, the rest is all of the used space")
        XCTAssertTrue(asking.strands[0].isUpperBound)

        let walking = SpaceBraid(volume: volume, sizes: [:], unmeasured: [], measuring: .music)
        XCTAssertTrue(walking.strands[0].isUpperBound)
    }

    func testAFolderMacOSRefusedIsNamedRatherThanShownAsEmpty() {
        let braid = SpaceBraid(
            volume: volume, sizes: [.documents: size(.documents, 0, .unreadable(1)), .movies: size(.movies, 0)],
            unmeasured: [], measuring: nil
        )
        XCTAssertEqual(braid.refused, [.documents], "an empty folder is not a refusal")
        XCTAssertEqual(braid.strands.map(\.kind), [.rest])
    }

    func testAreasAddingUpToMoreThanTheUsedSpaceDoNotInventARest() {
        let braid = SpaceBraid(volume: volume, sizes: [.library: size(.library, 900)], unmeasured: [], measuring: nil)
        XCTAssertNil(braid.strands.last?.bytes)
        XCTAssertNil(braid.strands.last?.share)
        XCTAssertFalse(braid.reconciles)
        XCTAssertEqual(braid.spans.last?.upperBound ?? 0, 0.8, accuracy: 1e-9, "an overrun is scaled to the used space")
    }

    @MainActor
    func testSurveyorWalksOnlyPromptFreeAreasUntilThePersonWidensIt() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let driver = Walks()
        let surveyor = SpaceSurveyor(survey: SpaceSurvey(driver: driver, home: "/Users/me"), defaults: defaults)

        surveyor.refreshIfStale()
        await waitUntilIdle(surveyor)
        let quiet = await driver.roots
        XCTAssertFalse(quiet.contains("/Users/me/Documents"), "no prompt-raising folder is walked unasked")
        XCTAssertEqual(surveyor.unmeasured, [.desktop, .documents, .downloads, .appData, .cloud])
        XCTAssertNotNil(surveyor.measuredAt)

        surveyor.refreshIfStale()
        XCTAssertFalse(surveyor.isMeasuring, "a fresh survey is shown as is")

        surveyor.measure(.askingMacOS)
        await waitUntilIdle(surveyor)
        let asked = await driver.roots
        XCTAssertTrue(asked.contains("/Users/me/Documents"))
        XCTAssertEqual(defaults.string(forKey: SpaceSurveyor.accessKey), "askingMacOS", "the person's choice is remembered")
        XCTAssertEqual(surveyor.unmeasured, [])
    }

    @MainActor
    private func waitUntilIdle(_ surveyor: SpaceSurveyor) async {
        for _ in 0..<500 where surveyor.isMeasuring { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(surveyor.isMeasuring)
    }
}

private actor Walks: FolderSizing {
    private(set) var roots: [String] = []

    func size(of roots: [FolderRoot], skipping: Set<String>, deadline: ContinuousClock.Instant) async -> RawFolderSize {
        self.roots += roots.map(\.path)
        return RawFolderSize(bytes: 10, children: [:], unreadable: 0, files: 1, ending: .complete)
    }
}
