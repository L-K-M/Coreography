import Foundation
import CoreographyKit

public typealias StoredMetric = HistoryMetric

/// Records the newest system readings to the on-disk Recent tier.
///
/// Samples buffer in memory and flush in one transaction every 30 s, so
/// the store sees about two writes a minute rather than one per sample.
/// A failed write is reported; the buffer is bounded and never grows
/// without limit while the disk is unavailable.
public actor HistoryRecorder {
    static let flushInterval: TimeInterval = 30
    private static let bufferLimit = 4096

    private let store: HistoryStore
    private var buffer: [HistorySample] = []
    private var lastFlush: Date?
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
        buffer.append(contentsOf: samples)
        if buffer.count > Self.bufferLimit { buffer.removeFirst(buffer.count - Self.bufferLimit) }
        guard let lastFlush else {
            self.lastFlush = now
            return
        }
        guard now.timeIntervalSince(lastFlush) >= Self.flushInterval else { return }
        await flush(now: now)
    }

    func flush(now: Date = Date()) async {
        lastFlush = now
        guard !buffer.isEmpty else { return }
        do {
            try await store.append(buffer, now: now)
            buffer.removeAll()
            lastError = nil
        } catch HistoryStoreError.storage(let reason) {
            lastError = reason
        } catch {
            lastError = "\(error)"
        }
    }

    public func deleteAll() async throws {
        buffer.removeAll()
        try await store.deleteAll()
    }

    func samples(_ metric: HistoryMetric, from start: Date, to end: Date) async throws -> [HistorySample] {
        try await store.samples(metric, from: start, to: end)
    }
}

/// Turn the newest frames into stored readings, using the same source
/// choices as the window: the primary interface, an automatic storage
/// device, the first GPU and the qualified system-power source.
enum HistorySamples {
    static func latest(
        host: CapturedSnapshot?, network: CapturedNetwork?, disks: CapturedDisks?, gpu: CapturedGPU?,
        power: CapturedPower?, sensors: CapturedSensors?
    ) -> [HistorySample] {
        var samples: [HistorySample] = []
        func add(_ metric: HistoryMetric, _ reading: MetricReading?, at time: Date?) {
            guard let reading, let time else { return }
            samples.append(HistorySample(metric: metric, time: time, value: reading.numericValue, availability: reading.availability))
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
            add(.networkReceived, primary.receivedBytesPerSecond, at: primary.stamp.wallTime)
            add(.networkSent, primary.sentBytesPerSecond, at: primary.stamp.wallTime)
        }
        if let disks, disks.devices.count == 1, disks.issues.isEmpty, !disks.enumerationTruncated, let device = disks.devices.first {
            add(.diskRead, device.readBytesPerSecond, at: device.stamp.wallTime)
            add(.diskWritten, device.writtenBytesPerSecond, at: device.stamp.wallTime)
        }
        if let gpu { add(.gpuBusy, gpu.devices.first?.utilizationPercent, at: gpu.stamp.wallTime) }
        if let power { add(.batteryCharge, power.batteryChargePercent, at: power.stamp.wallTime) }
        if let sensors {
            add(.hottestCelsius, sensors.hottest?.celsius, at: sensors.stamp.wallTime)
            let rail = sensors.systemPowerWatts
            add(.systemPower, rail.numericValue != nil ? rail : (power?.systemPowerWatts ?? rail), at: sensors.stamp.wallTime)
        }
        return samples
    }
}
