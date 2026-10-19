import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class SensorStatsTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testTracksCurrentMinMaxAndMeanPerSensorSinceReset() throws {
        var stats = SensorStats()
        stats.record(temperatures: [try temperature("Tp01", 50, region: "CPU performance cores"), try temperature("Tx01", 40)], sensors: nil, at: epoch)
        stats.record(temperatures: [try temperature("Tp01", 70, region: "CPU performance cores")], sensors: nil, at: epoch.addingTimeInterval(1))

        let rows = stats.rows()
        XCTAssertEqual(rows.map(\.group), ["CPU performance cores", "Other temperatures"])
        let cpu = try XCTUnwrap(rows.first)
        XCTAssertEqual(cpu.current, 70)
        XCTAssertEqual(cpu.minimum, 50)
        XCTAssertEqual(cpu.maximum, 70)
        XCTAssertEqual(cpu.mean, 60)
        XCTAssertEqual(cpu.samples, 2)
        XCTAssertNil(rows.last?.current, "a sensor missing from the newest sample has no current value")
        XCTAssertEqual(rows.last?.maximum, 40, "but keeps its statistics")
        XCTAssertEqual(stats.since, epoch)

        stats.reset()
        XCTAssertTrue(stats.rows().isEmpty)
        XCTAssertNil(stats.since)
    }

    func testUnreadableReadingsAreSkippedNotCountedAsZero() throws {
        var stats = SensorStats()
        let unreadable = TemperatureReading(key: "Tp01", region: nil, celsius: try .unavailable(reason: "fault"))
        stats.record(temperatures: [unreadable], sensors: nil, at: epoch)
        XCTAssertTrue(stats.rows().isEmpty)
        XCTAssertNil(stats.since, "statistics start with the first real reading")
    }

    func testAnEntirelyUnreadableSampleClearsEveryCurrentValue() throws {
        var stats = SensorStats()
        stats.record(temperatures: [try temperature("Tp01", 50)], sensors: nil, at: epoch)
        let unreadable = TemperatureReading(key: "Tp01", region: nil, celsius: try .unavailable(reason: "fault"))
        stats.record(temperatures: [unreadable], sensors: nil, at: epoch.addingTimeInterval(1))

        let row = try XCTUnwrap(stats.rows().first)
        XCTAssertNil(row.current, "a failed sample is not the last good one again")
        XCTAssertEqual(row.maximum, 50, "statistics stay")
        XCTAssertEqual(stats.since, epoch)
    }

    private func temperature(_ key: String, _ celsius: Double, region: String? = nil) throws -> TemperatureReading {
        TemperatureReading(key: key, region: region, celsius: try .measured(celsius))
    }
}
