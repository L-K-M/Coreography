import Foundation
import CoreographyKit

public typealias StoredMetric = HistoryMetric

/// Records the newest system readings and app-ledger intervals to the
/// on-disk Recent tier.
///
/// Samples buffer in memory and flush in one transaction every 30 s, so
/// the store sees about two writes a minute rather than one per sample.
/// A failed write is reported; the buffer is bounded and never grows
/// without limit while the disk is unavailable.
public actor HistoryRecorder {
    static let flushInterval: TimeInterval = 30
    private static let bufferLimit = 4096
    /// Over two hours of two-second process intervals.
    private static let ledgerBufferLimit = 4096

    private let store: HistoryStore
    private var buffer: [HistorySample] = []
    private var ledgerBuffer: [LedgerInterval] = []
    private var lastFlush: Date?
    /// Readings from before the last deletion are deleted history, even
    /// when a task carrying them arrives after it.
    private var deletedThrough: Date?
    public private(set) var lastError: String?

    init(store: HistoryStore) { self.store = store }

    /// The default store in Application Support; nil with a reason when it cannot open.
    public static func makeDefault() -> (recorder: HistoryRecorder?, error: String?) {
        do {
            return (HistoryRecorder(store: try HistoryStore()), nil)
        } catch HistoryStoreError.storage(let reason) {
            return (nil, reason)
        } catch {
            return (nil, "\(error)")
        }
    }

    func record(_ samples: [HistorySample], at now: Date) async {
        buffer.append(contentsOf: samples.filter { isAfterDeletion($0.time) })
        if buffer.count > Self.bufferLimit { buffer.removeFirst(buffer.count - Self.bufferLimit) }
        guard let lastFlush else {
            self.lastFlush = now
            return
        }
        guard now.timeIntervalSince(lastFlush) >= Self.flushInterval else { return }
        await flush(now: now)
    }

    /// Buffer one ledger interval; it is written with the next sample batch.
    func recordLedger(_ interval: LedgerInterval) {
        guard isAfterDeletion(interval.end) else { return }
        ledgerBuffer.append(interval)
        if ledgerBuffer.count > Self.ledgerBufferLimit { ledgerBuffer.removeFirst(ledgerBuffer.count - Self.ledgerBufferLimit) }
    }

    /// Take the batch out before writing: records arriving while the write
    /// awaits go to the next batch instead of being cleared with this one.
    /// A failed batch goes back in front, within the buffer limits, except
    /// what a deletion during the write covered.
    func flush(now: Date = Date()) async {
        lastFlush = now
        guard !buffer.isEmpty || !ledgerBuffer.isEmpty else { return }
        let samples = buffer
        let ledger = ledgerBuffer
        buffer.removeAll()
        ledgerBuffer.removeAll()
        do {
            try await store.append(samples, ledger: ledger, now: now)
            lastError = nil
        } catch {
            // deleteAll can run while this write awaits; what it covered must not return.
            buffer = Array((samples.filter { isAfterDeletion($0.time) } + buffer).suffix(Self.bufferLimit))
            ledgerBuffer = Array((ledger.filter { isAfterDeletion($0.end) } + ledgerBuffer).suffix(Self.ledgerBufferLimit))
            if case HistoryStoreError.storage(let reason) = error { lastError = reason } else { lastError = "\(error)" }
        }
    }

    public func deleteAll(now: Date = Date()) async throws {
        deletedThrough = now
        buffer.removeAll()
        ledgerBuffer.removeAll()
        try await store.deleteAll()
    }

    private func isAfterDeletion(_ time: Date) -> Bool {
        deletedThrough.map { time > $0 } ?? true
    }

    func samples(_ metric: HistoryMetric, from start: Date, to end: Date) async throws -> [HistorySample] {
        try await store.samples(metric, from: start, to: end)
    }

    func setRetention(_ plan: RetentionPlan) async {
        await store.setRetention(plan)
    }

    func size() async throws -> Int64 {
        try await store.size()
    }

    func rollups(_ metric: HistoryMetric, tier: RollupTier = .day, from start: Date, to end: Date) async throws -> [HistoryRollup] {
        try await store.rollups(metric, tier: tier, from: start, to: end)
    }

    func appDays(from start: Date, to end: Date) async throws -> [AppDayTotal] {
        try await store.appDays(from: start, to: end)
    }

    func ledger(from start: Date, to end: Date) async throws -> [LedgerInterval] {
        try await store.ledger(from: start, to: end)
    }
}

/// The source behind each stored series at the last recording. Samples
/// carry no source, so a change is stored as a gap: the stored line then
/// breaks where the live one does (a new primary interface, storage
/// device, GPU or hottest sensor), at the cost of that one reading.
struct RecordedSources: Equatable, Sendable {
    var interface: CapturedInterfaceID?
    var storage: CapturedStorageID?
    var gpu: GPUDeviceID?
    var sensor: String?

    /// Note the current source; true when it replaces a different one.
    mutating func changed<ID: Equatable>(_ source: WritableKeyPath<RecordedSources, ID?>, to id: ID) -> Bool {
        defer { self[keyPath: source] = id }
        return self[keyPath: source].map { $0 != id } ?? false
    }
}

/// Turn the newest frames into stored readings, using the same source
/// choices as the window: the primary interface, an automatic storage
/// device, the only GPU and the qualified system-power source.
enum HistorySamples {
    static func latest(
        host: CapturedSnapshot?, network: CapturedNetwork?, disks: CapturedDisks?, gpu: CapturedGPU?,
        power: CapturedPower?, sensors: CapturedSensors?, silicon: CapturedSilicon?, sources: inout RecordedSources
    ) -> [HistorySample] {
        var samples: [HistorySample] = []
        func add(_ metric: HistoryMetric, _ reading: MetricReading?, at time: Date?) {
            guard let reading, let time else { return }
            samples.append(HistorySample(metric: metric, time: time, value: reading.numericValue, availability: reading.availability))
        }
        func gap(_ metrics: HistoryMetric..., at time: Date) {
            samples += metrics.map { HistorySample(metric: $0, time: time, value: nil, availability: .gap) }
        }
        if let host {
            let time = host.stamp.wallTime
            add(.cpu, host.cpuPercentOfMachine, at: time)
            add(.memoryUsed, host.memoryUsedBytes, at: time)
            add(.memoryApp, host.memory.appBytes, at: time)
            add(.memoryWired, host.memory.wiredBytes, at: time)
            add(.memoryCompressed, host.memory.compressedBytes, at: time)
            add(.memoryCached, host.memory.cachedBytes, at: time)
            add(.memoryPressure, host.memory.pressure, at: time)
            add(.swapUsed, host.memory.swapUsedBytes, at: time)
            add(.thermalPressure, host.thermalPressure, at: time)
        }
        if let network, let primary = network.interfaces.first(where: { $0.id == network.primaryInterface }) {
            if sources.changed(\.interface, to: primary.id) {
                gap(.networkReceived, .networkSent, at: primary.stamp.wallTime)
            } else {
                add(.networkReceived, primary.receivedBytesPerSecond, at: primary.stamp.wallTime)
                add(.networkSent, primary.sentBytesPerSecond, at: primary.stamp.wallTime)
            }
        }
        if let disks, disks.devices.count == 1, disks.issues.isEmpty, !disks.enumerationTruncated, let device = disks.devices.first {
            if sources.changed(\.storage, to: device.id) {
                gap(.diskRead, .diskWritten, at: device.stamp.wallTime)
            } else {
                add(.diskRead, device.readBytesPerSecond, at: device.stamp.wallTime)
                add(.diskWritten, device.writtenBytesPerSecond, at: device.stamp.wallTime)
            }
        }
        // With two GPUs the first one can change from sample to sample, so only a lone GPU is recorded.
        if let gpu, gpu.devices.count == 1, let device = gpu.devices.first {
            if sources.changed(\.gpu, to: device.id) {
                gap(.gpuBusy, at: gpu.stamp.wallTime)
            } else {
                add(.gpuBusy, device.utilizationPercent, at: gpu.stamp.wallTime)
            }
        }
        // Cluster activity and frequency are stored per tier kind, not per
        // cluster: Pro, Max and Ultra chips carry several clusters of a kind.
        // No silicon frame, or one without the kind (Intel, VM, IOReport
        // unavailable), writes nothing, so the series gaps rather than reads 0.
        if let silicon {
            let time = silicon.stamp.wallTime
            for (kind, active, frequency) in Self.clusterKinds {
                add(active, clusterMean(silicon.cpuTiers, kind: kind, \.activePercent), at: time)
                add(frequency, clusterMean(silicon.cpuTiers, kind: kind, \.frequencyMHz), at: time)
            }
        }
        if let power { add(.batteryCharge, power.batteryChargePercent, at: power.stamp.wallTime) }
        if let sensors {
            if let hottest = sensors.hottest, sources.changed(\.sensor, to: hottest.key) {
                gap(.hottestCelsius, at: sensors.stamp.wallTime)
            } else {
                add(.hottestCelsius, sensors.hottest?.celsius, at: sensors.stamp.wallTime)
            }
        }
        // The window's choice: the SMC rail when it reads, else the power source's draw, else why neither does.
        if let sensors, sensors.systemPowerWatts.numericValue != nil {
            add(.systemPower, sensors.systemPowerWatts, at: sensors.stamp.wallTime)
        } else if let power {
            add(.systemPower, power.systemPowerWatts, at: power.stamp.wallTime)
        } else if let sensors {
            add(.systemPower, sensors.systemPowerWatts, at: sensors.stamp.wallTime)
        }
        return samples
    }

    /// (kind, activity metric, frequency metric): E feeds the efficiency
    /// series and P the performance one. The M tier of newer chips has no
    /// series of its own yet and is left out.
    private static let clusterKinds: [(CPUTierKind, HistoryMetric, HistoryMetric)] = [
        (.e, .efficiencyClusterActivePercent, .efficiencyClusterFrequencyMHz),
        (.p, .performanceClusterActivePercent, .performanceClusterFrequencyMHz)
    ]

    private static let clusterMeanMethod = "Core-weighted mean of the kind's clusters"

    /// One stored reading per tier kind: the mean across the kind's clusters,
    /// weighted by each entry's core count (0 counts as 1). A frame carries
    /// one entry per kind today, so the weighting only matters if several
    /// appear. A kind absent from the frame gives no reading at all.
    static func clusterMean(
        _ tiers: [CPUTierReading], kind: CPUTierKind, _ reading: KeyPath<CPUTierReading, MetricReading>
    ) -> MetricReading? {
        let members = tiers.filter { $0.kind == kind }
        guard let first = members.first else { return nil }
        // A lone cluster's entry is the kind's reading and keeps its own
        // availability; only a fold of several stores as estimated.
        guard members.count > 1 else { return first[keyPath: reading] }
        let weighted = members.compactMap { tier -> (value: Double, cores: Int)? in
            guard let value = tier[keyPath: reading].numericValue else { return nil }
            return (value, max(tier.cores, 1))
        }
        // With every entry valueless, the first's state stands for the kind's.
        guard !weighted.isEmpty else { return first[keyPath: reading] }
        let cores = weighted.reduce(0) { $0 + $1.cores }
        let mean = weighted.reduce(0.0) { $0 + $1.value * Double($1.cores) } / Double(cores)
        let head = first[keyPath: reading]
        // A folded mean is derived, so it stores as estimated whatever the entries carried.
        return try? .estimated(mean, method: Self.clusterMeanMethod, source: head.source)
    }
}
