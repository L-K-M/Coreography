import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class SensorMonitorTests: XCTestCase {
    func testDecoderHandlesFixedPointFloatAndIntegerTypes() {
        XCTAssertEqual(SMCValueDecoder.number(type: "sp78", bytes: [0x2A, 0x80]), 42.5)
        XCTAssertEqual(SMCValueDecoder.number(type: "sp78", bytes: [0xFF, 0x00]), -1)
        XCTAssertEqual(SMCValueDecoder.number(type: "fpe2", bytes: [0x1F, 0x40]), 2000)
        XCTAssertEqual(SMCValueDecoder.number(type: "sp96", bytes: [0x01, 0x00]), 4)
        let float: Float = 41.25
        let littleEndian = withUnsafeBytes(of: float.bitPattern.littleEndian) { Array($0) }
        XCTAssertEqual(SMCValueDecoder.number(type: "flt ", bytes: littleEndian), 41.25)
        XCTAssertEqual(SMCValueDecoder.number(type: "ui8 ", bytes: [3]), 3)
        XCTAssertEqual(SMCValueDecoder.number(type: "si8 ", bytes: [0xFE]), -2)
        XCTAssertEqual(SMCValueDecoder.number(type: "ui16", bytes: [0x01, 0x02]), 258)
        XCTAssertEqual(SMCValueDecoder.number(type: "ui32", bytes: [0, 0, 0x08, 0x00]), 2048)

        // Unknown types, short replies and non-finite floats decode to nothing.
        XCTAssertNil(SMCValueDecoder.number(type: "{pwm", bytes: [0, 0]))
        XCTAssertNil(SMCValueDecoder.number(type: "sp78", bytes: [0x2A]))
        XCTAssertNil(SMCValueDecoder.number(type: "flt ", bytes: [0, 0]))
        let nan = withUnsafeBytes(of: Float.nan.bitPattern.littleEndian) { Array($0) }
        XCTAssertNil(SMCValueDecoder.number(type: "flt ", bytes: nan))
        XCTAssertNil(SMCValueDecoder.number(type: "spzz", bytes: [0, 0]))
    }

    func testHottestPlausibleSensorKeepsItsIdentityAndRegion() async throws {
        let monitor = try SensorMonitor(driver: FixtureSensorDriver([.success(RawSensors(
            power: [RawSensorValue(key: "PSTR", value: 12.5), RawSensorValue(key: "PDTR", value: 40)],
            temperatures: [
                RawSensorValue(key: "Te05", value: 48), RawSensorValue(key: "Tp09", value: 71.5),
                RawSensorValue(key: "Ts0P", value: 3), RawSensorValue(key: "TZ99", value: 400)
            ],
            fans: [RawFan(index: 0, rpm: 2400, maximumRPM: nil)], discoveryTruncated: false
        ))]))
        let sensors = try await monitor.sample()

        XCTAssertEqual(sensors.hottest?.key, "Tp09")
        XCTAssertEqual(sensors.hottest?.region, "CPU performance cores")
        XCTAssertEqual(sensors.hottest?.celsius.numericValue, 71.5)
        XCTAssertEqual(sensors.plausibleTemperatureCount, 2)
        XCTAssertEqual(sensors.implausibleTemperatureCount, 2)
        XCTAssertEqual(sensors.systemPowerWatts.numericValue, 12.5)
        XCTAssertEqual(sensors.systemPowerWatts.availability, .estimated)
        XCTAssertEqual(sensors.systemPowerWatts.source?.channel, "PSTR")
        XCTAssertEqual(sensors.fans.first?.rpm.numericValue, 2400)
        XCTAssertEqual(sensors.fans.first?.maximumRPM.availability, .unavailable)
    }

    func testEveryPlausibleTemperatureOfTheNewestSampleIsListed() async throws {
        let monitor = try SensorMonitor(driver: FixtureSensorDriver([.success(RawSensors(
            power: [], temperatures: [
                RawSensorValue(key: "Tp09", value: 71.5), RawSensorValue(key: "Te05", value: 48),
                RawSensorValue(key: "TZ99", value: 400)
            ],
            fans: [], discoveryTruncated: false
        ))]))
        _ = try await monitor.sample()
        let temperatures = await monitor.temperatures()
        XCTAssertEqual(temperatures.map(\.key), ["Te05", "Tp09"], "faults excluded, sorted by key")
        XCTAssertEqual(temperatures.first?.region, "CPU efficiency cores")
        await monitor.reset()
        let cleared = await monitor.temperatures()
        XCTAssertTrue(cleared.isEmpty)
    }

    func testDesktopRailFallbackAndFaultyRailsAreNotZero() async throws {
        let monitor = try SensorMonitor(driver: FixtureSensorDriver([
            .success(RawSensors(power: [RawSensorValue(key: "PSTR", value: 0), RawSensorValue(key: "PDTR", value: 31)],
                                temperatures: [], fans: [], discoveryTruncated: true)),
            .success(RawSensors(power: [RawSensorValue(key: "PSTR", value: -2)], temperatures: [], fans: [],
                                discoveryTruncated: false))
        ]))
        let desktop = try await monitor.sample()
        XCTAssertEqual(desktop.systemPowerWatts.numericValue, 31)
        XCTAssertEqual(desktop.systemPowerWatts.source?.channel, "PDTR")
        XCTAssertNil(desktop.hottest)
        XCTAssertTrue(desktop.discoveryTruncated)

        let faulty = try await monitor.sample()
        XCTAssertEqual(faulty.systemPowerWatts.availability, .unavailable)
        XCTAssertNil(faulty.systemPowerWatts.numericValue)
    }

    func testMissingOrRefusedSMCIsExplicit() async throws {
        let monitor = try SensorMonitor(driver: FixtureSensorDriver([
            .failure(.notPresent), .failure(.restricted(code: 1))
        ]))
        let virtual = try await monitor.sample()
        XCTAssertEqual(virtual.source.availability, .unsupported)
        XCTAssertEqual(virtual.systemPowerWatts.availability, .unsupported)
        let refused = try await monitor.sample()
        XCTAssertEqual(refused.source.availability, .restricted)
    }
}

private actor FixtureSensorDriver: SensorSampleReading {
    private static let clock = UUID(uuidString: "9B4E1C2D-7A3F-4B6E-8D10-5C2A9E7F3B41")!
    private var results: [Result<RawSensors, SensorDriverError>]
    private var count: UInt64 = 0

    init(_ results: [Result<RawSensors, SensorDriverError>]) { self.results = results }

    func read() async -> RawSensorSnapshot {
        precondition(!results.isEmpty, "Fixture exhausted")
        count += 1
        return RawSensorSnapshot(
            clockID: Self.clock, monotonicNanoseconds: count * 1_000_000_000,
            wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(count)),
            sensors: results.removeFirst()
        )
    }
}
