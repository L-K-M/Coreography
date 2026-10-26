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

        // The startup disk's data volume shares its space; listing it would show the disk twice.
        XCTAssertNil(VolumeDecoder.volume(path: "/System/Volumes/Data", name: "Macintosh HD - Data", total: 1_000, important: 400,
                                          available: 300, isInternal: true, isLocal: true, isRoot: false))
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

    func testStartupCapacityKeepsReasonsAndClampsFreeSpace() async {
        let measured = await VolumeMonitor(driver: Startup(.success(RawVolumeCapacity(totalBytes: 1_000, availableBytes: 250))))
            .startupCapacity()
        XCTAssertEqual(measured, .measured(totalBytes: 1_000, availableBytes: 250))
        XCTAssertEqual(measured.usedBytes, 750)
        XCTAssertEqual(measured.usedFraction ?? 0, 0.75, accuracy: 1e-9)

        let overfull = await VolumeMonitor(driver: Startup(.success(RawVolumeCapacity(totalBytes: 1_000, availableBytes: 2_000))))
            .startupCapacity()
        XCTAssertEqual(overfull.usedBytes, 0, "free space never exceeds the volume")

        let empty = await VolumeMonitor(driver: Startup(.success(RawVolumeCapacity(totalBytes: 0, availableBytes: 0))))
            .startupCapacity()
        XCTAssertNil(empty.usedFraction, "a volume without a size is unknown, not full")

        // A capacity built directly keeps the same bounds as one the monitor read.
        XCTAssertNil(StartupCapacity.measured(totalBytes: 0, availableBytes: 0).usedFraction)
        XCTAssertEqual(StartupCapacity.measured(totalBytes: 100, availableBytes: 300).usedFraction, 0)
        XCTAssertEqual(StartupCapacity.measured(totalBytes: 100, availableBytes: -5).usedFraction, 1)

        let failed = await VolumeMonitor(driver: Startup(.failure(.unavailable("No capacity")))).startupCapacity()
        XCTAssertEqual(failed, .unavailable(reason: "No capacity"))
        XCTAssertNil(failed.usedBytes)
    }
}

private struct Startup: VolumeCapacityReading {
    let result: Result<RawVolumeCapacity, VolumeCapacityError>

    init(_ result: Result<RawVolumeCapacity, VolumeCapacityError>) { self.result = result }

    func startupVolume() async -> Result<RawVolumeCapacity, VolumeCapacityError> { result }
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
