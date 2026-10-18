import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class SiliconMonitorTests: XCTestCase {
    func testEnergyBecomesWattsPerBlockWithoutDoubleCounting() {
        let channels = [
            energy("DIE_0_CPU Energy", 2_000, "mJ"), energy("DIE_1_CPU Energy", 1_000, "mJ"),
            energy("ECPU", 500, "mJ"), energy("GPU Energy", 3_000_000_000, "nJ"), energy("GPU SRAM", 1, "mJ"),
            energy("ANE0", 250_000, "uJ"), energy("DRAM", 400, "mJ"), energy("Odd", 1, "kJ")
        ]
        XCTAssertEqual(
            SiliconDecoding.energy(channels, seconds: 2),
            SiliconDecoding.Energy(cpu: 1.5, gpu: 1.5, ane: 0.125, dram: 0.2),
            "cluster and SRAM subtotals are not added again; an unknown unit is skipped"
        )
        XCTAssertNil(SiliconDecoding.energy([], seconds: 1).cpu, "no channel is not zero watts")
    }

    func testResidencyGivesActiveShareAndWeightedFrequency() throws {
        let states = [state("DOWN", 10), state("IDLE", 40), state("V0P5", 25), state("V1P4", 25)]
        let usage = try XCTUnwrap(SiliconDecoding.usage(states, frequencies: [600, 1200]))
        XCTAssertEqual(usage.activeRatio, 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(usage.meanMHz), 900, accuracy: 1e-9)
        XCTAssertNil(SiliconDecoding.usage(states, frequencies: [600, 1200, 1800]), "a longer table does not fit")
        XCTAssertNil(SiliconDecoding.usage([state("IDLE", 1)], frequencies: [600]))

        let idle = try XCTUnwrap(SiliconDecoding.usage([state("IDLE", 100), state("V0P5", 0)], frequencies: [600]))
        XCTAssertEqual(idle.activeRatio, 0)
        XCTAssertNil(idle.meanMHz, "an idle core has no frequency, not the lowest one")
    }

    func testTablesInHertzOrKilohertzAreScaledByPlausibility() {
        XCTAssertEqual(SiliconDecoding.megahertz([600_000_000, 3_228_000_000]), [600, 3228], "M1-M3 store hertz")
        XCTAssertEqual(SiliconDecoding.megahertz([600_000, 4_512_000]), [600, 4512], "M4 and later store kilohertz")
        XCTAssertNil(SiliconDecoding.megahertz([5, 9]))
        XCTAssertNil(SiliconDecoding.megahertz([]))
    }

    func testTiersTakeLegacyTablesOrAccClustersFromTheTop() {
        let legacy = FrequencyTables(RawFrequencyTables(
            tables: ["voltage-states1-sram": [600_000_000, 2_064_000_000], "voltage-states5-sram": [600_000_000, 3_228_000_000]],
            clusters: []
        ))
        XCTAssertEqual(try legacy.cpu(.e, among: [.e, .p]).get().last, 2064)
        XCTAssertEqual(try legacy.cpu(.p, among: [.e, .p]).get().last, 3228)
        XCTAssertThrowsError(try legacy.cpu(.m, among: [.e, .m, .p]).get(), "three tiers need acc-clusters")

        let discovered = FrequencyTables(RawFrequencyTables(
            tables: ["voltage-states3-sram": [1_000_000, 2_000_000], "voltage-states23-sram": [1_000_000, 4_600_000]],
            clusters: [RawClusterEntry(tableIndex: 23, type: 2), RawClusterEntry(tableIndex: 3, type: 1)]
        ))
        XCTAssertEqual(try discovered.cpu(.m, among: [.m, .p]).get().last, 2000)
        XCTAssertEqual(try discovered.cpu(.p, among: [.m, .p]).get().last, 4600)
        XCTAssertThrowsError(try discovered.gpu.get(), "no GPU table, no GPU frequency")
    }

    func testMonitorCollectsFirstThenEstimatesEveryBlock() async throws {
        let driver = Scripted(intervals: [cpuActive(energy: 2_000)])
        let monitor = try SiliconMonitor(driver: driver)
        let first = try await monitor.sample()
        XCTAssertEqual(first.cpuPowerWatts.availability, .collecting, "the first read is only a baseline")

        let second = try await monitor.sample()
        XCTAssertEqual(second.cpuPowerWatts.numericValue ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(second.cpuPowerWatts.method, SiliconMonitor.energyMethod)
        XCTAssertEqual(second.anePowerWatts.availability, .unavailable, "an absent channel is unavailable, not zero")
        let top = try XCTUnwrap(second.topTier)
        XCTAssertEqual(top.kind, .p)
        XCTAssertEqual(top.cores, 2)
        XCTAssertEqual(top.activePercent.numericValue ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(top.frequencyMHz.numericValue ?? 0, 2400, accuracy: 1e-9, "weighted by each core's active residency")
        XCTAssertEqual(second.cpuTiers.map(\.kind), [.e, .p])
        XCTAssertEqual(second.gpuFrequencyMHz.numericValue ?? 0, 1000, accuracy: 1e-9, "the table's OFF entry is skipped")
        XCTAssertEqual(second.gpuActivePercent.numericValue ?? 0, 25, accuracy: 1e-9)
    }

    func testFrozenEnergyCountersBecomeUnavailableWhileTheCPUIsBusy() async throws {
        let monitor = try SiliconMonitor(driver: Scripted(intervals: Array(repeating: cpuActive(energy: 0), count: 6)))
        _ = try await monitor.sample()
        var readings: [MetricReading] = []
        for _ in 0..<6 { readings.append(try await monitor.sample().cpuPowerWatts) }
        XCTAssertEqual(readings.prefix(4).map(\.availability), Array(repeating: .estimated, count: 4), "a still counter is not proof at once")
        XCTAssertEqual(readings.last?.availability, .unavailable)
        XCTAssertEqual(readings.last?.reason, "IOReport energy counters are not advancing while the CPU is busy")
    }

    func testVirtualMachinesAndOtherPlatformsSayWhy() async throws {
        let vm = try await SiliconMonitor(driver: Scripted(failure: .virtualMachine)).sample()
        XCTAssertEqual(vm.cpuPowerWatts.availability, .unsupported)
        XCTAssertEqual(vm.gpuFrequencyMHz.reason, "A virtual machine has no power counters or frequency tables")

        let missing = try await SiliconMonitor(driver: Scripted(failure: .unavailable("IOReport lists no channels"))).sample()
        XCTAssertEqual(missing.cpuPowerWatts.reason, "IOReport lists no channels")
    }

    // MARK: Fixtures

    private func energy(_ name: String, _ value: Int64, _ unit: String) -> RawReportChannel {
        RawReportChannel(group: "Energy Model", subgroup: "", name: name, unit: unit, value: value, states: [])
    }

    private func state(_ name: String, _ residency: Int64) -> RawReportState {
        RawReportState(name: name, residency: residency)
    }

    private func core(_ name: String, _ states: [RawReportState]) -> RawReportChannel {
        RawReportChannel(group: "CPU Stats", subgroup: "CPU Core Performance States", name: name, unit: "", value: nil, states: states)
    }

    /// Two P cores at 50% active: one at 1800 MHz for 10, one at 3000 MHz for 10 (mean 2400).
    private func cpuActive(energy joules: Int64) -> [RawReportChannel] {
        [
            energy("CPU Energy", joules, "mJ"),
            core("ECPU0", [state("IDLE", 90), state("V0P1", 10), state("V1P0", 0)]),
            core("PCPU0", [state("IDLE", 10), state("V0P1", 10), state("V1P0", 0)]),
            core("PCPU1", [state("IDLE", 10), state("V0P1", 0), state("V1P0", 10)]),
            RawReportChannel(
                group: "GPU Stats", subgroup: "GPU Performance States", name: "GPUPH", unit: "", value: nil,
                states: [state("OFF", 50), state("IDLE", 25), state("P1", 25), state("P2", 0)]
            )
        ]
    }
}

private actor Scripted: SiliconReportReading {
    private let clock = UUID()
    private var intervals: [[RawReportChannel]]
    private let failure: SiliconDriverError?
    private var reads: UInt64 = 0

    init(intervals: [[RawReportChannel]] = [], failure: SiliconDriverError? = nil) {
        self.intervals = intervals
        self.failure = failure
    }

    func read() async -> RawSiliconSample {
        reads += 1
        let channels: Result<[RawReportChannel], SiliconDriverError>
        if let failure { channels = .failure(failure) }
        else if reads == 1 { channels = .success([]) }
        else { channels = .success(intervals.isEmpty ? [] : intervals.removeFirst()) }
        return RawSiliconSample(
            clockID: clock, monotonicNanoseconds: reads * 1_000_000_000, wallTime: Date(timeIntervalSince1970: 1_700_000_000 + Double(reads)),
            intervalNanoseconds: reads == 1 || failure != nil ? nil : 1_000_000_000, channels: channels
        )
    }

    func frequencyTables() async -> Result<RawFrequencyTables, SiliconDriverError> {
        if let failure { return .failure(failure) }
        return .success(RawFrequencyTables(tables: [
            "voltage-states1-sram": [600_000_000, 2_064_000_000],
            "voltage-states5-sram": [1_800_000_000, 3_000_000_000],
            "voltage-states9": [0, 1_000_000_000, 1_398_000_000]
        ], clusters: []))
    }
}
