import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class VolumeMonitorTests: XCTestCase {
    func testDecoderPrefersImportantUseSpaceAndNamesEveryVolume() throws {
        let data = try XCTUnwrap(VolumeDecoder.volume(
            path: "/Volumes/Data", name: "", total: 1_000, important: 400, available: 300,
            isInternal: false, isLocal: true, isRoot: false
        ))
        XCTAssertEqual(data.name, "Data", "an unnamed volume takes its mount point's name")
        XCTAssertEqual(data.kind, .external)
        XCTAssertEqual(data.capacity, RawVolumeCapacity(totalBytes: 1_000, availableBytes: 400))

        let share = try XCTUnwrap(VolumeDecoder.volume(
            path: "/Volumes/Share", name: "Share", total: 1_000, important: nil, available: 2_000,
            isInternal: nil, isLocal: false, isRoot: false
        ))
        XCTAssertEqual(share.kind, .network)
        XCTAssertEqual(share.capacity.availableBytes, 1_000, "free space never exceeds the volume")

        XCTAssertNil(VolumeDecoder.volume(path: "/x", name: "X", total: nil, important: 1, available: 1,
                                          isInternal: true, isLocal: true, isRoot: false))
        XCTAssertNil(VolumeDecoder.volume(path: "/x", name: "X", total: 10, important: nil, available: nil,
                                          isInternal: true, isLocal: true, isRoot: false), "unknown free space is not zero")
    }

    func testVolumesListStartupFirstThenByKindAndName() async {
        let list = await VolumeMonitor(driver: Mounted()).volumes()
        XCTAssertEqual(list.volumes.map(\.name), ["Macintosh HD", "Archive", "Backup", "NAS"])
        XCTAssertNil(list.problem)
        XCTAssertEqual(list.volumes.first?.usedFraction ?? 0, 0.75, accuracy: 1e-9)

        let none = await VolumeMonitor(driver: Unlisted()).volumes()
        XCTAssertEqual(none.problem, "Mounted volumes could not be listed")
        XCTAssertTrue(none.volumes.isEmpty)
    }
}

private struct Mounted: VolumeCapacityReading {
    func startupVolume() async -> Result<RawVolumeCapacity, VolumeCapacityError> { .failure(.unsupportedPlatform) }

    func mountedVolumes() async -> Result<[RawVolume], VolumeCapacityError> {
        func volume(_ name: String, _ kind: RawVolumeKind, startup: Bool = false, total: Int64 = 100) -> RawVolume {
            RawVolume(path: "/Volumes/\(name)", name: name, kind: kind, isStartup: startup,
                      capacity: RawVolumeCapacity(totalBytes: total, availableBytes: total / 4))
        }
        return .success([
            volume("NAS", .network), volume("Backup", .external), volume("Macintosh HD", .internal, startup: true),
            volume("Archive", .internal), volume("Empty", .external, total: 0)
        ])
    }
}

private struct Unlisted: VolumeCapacityReading {
    func startupVolume() async -> Result<RawVolumeCapacity, VolumeCapacityError> { .failure(.unsupportedPlatform) }
    func mountedVolumes() async -> Result<[RawVolume], VolumeCapacityError> { .failure(.unavailable("Mounted volumes could not be listed")) }
}
