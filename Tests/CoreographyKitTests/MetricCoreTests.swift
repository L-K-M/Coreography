import Foundation
import XCTest
@testable import CoreographyKit

final class MetricCoreTests: XCTestCase {

    // MARK: - MetricReading factories

    func testMeasuredReadingCarriesFiniteValue() throws {
        let source = MetricSource(provider: "host", driver: "mach")
        let reading = try MetricReading.measured(42.5, source: source)
        XCTAssertEqual(reading.availability, .measured)
        XCTAssertEqual(reading.numericValue, 42.5)
        XCTAssertEqual(reading.source, source)
        XCTAssertNil(reading.method)
        XCTAssertNil(reading.reason)
    }

    func testMeasuredRejectsNonFiniteValues() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try MetricReading.measured(value)) { error in
                XCTAssertEqual(
                    error as? MetricReadingError,
                    .nonFiniteValue(.measured)
                )
            }
        }
    }

    func testEstimatedRejectsNonFiniteAndRequiresMethod() throws {
        XCTAssertThrowsError(
            try MetricReading.estimated(.nan, method: "ioreport-model")
        ) { error in
            XCTAssertEqual(
                error as? MetricReadingError, .nonFiniteValue(.estimated)
            )
        }
        XCTAssertThrowsError(
            try MetricReading.estimated(3.0, method: "")
        ) { error in
            XCTAssertEqual(
                error as? MetricReadingError, .missingEstimationMethod
            )
        }

        let reading = try MetricReading.estimated(3.0, method: "ioreport-model")
        XCTAssertEqual(reading.availability, .estimated)
        XCTAssertEqual(reading.numericValue, 3.0)
        XCTAssertEqual(reading.method, "ioreport-model")
    }

    func testNonNumericStatesCarryNoValue() throws {
        let readings: [MetricReading] = [
            .collecting(),
            .gap(reason: "paused"),
            try .unavailable(reason: "host_statistics failed"),
            try .restricted(reason: "needs helper"),
            .unsupported(reason: "no such sensor"),
        ]
        for reading in readings {
            XCTAssertNil(reading.numericValue)
            XCTAssertNotEqual(reading.availability, .measured)
            XCTAssertNotEqual(reading.availability, .estimated)
        }
    }

    func testRestrictedAndUnavailableRequireReason() {
        XCTAssertThrowsError(try MetricReading.restricted(reason: "")) {
            XCTAssertEqual(
                $0 as? MetricReadingError, .missingReason(.restricted)
            )
        }
        XCTAssertThrowsError(try MetricReading.unavailable(reason: "")) {
            XCTAssertEqual(
                $0 as? MetricReadingError, .missingReason(.unavailable)
            )
        }
    }

    /// A real measured zero must stay distinguishable from a gap.
    func testMeasuredZeroIsNotAGap() throws {
        let zero = try MetricReading.measured(0)
        let gap = MetricReading.gap(reason: "missed interval")
        XCTAssertEqual(zero.numericValue, 0)
        XCTAssertEqual(zero.availability, .measured)
        XCTAssertNil(gap.numericValue)
        XCTAssertEqual(gap.availability, .gap)
        XCTAssertNotEqual(zero, gap)
    }

    // MARK: - MetricReading Codable invariants

    private func decode(_ json: String) throws -> MetricReading {
        try JSONDecoder().decode(
            MetricReading.self, from: Data(json.utf8)
        )
    }

    func testDecodingRoundTripsAllStates() throws {
        let source = MetricSource(
            provider: "host", driver: "mach", channel: "cpu",
            chipProfile: "m4-generic"
        )
        let readings: [MetricReading] = [
            try .measured(7.25, source: source),
            try .estimated(1.5, method: "clpc", source: source),
            .collecting(source: source),
            .gap(reason: "missed interval", source: source),
            try .unavailable(reason: "read failed", source: source),
            try .restricted(reason: "entitlement", source: source),
            .unsupported(source: source),
        ]
        let encoder = JSONEncoder()
        for reading in readings {
            let decoded = try JSONDecoder().decode(
                MetricReading.self, from: encoder.encode(reading)
            )
            XCTAssertEqual(decoded, reading)
        }
    }

    func testDecodingRejectsValueOnNonNumericState() {
        XCTAssertThrowsError(
            try decode(#"{"availability":"gap","numericValue":7}"#)
        )
        XCTAssertThrowsError(
            try decode(#"{"availability":"restricted","numericValue":7,"reason":"x"}"#)
        )
    }

    func testDecodingRejectsMissingValueOnMeasured() {
        XCTAssertThrowsError(try decode(#"{"availability":"measured"}"#))
        XCTAssertThrowsError(
            try decode(#"{"availability":"estimated","method":"m"}"#)
        )
    }

    func testDecodingRejectsMissingMethodAndMissingReason() {
        XCTAssertThrowsError(
            try decode(#"{"availability":"estimated","numericValue":3}"#)
        )
        XCTAssertThrowsError(
            try decode(#"{"availability":"unavailable"}"#)
        )
    }

    func testDecodingRejectsNonFiniteValue() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        XCTAssertThrowsError(
            try decoder.decode(
                MetricReading.self,
                from: Data(#"{"availability":"measured","numericValue":"nan"}"#.utf8)
            )
        )
    }

    // MARK: - SampleStamp

    func testSampleStampIdentityAndFields() {
        let clock = UUID()
        let wall = Date(timeIntervalSince1970: 1_700_000_000)
        let a = SampleStamp(
            clockID: clock, monotonicNanoseconds: 5, wallTime: wall
        )
        let b = SampleStamp(
            clockID: clock, monotonicNanoseconds: 5, wallTime: wall
        )
        let differentClock = SampleStamp(
            clockID: UUID(), monotonicNanoseconds: 5, wallTime: wall
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, differentClock)
    }

    func testSampleStampNowAdvancesMonotonic() {
        let clock = UUID()
        let first = SampleStamp.now(clockID: clock)
        let second = SampleStamp.now(clockID: clock)
        XCTAssertEqual(first.clockID, second.clockID)
        XCTAssertGreaterThanOrEqual(
            second.monotonicNanoseconds, first.monotonicNanoseconds
        )
    }

    // MARK: - CounterRateTracker

    private let clock = UUID()
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func stamp(
        _ nanoseconds: UInt64, clockID: UUID? = nil
    ) -> SampleStamp {
        SampleStamp(
            clockID: clockID ?? clock,
            monotonicNanoseconds: nanoseconds,
            wallTime: epoch
        )
    }

    func testTrackerFirstSampleIsCollecting() throws {
        var tracker = try CounterRateTracker(maxGap: .seconds(5))
        XCTAssertEqual(
            tracker.record(100, at: stamp(0)).availability, .collecting
        )
    }

    func testTrackerRateIsDeltaOverRealElapsedSeconds() throws {
        var tracker = try CounterRateTracker(maxGap: .seconds(5))
        _ = tracker.record(1_000, at: stamp(0))
        // 300 units over 2 s of monotonic time -> 150/s, independent of
        // any nominal sampling cadence.
        let reading = tracker.record(1_300, at: stamp(2_000_000_000))
        XCTAssertEqual(reading.availability, .measured)
        XCTAssertEqual(try XCTUnwrap(reading.numericValue), 150, accuracy: 1e-9)
    }

    func testTrackerRateHandlesSubSecondElapsed() throws {
        var tracker = try CounterRateTracker(maxGap: .seconds(5))
        _ = tracker.record(10, at: stamp(0))
        let reading = tracker.record(35, at: stamp(500_000_000))
        // 25 units over 0.5 s -> 50/s.
        XCTAssertEqual(try XCTUnwrap(reading.numericValue), 50, accuracy: 1e-9)
    }

    func testTrackerCounterResetIsGapThenRebases() throws {
        var tracker = try CounterRateTracker(maxGap: .seconds(5))
        _ = tracker.record(500, at: stamp(0))
        let reset = tracker.record(50, at: stamp(1_000_000_000))
        XCTAssertEqual(reset.availability, .gap)
        XCTAssertNil(reset.numericValue)
        let resumed = tracker.record(70, at: stamp(2_000_000_000))
        XCTAssertEqual(try XCTUnwrap(resumed.numericValue), 20, accuracy: 1e-9)
    }

    func testTrackerClockChangeIsGapThenRebases() throws {
        var tracker = try CounterRateTracker(maxGap: .seconds(5))
        let newClock = UUID()
        _ = tracker.record(100, at: stamp(0))
        let changed = tracker.record(900, at: stamp(1_000_000_000, clockID: newClock))
        XCTAssertEqual(changed.availability, .gap)
        let resumed = tracker.record(950, at: stamp(3_000_000_000, clockID: newClock))
        XCTAssertEqual(try XCTUnwrap(resumed.numericValue), 25, accuracy: 1e-9)
    }

    func testTrackerMissedIntervalBeyondMaxGapIsGap() throws {
        var tracker = try CounterRateTracker(maxGap: .seconds(2))
        _ = tracker.record(0, at: stamp(0))
        let missed = tracker.record(600, at: stamp(3_000_000_000))
        XCTAssertEqual(missed.availability, .gap)
        // Exactly at the bound still counts as continuous.
        var edge = try CounterRateTracker(maxGap: .seconds(2))
        _ = edge.record(0, at: stamp(0))
        XCTAssertEqual(
            edge.record(200, at: stamp(2_000_000_000)).availability,
            .measured
        )
    }

    func testTrackerNonPositiveElapsedIsGap() throws {
        var tracker = try CounterRateTracker(maxGap: .seconds(5))
        _ = tracker.record(100, at: stamp(1_000_000_000))
        XCTAssertEqual(
            tracker.record(150, at: stamp(1_000_000_000)).availability, .gap
        )
        var backwards = try CounterRateTracker(maxGap: .seconds(5))
        _ = backwards.record(100, at: stamp(2_000_000_000))
        XCTAssertEqual(
            backwards.record(150, at: stamp(1_000_000_000)).availability, .gap
        )
    }

    func testTrackerRejectsNonPositiveMaxGap() {
        XCTAssertThrowsError(try CounterRateTracker(maxGap: .zero)) {
            XCTAssertEqual(
                $0 as? CounterRateTrackerError, .nonPositiveMaxGap
            )
        }
        XCTAssertThrowsError(try CounterRateTracker(maxGap: .seconds(-1))) {
            XCTAssertEqual(
                $0 as? CounterRateTrackerError, .nonPositiveMaxGap
            )
        }
    }

    func testTrackerResetReturnsToCollecting() throws {
        var tracker = try CounterRateTracker(maxGap: .seconds(5))
        _ = tracker.record(100, at: stamp(0))
        _ = tracker.record(200, at: stamp(1_000_000_000))
        tracker.reset()
        XCTAssertEqual(
            tracker.record(300, at: stamp(2_000_000_000)).availability,
            .collecting
        )
    }

    // MARK: - SampleBuffer

    func testBufferRejectsNonPositiveCapacityBeforeAllocation() {
        for bad in [0, -1, Int.min] {
            XCTAssertThrowsError(try SampleBuffer<Int>(capacity: bad)) {
                XCTAssertEqual(
                    $0 as? SampleBufferError, .invalidCapacity(bad)
                )
            }
        }
    }

    func testBufferAppendsChronologicallyBelowCapacity() throws {
        var buffer = try SampleBuffer<Int>(capacity: 4)
        XCTAssertTrue(buffer.isEmpty)
        buffer.append(1)
        buffer.append(2)
        XCTAssertEqual(buffer.elements, [1, 2])
        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.last, 2)
        XCTAssertFalse(buffer.isFull)
    }

    func testBufferWrapsAndEvictsOldest() throws {
        var buffer = try SampleBuffer<Int>(capacity: 3)
        for value in 1...7 { buffer.append(value) }
        XCTAssertTrue(buffer.isFull)
        XCTAssertEqual(buffer.elements, [5, 6, 7])
        XCTAssertEqual(buffer.last, 7)
        buffer.append(8)
        XCTAssertEqual(buffer.elements, [6, 7, 8])
    }

    func testBufferClearResetsOrderAndCount() throws {
        var buffer = try SampleBuffer<Int>(capacity: 3)
        for value in 1...5 { buffer.append(value) }
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.elements, [])
        XCTAssertNil(buffer.last)
        buffer.append(9)
        buffer.append(10)
        XCTAssertEqual(buffer.elements, [9, 10])
    }
}
