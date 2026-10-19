import Foundation
import CoreographyDrivers

/// A CPU core tier as IOReport names its cores: ECPU, MCPU or PCPU, lowest
/// performance first. M1-M4 have E and P; M5 Pro and Max have M and P;
/// M6 has all three. The letter is IOReport's, not a marketing name.
public enum CPUTierKind: String, Codable, Comparable, CaseIterable, Sendable {
    case e = "E"
    case m = "M"
    case p = "P"

    public static func < (lhs: CPUTierKind, rhs: CPUTierKind) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// "ECPU0", "PACC0_MCPU3" and "DIE_1_PCPU1_CPU0" name cores of a tier.
    static func of(channel: String) -> CPUTierKind? {
        if channel.contains("PCPU") { return .p }
        if channel.contains("MCPU") { return .m }
        if channel.contains("ECPU") { return .e }
        return nil
    }
}

/// One CPU tier over the interval: how busy its cores were and at what
/// frequency, from performance-state residency and the DVFS table.
public struct CPUTierReading: Codable, Equatable, Sendable {
    public let kind: CPUTierKind
    public let cores: Int
    /// Mean active residency of the tier's cores, 0-100.
    public let activePercent: MetricReading
    /// Residency-weighted mean frequency while active, in MHz.
    public let frequencyMHz: MetricReading
}

public struct SiliconSnapshot: Identifiable, Codable, Sendable {
    public let id: UUID
    public let stamp: SampleStamp
    public let cpuPowerWatts: MetricReading
    public let gpuPowerWatts: MetricReading
    public let anePowerWatts: MetricReading
    public let dramPowerWatts: MetricReading
    public let cpuTiers: [CPUTierReading]
    public let gpuActivePercent: MetricReading
    public let gpuFrequencyMHz: MetricReading
    public let continuity: SamplingContinuity

    /// The highest tier, whose frequency matters most for responsiveness.
    public var topTier: CPUTierReading? { cpuTiers.max { $0.kind < $1.kind } }
}

/// Apple Silicon power and frequency from IOReport (plan: M2 silicon
/// providers). Energy counter deltas over the real elapsed interval give
/// modeled watts; residencies give activity and frequency. All of it is
/// estimated: the energy model is Apple's, and S1 still has to compare it
/// with `powermetrics` on real chips.
public actor SiliconMonitor {
    static let energyMethod = "ioreport-energy-model"
    static let residencyMethod = "ioreport-dvfs-residency"
    private static let source = MetricSource(provider: "silicon", driver: "IOReport", channel: "Energy Model, CPU/GPU Stats")
    /// CPU busy above this while the energy counter stands still is evidence of a frozen counter.
    private static let frozenActivePercent = 10.0
    /// Consecutive such intervals before the counter is declared frozen.
    private static let frozenIntervals = 5

    private let driver: any SiliconReportReading
    private var tables: Result<FrequencyTables, SiliconDriverError>?
    private var continuity: ContinuityTracker
    private var buffer: SampleBuffer<SiliconSnapshot>
    private var stillIntervals = 0

    public init() throws { try self.init(driver: SiliconReportDriver(), historyCapacity: LiveHistory.capacity) }

    init(driver: any SiliconReportReading, maximumGap: Duration = .seconds(3), historyCapacity: Int = 60) throws {
        self.driver = driver
        self.continuity = ContinuityTracker(maximumGap: maximumGap)
        self.buffer = try SampleBuffer(capacity: historyCapacity)
    }

    public func reset() {
        continuity.reset()
        buffer.removeAll()
        stillIntervals = 0
    }

    public func history() -> [SiliconSnapshot] { buffer.elements }

    public func sample() async throws -> SiliconSnapshot {
        if tables == nil { tables = await driver.frequencyTables().map(FrequencyTables.init) }
        let raw = await driver.read()
        try Task.checkCancellation()
        let stamp = SampleStamp(clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds, wallTime: raw.wallTime)
        let outcome = continuity.record(stamp)
        if outcome == .discontinuous { buffer.removeAll() }

        let snapshot = try decode(raw, stamp: stamp, interrupted: outcome != .continuous)
        buffer.append(snapshot)
        return snapshot
    }

    private func decode(_ raw: RawSiliconSample, stamp: SampleStamp, interrupted: Bool) throws -> SiliconSnapshot {
        func snapshot(_ all: MetricReading, tiers: [CPUTierReading] = []) -> SiliconSnapshot {
            SiliconSnapshot(
                id: UUID(), stamp: stamp, cpuPowerWatts: all, gpuPowerWatts: all, anePowerWatts: all, dramPowerWatts: all,
                cpuTiers: tiers, gpuActivePercent: all, gpuFrequencyMHz: all,
                continuity: interrupted ? .interrupted : .continuous
            )
        }

        let channels: [RawReportChannel]
        switch raw.channels {
        case .failure(let error): return snapshot(try Self.missing(error))
        case .success(let read): channels = read
        }
        guard let interval = raw.intervalNanoseconds, interval > 0 else { return snapshot(.collecting(source: Self.source)) }
        let seconds = Double(interval) / 1e9

        let tiers = try cpuTiers(channels)
        let energy = SiliconDecoding.energy(channels, seconds: seconds)
        let busiest = tiers.compactMap(\.activePercent.numericValue).max() ?? 0
        let cpu = try power(energy.cpu, frozenCheck: busiest)
        let gpuChannel = channels.first { $0.group == "GPU Stats" && $0.subgroup == "GPU Performance States" && $0.name == "GPUPH" }
        let gpu = try gpuReadings(gpuChannel)

        return SiliconSnapshot(
            id: UUID(), stamp: stamp, cpuPowerWatts: cpu, gpuPowerWatts: try power(energy.gpu),
            anePowerWatts: try power(energy.ane), dramPowerWatts: try power(energy.dram),
            cpuTiers: tiers, gpuActivePercent: gpu.active, gpuFrequencyMHz: gpu.frequency,
            continuity: interrupted ? .interrupted : .continuous
        )
    }

    /// A counter that stands still while the CPU is busy is frozen, not idle
    /// (plan: a confirmed frozen source is unusable, not an estimated zero).
    private func power(_ watts: Double?, frozenCheck busiest: Double? = nil) throws -> MetricReading {
        guard let watts else {
            return try .unavailable(reason: "IOReport publishes no matching energy channel", source: Self.source)
        }
        if let busiest {
            stillIntervals = watts == 0 && busiest >= Self.frozenActivePercent ? stillIntervals + 1 : 0
            if stillIntervals >= Self.frozenIntervals {
                return try .unavailable(reason: "IOReport energy counters are not advancing while the CPU is busy", source: Self.source)
            }
        }
        return try .estimated(watts, method: Self.energyMethod, source: Self.source)
    }

    private func cpuTiers(_ channels: [RawReportChannel]) throws -> [CPUTierReading] {
        let cores = channels.filter { $0.group == "CPU Stats" && $0.subgroup == "CPU Core Performance States" }
        let byTier = Dictionary(grouping: cores.compactMap { core in CPUTierKind.of(channel: core.name).map { ($0, core) } }) { $0.0 }
        let kinds = byTier.keys.sorted()
        return try kinds.map { kind in
            let members = byTier[kind]!.map(\.1)
            let table = tableResult(for: kind, among: kinds)
            let usage = members.compactMap { core -> SiliconDecoding.Usage? in
                guard case .success(let frequencies) = table else { return SiliconDecoding.activity(core.states) }
                return SiliconDecoding.usage(core.states, frequencies: frequencies) ?? SiliconDecoding.activity(core.states)
            }
            let active = usage.isEmpty ? nil : usage.map(\.activeRatio).reduce(0, +) / Double(usage.count) * 100
            return CPUTierReading(
                kind: kind, cores: members.count,
                activePercent: try active.map { try .estimated($0, method: Self.residencyMethod, source: Self.source) }
                    ?? .unavailable(reason: "No residency was reported", source: Self.source),
                frequencyMHz: try frequency(usage, table: table)
            )
        }
    }

    private func gpuReadings(_ channel: RawReportChannel?) throws -> (active: MetricReading, frequency: MetricReading) {
        guard let channel else {
            let missing = try MetricReading.unavailable(reason: "IOReport publishes no GPU performance states", source: Self.source)
            return (missing, missing)
        }
        let table = gpuTable
        let usage: SiliconDecoding.Usage?
        if case .success(let frequencies) = table {
            usage = SiliconDecoding.usage(channel.states, frequencies: frequencies) ?? SiliconDecoding.activity(channel.states)
        } else {
            usage = SiliconDecoding.activity(channel.states)
        }
        guard let usage else {
            let missing = try MetricReading.unavailable(reason: "The GPU reported no residency", source: Self.source)
            return (missing, missing)
        }
        return (
            try .estimated(usage.activeRatio * 100, method: Self.residencyMethod, source: Self.source),
            try frequency([usage], table: table)
        )
    }

    private func frequency(_ usage: [SiliconDecoding.Usage], table: Result<[Double], SiliconDriverError>) throws -> MetricReading {
        switch table {
        case .failure(let error):
            return try Self.missing(error)
        case .success:
            let weighted = usage.filter { $0.meanMHz != nil }
            let active = weighted.map(\.activeResidency).reduce(0, +)
            guard !weighted.isEmpty else {
                return try .unavailable(reason: "The frequency table does not fit the reported states", source: Self.source)
            }
            guard active > 0 else { return .gap(reason: "Idle for the whole interval", source: Self.source) }
            let mean = weighted.map { $0.activeResidency * ($0.meanMHz ?? 0) }.reduce(0, +) / active
            return try .estimated(mean, method: Self.residencyMethod, source: Self.source)
        }
    }

    private func tableResult(for kind: CPUTierKind, among kinds: [CPUTierKind]) -> Result<[Double], SiliconDriverError> {
        switch tables {
        case .none: .failure(.unavailable("Frequency tables were not read"))
        case .failure(let error): .failure(error)
        case .success(let loaded): loaded.cpu(kind, among: kinds)
        }
    }

    private var gpuTable: Result<[Double], SiliconDriverError> {
        switch tables {
        case .none: .failure(.unavailable("Frequency tables were not read"))
        case .failure(let error): .failure(error)
        case .success(let loaded): loaded.gpu
        }
    }

    private static func missing(_ error: SiliconDriverError) throws -> MetricReading {
        switch error {
        case .unsupportedPlatform: .unsupported(reason: "Apple Silicon telemetry requires macOS", source: source)
        case .virtualMachine: .unsupported(reason: "A virtual machine has no power counters or frequency tables", source: source)
        case .unavailable(let reason): try .unavailable(reason: reason, source: source)
        }
    }
}

/// The power manager's tables in MHz, assigned to tiers (chip profile as data).
struct FrequencyTables: Sendable {
    /// M1-M4 keep the lowest tier at 1 and the highest at 5; M5 and later
    /// name their tables in `acc-clusters` instead.
    static let legacyLowest = "voltage-states1-sram"
    static let legacyHighest = "voltage-states5-sram"
    static let gpuKey = "voltage-states9"

    let tables: [String: [Double]]
    /// Table keys from the lowest tier to the highest, from `acc-clusters`.
    let clusterKeys: [String]

    init(_ raw: RawFrequencyTables) {
        tables = raw.tables.compactMapValues(SiliconDecoding.megahertz)
        clusterKeys = raw.clusters.sorted { $0.type < $1.type }.map { "voltage-states\($0.tableIndex)-sram" }
    }

    func cpu(_ kind: CPUTierKind, among kinds: [CPUTierKind]) -> Result<[Double], SiliconDriverError> {
        guard let position = kinds.firstIndex(of: kind) else { return .failure(.unavailable("Unknown CPU tier")) }
        // Tiers and tables pair from the top: the highest tier takes the highest table.
        let fromTop = kinds.count - 1 - position
        // M1-M4 keys first, as macmon reads them; acc-clusters otherwise.
        if kinds.count <= 2, let table = tables[fromTop == 0 && kinds.count == 2 ? Self.legacyHighest : Self.legacyLowest] {
            return .success(table)
        }
        if clusterKeys.count >= kinds.count, let table = tables[clusterKeys[clusterKeys.count - 1 - fromTop]] {
            return .success(table)
        }
        return .failure(.unavailable("No frequency table is known for the \(kind.rawValue) cores of this chip"))
    }

    /// The GPU table's first entry belongs to its OFF state.
    var gpu: Result<[Double], SiliconDriverError> {
        guard let table = tables[Self.gpuKey], table.count > 1 else {
            return .failure(.unavailable("The power manager publishes no GPU frequency table"))
        }
        return .success(Array(table.dropFirst()))
    }
}

/// Pure decoding rules for IOReport deltas.
enum SiliconDecoding {
    /// States before the active ones: CPUs list IDLE or DOWN, IDLE; the GPU OFF.
    private static let inactiveStates: Set<String> = ["IDLE", "DOWN", "OFF"]
    private static let joulesPerUnit: [String: Double] = ["mJ": 1e-3, "uJ": 1e-6, "nJ": 1e-9]
    /// No Apple Silicon table tops out below this, so a smaller reading means another unit.
    private static let minimumPlausibleMHz = 200.0
    private static let maximumPlausibleMHz = 10_000.0

    struct Energy: Equatable {
        var cpu: Double?
        var gpu: Double?
        var ane: Double?
        var dram: Double?
    }

    struct Usage: Equatable {
        let activeRatio: Double
        let activeResidency: Double
        /// nil when no table fit the states.
        let meanMHz: Double?
    }

    /// Watts per block. "CPU Energy" or "DIE_0_CPU Energy"; "GPU Energy";
    /// "ANE", "ANE0" or "ANE0_1"; "DRAM…". Other channels (cluster or SRAM
    /// subtotals) would double count and are left out.
    static func energy(_ channels: [RawReportChannel], seconds: Double) -> Energy {
        var result = Energy()
        for channel in channels where channel.group == "Energy Model" {
            guard let value = channel.value, let scale = joulesPerUnit[channel.unit], seconds > 0 else { continue }
            let watts = Double(value) * scale / seconds
            if channel.name.hasSuffix("CPU Energy") { result.cpu = (result.cpu ?? 0) + watts }
            else if channel.name == "GPU Energy" { result.gpu = (result.gpu ?? 0) + watts }
            else if channel.name.hasPrefix("ANE") { result.ane = (result.ane ?? 0) + watts }
            else if channel.name.hasPrefix("DRAM") { result.dram = (result.dram ?? 0) + watts }
        }
        return result
    }

    /// Active share and the residency-weighted frequency, when the table fits:
    /// a frequency for each active state, at most.
    static func usage(_ states: [RawReportState], frequencies: [Double]) -> Usage? {
        guard let offset = states.firstIndex(where: { !inactiveStates.contains($0.name) }),
              !frequencies.isEmpty, states.count > frequencies.count, states.count - offset >= frequencies.count else { return nil }
        let active = states[offset..<(offset + frequencies.count)].map { Double(max($0.residency, 0)) }
        let total = states.map { Double(max($0.residency, 0)) }.reduce(0, +)
        let activeSum = active.reduce(0, +)
        guard total > 0 else { return nil }
        let mean = activeSum > 0 ? zip(active, frequencies).map { $0 * $1 }.reduce(0, +) / activeSum : nil
        return Usage(activeRatio: activeSum / total, activeResidency: activeSum, meanMHz: mean)
    }

    /// Active share without a frequency table.
    static func activity(_ states: [RawReportState]) -> Usage? {
        let total = states.map { Double(max($0.residency, 0)) }.reduce(0, +)
        guard total > 0 else { return nil }
        let active = states.filter { !inactiveStates.contains($0.name) }.map { Double(max($0.residency, 0)) }.reduce(0, +)
        return Usage(activeRatio: active / total, activeResidency: active, meanMHz: nil)
    }

    /// Hertz (M1-M3) or kilohertz (M4 and later) to MHz, chosen by which
    /// gives a plausible top frequency; nil when neither does.
    static func megahertz(_ raw: [UInt32]) -> [Double]? {
        guard let top = raw.max().map(Double.init), top > 0 else { return nil }
        for divisor in [1e6, 1e3] where (minimumPlausibleMHz...maximumPlausibleMHz).contains(top / divisor) {
            return raw.map { Double($0) / divisor }
        }
        return nil
    }
}
