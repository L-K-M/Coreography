import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class NetworkMonitorTests: XCTestCase {
    func testFullWidthCountersAndActualInterfaceIntervals() async throws {
        let baseline = UInt64(1) << 40
        let monitor = try makeMonitor([
            fixture(time: 2, rows: [row(time: 1, received: baseline, sent: baseline)]),
            fixture(time: 5, rows: [row(time: 3, received: baseline + 4096, sent: baseline + 2048)])
        ])
        let first = try await monitor.sample()
        XCTAssertEqual(first.interfaces.first?.receivedBytesPerSecond.availability, .collecting)
        let next = try await monitor.sample()
        XCTAssertEqual(next.interfaces.first?.receivedBytesPerSecond.numericValue, 2048)
        XCTAssertEqual(next.interfaces.first?.sentBytesPerSecond.numericValue, 1024)
        XCTAssertEqual(next.primaryInterface?.name, "en0")
        XCTAssertNil(next.primaryIssue)
    }

    func testPrimarySelectionDoesNotAggregatePhysicalAndTunnelCounters() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1), row(index: 9, name: "utun9", time: 1)]),
            fixture(time: 2, rows: [
                row(time: 2, received: 100), row(index: 9, name: "utun9", time: 2, received: 200)
            ])
        ])
        _ = try await monitor.sample()
        let next = try await monitor.sample()
        XCTAssertEqual(next.interfaces.count, 2)
        let primary = next.interfaces.first { $0.id == next.primaryInterface }
        XCTAssertEqual(primary?.receivedBytesPerSecond.numericValue, 100)
        XCTAssertEqual(next.interfaces.last?.receivedBytesPerSecond.numericValue, 200)
    }

    func testMissingPrimaryKeepsObservedInterfacesWithoutGuessingOne() async throws {
        let monitor = try makeMonitor([fixture(time: 1, rows: [row(time: 1)], primary: nil)])
        let result = try await monitor.sample()
        XCTAssertNil(result.primaryInterface)
        XCTAssertEqual(result.interfaces.count, 1)
        XCTAssertEqual(result.primaryIssue?.availability, .unavailable)
    }

    func testInterfaceIndexReuseDoesNotInheritOldNameCounters() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, received: 9000)]),
            fixture(time: 2, rows: [row(name: "utun9", time: 2, received: 10)], primary: "utun9")
        ])
        let before = try await monitor.sample()
        let after = try await monitor.sample()
        XCTAssertNotEqual(before.interfaces.first?.id, after.interfaces.first?.id)
        XCTAssertEqual(after.interfaces.first?.receivedBytesPerSecond.availability, .collecting)
    }

    func testDownAndMissingInterfacesDropBaselines() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1)]),
            fixture(time: 2, rows: [row(time: 2, state: .down)]),
            fixture(time: 3, rows: [row(time: 3, received: 9000)]),
            fixture(time: 4, rows: []),
            fixture(time: 5, rows: [row(time: 5, received: 10000)])
        ])
        _ = try await monitor.sample()
        let down = try await monitor.sample()
        XCTAssertEqual(down.interfaces.first?.receivedBytesPerSecond.availability, .unavailable)
        let up = try await monitor.sample()
        XCTAssertEqual(up.interfaces.first?.receivedBytesPerSecond.availability, .collecting)
        let missing = try await monitor.sample()
        XCTAssertNil(missing.primaryInterface)
        let returned = try await monitor.sample()
        XCTAssertEqual(returned.interfaces.first?.receivedBytesPerSecond.availability, .collecting)
    }

    func testCounterResetsAndSleepDoNotBecomeTrafficSpikes() async throws {
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1, received: 9000)]),
            fixture(time: 2, rows: [row(time: 2, received: 1)]),
            fixture(time: 3, rows: [row(time: 3, received: 50)], wall: 3600)
        ])
        _ = try await monitor.sample()
        let reset = try await monitor.sample()
        XCTAssertEqual(reset.interfaces.first?.receivedBytesPerSecond.availability, .gap)
        let wake = try await monitor.sample()
        XCTAssertEqual(wake.continuity, .interrupted)
        XCTAssertNil(wake.interfaces.first?.sentBytesPerSecond.numericValue)
    }

    func testEnumerationFailureAndRecoveryHaveExplicitCoverage() async throws {
        let failed = RawNetworkSnapshot(
            clockID: Self.clock, monotonicNanoseconds: 2_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(2), enumeration: .failure(.restricted(code: 1)),
            primaryInterface: .failure(.unavailable(reason: "Fixture"))
        )
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1)]), failed,
            fixture(time: 3, rows: [row(time: 3, received: 1000)])
        ])
        _ = try await monitor.sample()
        let restricted = try await monitor.sample()
        XCTAssertEqual(restricted.enumeration.availability, .restricted)
        XCTAssertNil(restricted.enumeration.numericValue)
        let recovered = try await monitor.sample()
        XCTAssertEqual(recovered.interfaces.first?.receivedBytesPerSecond.availability, .collecting)
    }

    func testInvalidOrDuplicateRowsDoNotInventDetachedZeroTraffic() async throws {
        let sample = fixture(time: 1, rows: [row(name: "", time: 1), row(time: 1), row(time: 1)])
        let result = try await makeMonitor([sample]).sample()
        XCTAssertEqual(result.interfaces.count, 1)
        XCTAssertEqual(result.issues.count, 2)
        XCTAssertNil(result.interfaces.first?.receivedBytesPerSecond.numericValue)
        XCTAssertThrowsError(try JSONDecoder().decode(
            NetworkInterfaceID.self, from: Data(#"{"index":0,"name":"en0"}"#.utf8)
        ))
    }

    func testWallClockRollbackClearsHistoryAndClockChangeLeavesGap() async throws {
        let sample = RawNetworkSnapshot(
            clockID: UUID(), monotonicNanoseconds: 3_000_000_000,
            wallTime: Self.epoch, enumeration: .success(NetworkEnumeration(interfaces: [row(time: 3)])),
            primaryInterface: .success(PrimaryNetworkInterface(name: "en0", family: .ipv4))
        )
        let monitor = try makeMonitor([
            fixture(time: 1, rows: [row(time: 1)]),
            fixture(time: 2, rows: [row(time: 2)], wall: 0), sample
        ])
        _ = try await monitor.sample()
        _ = try await monitor.sample()
        let historyAfterRollback = await monitor.history()
        XCTAssertEqual(historyAfterRollback.count, 1)
        let newClock = try await monitor.sample()
        XCTAssertEqual(newClock.interfaces.first?.sentBytesPerSecond.availability, .gap)
        let history = await monitor.history()
        XCTAssertEqual(history.count, 1)
    }

    func testNativeDriverReturnsRealInterfaceCountersOrExplicitUnsupported() async throws {
        let sample = await NetworkInterfacesDriver().read()
        #if os(macOS)
        let enumeration = try sample.enumeration.get()
        let loopback = try XCTUnwrap(enumeration.interfaces.first { $0.name == "lo0" })
        XCTAssertGreaterThan(loopback.index, 0)
        #else
        switch sample.enumeration {
        case .failure(.unsupportedPlatform): break
        default: XCTFail("Linux must not fabricate macOS interface counters")
        }
        #endif
    }

    private static let clock = UUID(uuidString: "AFAE41C6-793E-4A64-A545-66CFA34571EB")!
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeMonitor(_ samples: [RawNetworkSnapshot]) throws -> NetworkMonitor {
        try NetworkMonitor(driver: FixtureNetworkDriver(samples))
    }

    private func fixture(
        time: UInt64, rows: [RawNetworkInterface], primary: String? = "en0", wall: UInt64? = nil
    ) -> RawNetworkSnapshot {
        RawNetworkSnapshot(
            clockID: Self.clock, monotonicNanoseconds: time * 1_000_000_000,
            wallTime: Self.epoch.addingTimeInterval(Double(wall ?? time)),
            enumeration: .success(NetworkEnumeration(interfaces: rows)),
            primaryInterface: primary.map { .success(PrimaryNetworkInterface(name: $0, family: .ipv4)) }
                ?? .failure(.unavailable(reason: "No primary interface"))
        )
    }

    private func row(
        index: UInt32 = 2, name: String = "en0", time: UInt64,
        received: UInt64 = 0, sent: UInt64 = 0, state: NetworkLinkState = .up
    ) -> RawNetworkInterface {
        RawNetworkInterface(
            index: index, name: name, linkState: state, receivedBytes: received, sentBytes: sent,
            monotonicNanoseconds: time * 1_000_000_000
        )
    }
}

private actor FixtureNetworkDriver: NetworkSampleReading {
    private var samples: [RawNetworkSnapshot]
    init(_ samples: [RawNetworkSnapshot]) { self.samples = samples }
    func read() async -> RawNetworkSnapshot {
        precondition(!samples.isEmpty, "Fixture exhausted")
        return samples.removeFirst()
    }
}
