import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class TierBandTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testCellsReachTheNextSampleAndNeverBridgeBreaks() throws {
        let frames = try [
            frame(at: 0, efficiency: 40, performance: 10),
            frame(at: 1, efficiency: 50, performance: nil),
            frame(at: 5, efficiency: 140, performance: 20, continuity: .interrupted)
        ]
        let cells = TierBand.cells(frames)
        XCTAssertEqual(cells.map(\.tier), ["E", "P", "E", "E", "P"], "a tier without a reading leaves a hole")
        XCTAssertEqual(cells[0].end, epoch.addingTimeInterval(1), "up to the next sample")
        XCTAssertEqual(cells[2].end, epoch.addingTimeInterval(2), "not across the break to the interrupted sample")
        XCTAssertEqual(cells[3].activePercent, 100, "activity is a share")
        XCTAssertEqual(cells[4].end, epoch.addingTimeInterval(6), "the newest sample covers one interval")
    }

    private func frame(
        at second: Double, efficiency: Double, performance: Double?, continuity: SamplingContinuity = .continuous
    ) throws -> CapturedSilicon {
        let watts = try MetricReading.estimated(1, method: "test")
        func tier(_ kind: CPUTierKind, _ active: Double?) throws -> CPUTierReading {
            CPUTierReading(
                kind: kind, cores: 4,
                activePercent: try active.map { try .estimated($0, method: "test") } ?? .gap(reason: "test"),
                frequencyMHz: try .estimated(1_000, method: "test"), maximumMHz: nil
            )
        }
        return SiliconSnapshot(
            id: UUID(), stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: UInt64(second * 1e9), wallTime: epoch.addingTimeInterval(second)),
            cpuPowerWatts: watts, gpuPowerWatts: watts, anePowerWatts: watts, dramPowerWatts: watts,
            cpuTiers: [try tier(.e, efficiency), try tier(.p, performance)],
            gpuActivePercent: watts, gpuFrequencyMHz: watts, continuity: continuity
        )
    }
}
