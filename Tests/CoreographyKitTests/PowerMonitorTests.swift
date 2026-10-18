import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class PowerMonitorTests: XCTestCase {
    func testDecoderReadsTheInternalBatteryAndIgnoresUnknownEstimates() throws {
        let ups: [String: Any] = ["Type": "UPS", "Current Capacity": NSNumber(value: 10), "Max Capacity": NSNumber(value: 100)]
        let battery: [String: Any] = [
            "Type": "InternalBattery", "Current Capacity": NSNumber(value: 80), "Max Capacity": NSNumber(value: 100),
            "Power Source State": "Battery Power", "Is Charging": false,
            "Time to Empty": NSNumber(value: 212), "Time to Full Charge": NSNumber(value: -1)
        ]
        let state = try PowerSourceDecoder.battery([ups, battery]).get()
        XCTAssertEqual(state, BatteryState(
            chargePercent: 80, powerSource: .battery, isCharging: false, minutesToEmpty: 212, minutesToFull: nil
        ))

        XCTAssertEqual(PowerSourceDecoder.battery([ups]), .failure(.noBattery))
        var invalid = battery
        invalid["Current Capacity"] = NSNumber(value: 101)
        XCTAssertThrowsError(try PowerSourceDecoder.battery([invalid]).get())
        invalid["Current Capacity"] = true
        XCTAssertThrowsError(try PowerSourceDecoder.battery([invalid]).get())
    }

    func testDecoderReadsSignedGasGaugeCurrentAndAdapterRating() throws {
        let gauge = try PowerSourceDecoder.gauge([
            "Voltage": NSNumber(value: 12_000), "Amperage": NSNumber(value: -1_500),
            "CycleCount": NSNumber(value: 87), "DesignCapacity": NSNumber(value: 5_000),
            "AppleRawMaxCapacity": NSNumber(value: 4_500)
        ]).get()
        XCTAssertEqual(gauge.amperageMilliamps, -1_500)
        XCTAssertEqual(gauge.cycleCount, 87)
        XCTAssertThrowsError(try PowerSourceDecoder.gauge(["Voltage": NSNumber(value: 12_000)]).get())

        XCTAssertEqual(PowerSourceDecoder.adapterWatts(["Watts": NSNumber(value: 96)]), .success(96))
        XCTAssertEqual(PowerSourceDecoder.adapterWatts(nil), .failure(.unavailable(reason: "No power adapter connected")))
    }

    func testOnBatteryTheDischargeIsTheSystemDraw() async throws {
        let monitor = try PowerMonitor(driver: FixturePowerDriver([
            raw(source: .battery, charging: false, amperage: -1_500)
        ]))
        let power = try await monitor.sample()
        // 12 V × -1.5 A.
        XCTAssertEqual(power.batteryPowerWatts.numericValue, -18)
        XCTAssertEqual(power.systemPowerWatts.numericValue, 18)
        XCTAssertEqual(power.systemPowerWatts.availability, .estimated)
        XCTAssertEqual(power.batteryChargePercent.numericValue, 80)
        XCTAssertEqual(power.batteryMinutesRemaining.numericValue, 212)
        XCTAssertEqual(power.batteryHealthPercent.numericValue, 90)
        XCTAssertEqual(power.batteryCycleCount.numericValue, 87)
        XCTAssertEqual(power.powerSource, .battery)
    }

    func testOnExternalPowerSystemDrawIsUnknownNotTheChargeRate() async throws {
        let monitor = try PowerMonitor(driver: FixturePowerDriver([
            raw(source: .externalPower, charging: true, amperage: 2_000)
        ]))
        let power = try await monitor.sample()
        XCTAssertEqual(power.batteryPowerWatts.numericValue, 24)
        XCTAssertEqual(power.systemPowerWatts.availability, .unavailable)
        XCTAssertNil(power.systemPowerWatts.numericValue)
        XCTAssertEqual(power.adapterRatingWatts.numericValue, 96)
        XCTAssertEqual(power.batteryMinutesRemaining.availability, .unavailable)
    }

    func testDesktopWithoutBatteryIsUnsupportedNotZero() async throws {
        let monitor = try PowerMonitor(driver: FixturePowerDriver([RawPowerSnapshot(
            clockID: Self.clock, monotonicNanoseconds: 1, wallTime: Self.epoch,
            battery: .failure(.noBattery), gauge: .failure(.noBattery),
            adapterWatts: .failure(.unavailable(reason: "No power adapter connected"))
        )]))
        let power = try await monitor.sample()
        XCTAssertEqual(power.batteryChargePercent.availability, .unsupported)
        XCTAssertEqual(power.batteryPowerWatts.availability, .unsupported)
        XCTAssertEqual(power.systemPowerWatts.availability, .unavailable)
        XCTAssertNil(power.powerSource)
    }

    private static let clock = UUID(uuidString: "2F1B9A3E-5C47-4E0B-8B44-0D2C7A61E9F3")!
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func raw(source: PowerSourceState, charging: Bool, amperage: Int64) -> RawPowerSnapshot {
        RawPowerSnapshot(
            clockID: Self.clock, monotonicNanoseconds: 1, wallTime: Self.epoch,
            battery: .success(BatteryState(
                chargePercent: 80, powerSource: source, isCharging: charging,
                minutesToEmpty: charging ? nil : 212, minutesToFull: nil
            )),
            gauge: .success(BatteryGauge(
                voltageMillivolts: 12_000, amperageMilliamps: amperage, cycleCount: 87,
                designCapacityMilliampHours: 5_000, fullChargeCapacityMilliampHours: 4_500
            )),
            adapterWatts: source == .externalPower ? .success(96) : .failure(.unavailable(reason: "No power adapter connected"))
        )
    }
}

private actor FixturePowerDriver: PowerSampleReading {
    private var samples: [RawPowerSnapshot]
    init(_ samples: [RawPowerSnapshot]) { self.samples = samples }
    func read() async -> RawPowerSnapshot {
        precondition(!samples.isEmpty, "Fixture exhausted")
        return samples.removeFirst()
    }
}
