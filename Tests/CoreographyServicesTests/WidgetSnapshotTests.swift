import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class WidgetSnapshotTests: XCTestCase {
    func testWidgetsTakeTwoReadingsAndUseActualIntervals() async throws {
        let host = WidgetHostDriver(samples: [hostSample(seconds: 0), hostSample(seconds: 2)])
        let network = WidgetNetworkDriver(samples: [networkSample(seconds: 0), networkSample(seconds: 2)])
        let snapshot = try await sampler(host: host, network: network).sample()

        XCTAssertEqual(snapshot.host.cpuPercentOfMachine.numericValue, 25)
        XCTAssertEqual(snapshot.host.cpuPercentOfMachine.availability, .measured)
        XCTAssertEqual(snapshot.host.memoryUsedBytes.availability, .estimated)
        XCTAssertEqual(snapshot.memoryFraction, 0.5)
        XCTAssertEqual(snapshot.host.memory.pressureLevel, .warning)
        XCTAssertEqual(snapshot.host.memory.swapUsedBytes.numericValue, 1024)
        XCTAssertEqual(snapshot.primaryInterface?.id.name, "en0")
        XCTAssertEqual(snapshot.primaryInterface?.receivedBytesPerSecond.numericValue, 2048)
        XCTAssertEqual(snapshot.primaryInterface?.sentBytesPerSecond.numericValue, 1024)
        XCTAssertEqual(snapshot.sampledAt, Self.epoch.addingTimeInterval(2))
        XCTAssertEqual(snapshot.disk, .measured(totalBytes: 1_000, availableBytes: 400))
        let reads = await (host.readCount, network.readCount)
        XCTAssertEqual(reads.0, 2)
        XCTAssertEqual(reads.1, 2)
    }

    func testMissingPrimaryDoesNotSubstituteAnotherInterface() async throws {
        let host = WidgetHostDriver(samples: [hostSample(seconds: 0), hostSample(seconds: 1)])
        let network = WidgetNetworkDriver(samples: [
            networkSample(seconds: 0, primary: .failure(.unavailable(reason: "No default route"))),
            networkSample(seconds: 1, primary: .failure(.unavailable(reason: "No default route")))
        ])
        let snapshot = try await sampler(host: host, network: network).sample()

        XCTAssertFalse(snapshot.network.interfaces.isEmpty)
        XCTAssertNil(snapshot.primaryInterface)
        XCTAssertEqual(snapshot.network.primaryIssue?.reason, "No default route")
        XCTAssertEqual(snapshot.host.cpuPercentOfMachine.numericValue, 25)
    }

    func testUnavailableSourcesKeepReasonsAndNeverBecomeZero() async throws {
        let host = WidgetHostDriver(samples: [0, 1].map {
            hostSample(seconds: $0, failure: .systemCall(operation: "host_statistics", code: 5))
        })
        let network = WidgetNetworkDriver(samples: [0, 1].map {
            RawNetworkSnapshot(
                clockID: Self.clock, monotonicNanoseconds: $0 * Self.nanosecondsPerSecond,
                wallTime: Self.epoch.addingTimeInterval(Double($0)),
                enumeration: .failure(.restricted(code: 1)),
                primaryInterface: .failure(.restricted(code: 1))
            )
        })
        let snapshot = try await sampler(host: host, network: network).sample()

        XCTAssertNil(snapshot.host.cpuPercentOfMachine.numericValue)
        XCTAssertEqual(snapshot.host.cpuPercentOfMachine.reason, "host_statistics failed (5)")
        XCTAssertNil(snapshot.memoryFraction)
        XCTAssertEqual(snapshot.network.enumeration.availability, .restricted)
        XCTAssertNil(snapshot.primaryInterface)
        XCTAssertNotNil(snapshot.network.primaryIssue?.reason)
    }

    func testUnreadableStartupVolumeKeepsItsReason() async throws {
        let host = WidgetHostDriver(samples: [hostSample(seconds: 0), hostSample(seconds: 1)])
        let network = WidgetNetworkDriver(samples: [networkSample(seconds: 0), networkSample(seconds: 1)])
        let snapshot = try await sampler(
            host: host, network: network, volume: .failure(.unavailable("The startup volume reports no capacity"))
        ).sample()

        XCTAssertEqual(snapshot.disk, .unavailable(reason: "The startup volume reports no capacity"))
        XCTAssertNil(snapshot.disk.usedFraction)
        XCTAssertEqual(snapshot.host.cpuPercentOfMachine.numericValue, 25)
    }

    func testInterruptedSampleKeepsGaugesButNotRates() async throws {
        let host = WidgetHostDriver(samples: [hostSample(seconds: 0), hostSample(seconds: 10)])
        let network = WidgetNetworkDriver(samples: [networkSample(seconds: 0), networkSample(seconds: 10)])
        let snapshot = try await sampler(host: host, network: network).sample()

        XCTAssertEqual(snapshot.host.cpuPercentOfMachine.availability, .gap)
        XCTAssertEqual(snapshot.primaryInterface?.receivedBytesPerSecond.availability, .gap)
        XCTAssertNil(snapshot.host.cpuPercentOfMachine.numericValue)
        XCTAssertNil(snapshot.primaryInterface?.receivedBytesPerSecond.numericValue)
        XCTAssertNil(snapshot.primaryInterface?.sentBytesPerSecond.numericValue)
        XCTAssertEqual(snapshot.memoryFraction, 0.5)
    }

    func testCancellationStopsBeforeTheSecondRead() async throws {
        let host = WidgetHostDriver(samples: [hostSample(seconds: 0)])
        let network = WidgetNetworkDriver(samples: [networkSample(seconds: 0)])
        let sampler = try WidgetSampler(
            host: SystemMonitor(driver: host), network: NetworkMonitor(driver: network),
            volumes: VolumeMonitor(driver: WidgetVolumeDriver(result: .failure(.unsupportedPlatform))),
            waitForInterval: { throw CancellationError() }
        )
        do {
            _ = try await sampler.sample()
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {
            let reads = await (host.readCount, network.readCount)
            XCTAssertEqual(reads.0, 1)
            XCTAssertEqual(reads.1, 1)
        }
    }

    func testOfflineHintNamesActivityAndTheMostPressingReading() async throws {
        func hint(
            busy: UInt64, pressure: KernelMemoryPressure = .normal,
            volume: RawVolumeCapacity = RawVolumeCapacity(totalBytes: 1_000_000_000, availableBytes: 500_000_000)
        ) async throws -> String {
            let host = WidgetHostDriver(samples: [0, 1].map { hostSample(seconds: $0, busyPercent: busy, pressure: pressure) })
            let network = WidgetNetworkDriver(samples: [networkSample(seconds: 0), networkSample(seconds: 1)])
            return OfflineHint.text(try await sampler(host: host, network: network, volume: .success(volume)).sample())
        }

        let quiet = try await hint(busy: 5)
        XCTAssertEqual(quiet, "Your Mac is mostly idle, with the CPU at 5%. Memory pressure is normal.")
        let critical = try await hint(busy: 90, pressure: .critical)
        XCTAssertEqual(critical, "Your Mac is busy, with the CPU at 90%. Memory pressure is critical.")
        let full = try await hint(busy: 40, volume: RawVolumeCapacity(totalBytes: 1_000_000_000, availableBytes: 50_000_000))
        XCTAssertTrue(full.hasPrefix("Your Mac is moderately busy, with the CPU at 40%. The startup disk is nearly full, with "))

        let host = WidgetHostDriver(samples: [0, 1].map {
            hostSample(seconds: $0, failure: .systemCall(operation: "host_statistics", code: 5))
        })
        let network = WidgetNetworkDriver(samples: [networkSample(seconds: 0), networkSample(seconds: 1)])
        let unavailable = OfflineHint.text(try await sampler(host: host, network: network).sample())
        XCTAssertEqual(unavailable, "The CPU reading is unavailable.", "with memory unreadable, its .warning pressure is not reported")
    }

    func testNativeSamplerMeasuresOrReportsUnsupportedPlatform() async throws {
        let snapshot = try await WidgetSampler().sample()
        #if os(macOS)
        XCTAssertEqual(snapshot.host.cpuPercentOfMachine.availability, .measured)
        XCTAssertNotNil(snapshot.memoryFraction)
        XCTAssertEqual(snapshot.network.enumeration.availability, .measured)
        XCTAssertNotNil(snapshot.disk.usedFraction)
        #else
        XCTAssertEqual(snapshot.host.cpuPercentOfMachine.availability, .unsupported)
        XCTAssertNil(snapshot.memoryFraction)
        XCTAssertEqual(snapshot.network.enumeration.availability, .unsupported)
        XCTAssertEqual(snapshot.disk, .unavailable(reason: "Volumes need macOS"))
        #endif
    }

    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private static let clock = UUID()
    private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

    private func sampler(
        host: WidgetHostDriver, network: WidgetNetworkDriver,
        volume: Result<RawVolumeCapacity, VolumeCapacityError> = .success(RawVolumeCapacity(totalBytes: 1_000, availableBytes: 400))
    ) throws -> WidgetSampler {
        try WidgetSampler(
            host: SystemMonitor(driver: host), network: NetworkMonitor(driver: network),
            volumes: VolumeMonitor(driver: WidgetVolumeDriver(result: volume)), waitForInterval: {}
        )
    }

    private func hostSample(
        seconds: UInt64, failure: HostDriverError? = nil, busyPercent: UInt64 = 25, pressure: KernelMemoryPressure = .warning
    ) -> RawHostSnapshot {
        RawHostSnapshot(
            clockID: Self.clock, monotonicNanoseconds: seconds * Self.nanosecondsPerSecond,
            wallTime: Self.epoch.addingTimeInterval(Double(seconds)),
            inventory: HostInventory(operatingSystem: "fixture", architecture: "arm64", logicalCPUCount: 8, physicalMemoryBytes: 16 * 4096),
            cpu: failure.map { .failure($0) } ?? .success(ProcessorTicks(
                user: seconds * busyPercent, system: 0, idle: seconds * (100 - busyPercent), nice: 0
            )),
            memory: failure.map { .failure($0) } ?? .success(MemoryPages(
                active: 5, inactive: 0, speculative: 0, wired: 2, compressed: 1,
                compressorContents: 2, purgeable: 0, fileBacked: 0,
                pageIns: 0, swapIns: 0, swapOuts: 0, pageSizeBytes: 4096
            )),
            swap: .success(SwapUsage(totalBytes: 2048, usedBytes: 1024)),
            memoryPressure: .success(pressure), thermalPressure: .success(.nominal)
        )
    }

    private func networkSample(
        seconds: UInt64,
        primary: Result<PrimaryNetworkInterface, NetworkDriverError> = .success(PrimaryNetworkInterface(name: "en0", family: .ipv4))
    ) -> RawNetworkSnapshot {
        RawNetworkSnapshot(
            clockID: Self.clock, monotonicNanoseconds: seconds * Self.nanosecondsPerSecond,
            wallTime: Self.epoch.addingTimeInterval(Double(seconds)),
            enumeration: .success(NetworkEnumeration(interfaces: [
                RawNetworkInterface(
                    index: 1, name: "en0", linkState: .up, receivedBytes: seconds * 2048, sentBytes: seconds * 1024,
                    monotonicNanoseconds: seconds * Self.nanosecondsPerSecond
                ),
                RawNetworkInterface(
                    index: 2, name: "utun0", linkState: .up, receivedBytes: seconds * 9999, sentBytes: seconds * 9999,
                    monotonicNanoseconds: seconds * Self.nanosecondsPerSecond
                )
            ])), primaryInterface: primary
        )
    }
}

private actor WidgetHostDriver: HostSampleReading {
    private var samples: [RawHostSnapshot]
    private(set) var readCount = 0

    init(samples: [RawHostSnapshot]) { self.samples = samples }

    func read() async -> RawHostSnapshot {
        readCount += 1
        return samples.removeFirst()
    }
}

private actor WidgetNetworkDriver: NetworkSampleReading {
    private var samples: [RawNetworkSnapshot]
    private(set) var readCount = 0

    init(samples: [RawNetworkSnapshot]) { self.samples = samples }

    func read() async -> RawNetworkSnapshot {
        readCount += 1
        return samples.removeFirst()
    }
}

private struct WidgetVolumeDriver: VolumeCapacityReading {
    let result: Result<RawVolumeCapacity, VolumeCapacityError>

    func startupVolume() async -> Result<RawVolumeCapacity, VolumeCapacityError> { result }
}
