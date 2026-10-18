import Foundation
import CoreographyKit

/// A frozen view of recent data that one question's queries share (plan:
/// a question anchors to one diagnostic snapshot, so follow-up calls never
/// silently mix past and live values).
public struct DiagnosticSnapshot: Sendable {
    public let id: UUID
    public let takenAt: Date
    let host: [CapturedSnapshot]
    let network: [CapturedNetwork]
    let gpu: [CapturedGPU]
    let power: [CapturedPower]
    let sensors: [CapturedSensors]
    let processes: CapturedProcesses?
    let ledger: AppLedger

    init(
        takenAt: Date, host: [CapturedSnapshot], network: [CapturedNetwork], gpu: [CapturedGPU],
        power: [CapturedPower], sensors: [CapturedSensors], processes: CapturedProcesses?, ledger: AppLedger
    ) {
        self.id = UUID()
        self.takenAt = takenAt
        self.host = host
        self.network = network
        self.gpu = gpu
        self.power = power
        self.sensors = sensors
        self.processes = processes
        self.ledger = ledger
    }
}

public enum DiagnosticError: Error, Codable, Equatable, Sendable {
    case invalidArgument(String)
    case rangeTooLarge(maximumSeconds: Int)
    case invalidCursor
    case unavailable(String)
}

/// One reading with its unit and a stable evidence reference.
public struct DiagnosticValue: Codable, Sendable {
    public let unit: String
    public let reading: MetricReading
    public let evidence: String
}

/// A fact the service computed; the model explains it, never the reverse.
public struct DiagnosticSignal: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case cpuSaturated, memoryPressureElevated, swapping, thermalPressureElevated, samplingGap
    }

    public let kind: Kind
    public let detail: String
    public let evidence: String
}

public struct SystemSummary: Codable, Sendable {
    public let snapshotID: UUID
    public let takenAt: Date
    /// The span of host samples the summary covers; nil without samples.
    public let windowStart: Date?
    public let windowEnd: Date?
    public let cpuPercentOfMachine: DiagnosticValue?
    public let cpuMeanPercent: Double?
    public let cpuPeakPercent: Double?
    public let memoryUsedBytes: DiagnosticValue?
    public let memoryPressure: String?
    public let swapUsedBytes: DiagnosticValue?
    public let swapOutBytesPerSecondPeak: Double?
    public let networkReceivedBytesPerSecond: DiagnosticValue?
    public let networkSentBytesPerSecond: DiagnosticValue?
    public let gpuBusyPercent: DiagnosticValue?
    public let systemPowerWatts: DiagnosticValue?
    public let thermalPressure: String?
    public let hottestCelsius: DiagnosticValue?
    public let signals: [DiagnosticSignal]
}

public struct AppActivity: Codable, Sendable {
    public let app: String
    public let value: Double
    public let unit: String
    public let isLowerBound: Bool
}

public struct TopAppsPage: Codable, Sendable {
    public let snapshotID: UUID
    public let metric: DiagnosticTools.ActivityMetric
    public let rows: [AppActivity]
    public let remaining: Int
    /// Continue with this cursor; bound to this snapshot, metric and range.
    public let nextCursor: String?
    public let coveredStart: Date?
    public let coveredEnd: Date?
    public let coverageNote: String
}

public struct MetricHistory: Codable, Sendable {
    public struct Point: Codable, Sendable {
        public let time: Date
        public let value: Double
        /// Points in different segments are separated by a gap.
        public let segment: Int
    }

    public let snapshotID: UUID
    public let metric: DiagnosticTools.HistoryMetric
    public let unit: String
    public let points: [Point]
    /// True when points were reduced to bucket minima and maxima.
    public let decimated: Bool
}

public struct DataSourceStatus: Codable, Sendable {
    public let metric: String
    public let availability: MetricAvailability
    public let source: MetricSource?
    public let reason: String?
}

public struct ProcessDetails: Codable, Sendable {
    public let pid: Int32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64
    public let name: String
    public let app: String
    public let uid: UInt32
    public let cpuPercentOfMachine: MetricReading
    public let memoryFootprintBytes: MetricReading
    public let diskReadBytesPerSecond: MetricReading
    public let diskWriteBytesPerSecond: MetricReading
}

/// The shared, read-only diagnostic contract (plan: one service for the
/// window, CLI, MCP and the optional assistant). Every tool is bounded
/// server-side; nothing exposes paths, arguments or process control.
public enum DiagnosticTools {
    public enum ActivityMetric: String, Codable, Sendable { case cpu, disk }
    public enum HistoryMetric: String, Codable, CaseIterable, Sendable {
        case cpu, memoryUsed, networkReceived, networkSent, gpuBusy, hottestCelsius, systemPower
    }

    public static let maximumRangeSeconds = 3600
    public static let maximumRows = 50
    public static let maximumPoints = 600
    static let summaryWindow: TimeInterval = 60
    private static let saturatedCPUPercent = 85.0

    // MARK: Summary

    public static func summary(_ snapshot: DiagnosticSnapshot) -> SystemSummary {
        let window = recent(snapshot.host, before: snapshot.takenAt) { $0.stamp.wallTime }
        let latest = window.last
        let cpu = window.compactMap(\.cpuPercentOfMachine.numericValue)
        let primary = snapshot.network.last.flatMap { frame in
            frame.interfaces.first { $0.id == frame.primaryInterface }.map { (frame, $0) }
        }
        let sensors = snapshot.sensors.last
        let power = sensors?.systemPowerWatts.numericValue != nil
            ? sensors?.systemPowerWatts : snapshot.power.last?.systemPowerWatts

        return SystemSummary(
            snapshotID: snapshot.id, takenAt: snapshot.takenAt,
            windowStart: window.first?.stamp.wallTime, windowEnd: latest?.stamp.wallTime,
            cpuPercentOfMachine: latest.map { value("%", $0.cpuPercentOfMachine, $0.id) },
            cpuMeanPercent: cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count),
            cpuPeakPercent: cpu.max(),
            memoryUsedBytes: latest.map { value("bytes", $0.memoryUsedBytes, $0.id) },
            memoryPressure: latest?.memory.pressureLevel.map { "\($0)" },
            swapUsedBytes: latest.map { value("bytes", $0.memory.swapUsedBytes, $0.id) },
            swapOutBytesPerSecondPeak: window.compactMap(\.memory.swapOutBytesPerSecond.numericValue).max(),
            networkReceivedBytesPerSecond: primary.map { value("bytes/s", $0.1.receivedBytesPerSecond, $0.0.id) },
            networkSentBytesPerSecond: primary.map { value("bytes/s", $0.1.sentBytesPerSecond, $0.0.id) },
            gpuBusyPercent: snapshot.gpu.last.flatMap { frame in
                frame.devices.first.map { value("%", $0.utilizationPercent, frame.id) }
            },
            systemPowerWatts: power.map { DiagnosticValue(unit: "W", reading: $0, evidence: "power:latest") },
            thermalPressure: latest.flatMap { ThermalPressureLevel(reading: $0.thermalPressure) }.map { "\($0)" },
            hottestCelsius: sensors.flatMap { frame in
                frame.hottest.map { DiagnosticValue(unit: "°C (\($0.key))", reading: $0.celsius, evidence: "sensors:\(frame.id)") }
            },
            signals: signals(window)
        )
    }

    /// Facts only: thresholds over the summary window, each with evidence.
    static func signals(_ window: [CapturedSnapshot]) -> [DiagnosticSignal] {
        guard let first = window.first, let last = window.last else { return [] }
        let evidence = "host:\(first.stamp.wallTime.timeIntervalSince1970)-\(last.stamp.wallTime.timeIntervalSince1970)"
        var result: [DiagnosticSignal] = []

        let cpu = window.compactMap(\.cpuPercentOfMachine.numericValue)
        if !cpu.isEmpty, cpu.reduce(0, +) / Double(cpu.count) >= saturatedCPUPercent {
            result.append(DiagnosticSignal(kind: .cpuSaturated, detail: "Mean CPU at or above 85% of the machine", evidence: evidence))
        }
        let elevated = window.filter { ($0.memory.pressureLevel?.rawValue ?? 0) >= MemoryPressureLevel.warning.rawValue }
        if elevated.count * 2 >= window.count {
            result.append(DiagnosticSignal(
                kind: .memoryPressureElevated,
                detail: "Memory pressure at warning or above in \(elevated.count) of \(window.count) samples",
                evidence: evidence
            ))
        }
        if window.contains(where: { ($0.memory.swapOutBytesPerSecond.numericValue ?? 0) > 0 }) {
            result.append(DiagnosticSignal(kind: .swapping, detail: "Pages were swapped out", evidence: evidence))
        }
        if window.contains(where: { (ThermalPressureLevel(reading: $0.thermalPressure)?.rawValue ?? 0) >= ThermalPressureLevel.heavy.rawValue }) {
            result.append(DiagnosticSignal(kind: .thermalPressureElevated, detail: "Thermal pressure reached heavy", evidence: evidence))
        }
        if window.contains(where: { $0.continuity == .interrupted }) {
            result.append(DiagnosticSignal(kind: .samplingGap, detail: "Sampling was interrupted; some intervals are missing", evidence: evidence))
        }
        return result
    }

    // MARK: Top apps

    public static func topApps(
        _ snapshot: DiagnosticSnapshot, metric: ActivityMetric, range: ClosedRange<Date>? = nil,
        limit: Int = 10, cursor: String? = nil
    ) throws -> TopAppsPage {
        guard (1...maximumRows).contains(limit) else {
            throw DiagnosticError.invalidArgument("limit must be 1-\(maximumRows)")
        }
        let window = try boundedRange(range, snapshot: snapshot)
        let offset = try cursorOffset(cursor, snapshot: snapshot, metric: metric, range: window)
        let (apps, covered) = snapshot.ledger.totals(in: window)
        let unit = metric == .cpu ? "CPU-seconds" : "bytes"
        let activity: [AppActivity] = apps.map { app in
            AppActivity(app: app.name, value: metric == .cpu ? app.cpuSeconds : app.diskBytes,
                        unit: unit, isLowerBound: app.isLowerBound)
        }
        let ranked = activity.filter { $0.value > 0 }.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.app < rhs.app
        }
        let page = Array(ranked.dropFirst(offset).prefix(limit))
        let next = offset + page.count
        return TopAppsPage(
            snapshotID: snapshot.id, metric: metric, rows: page,
            remaining: max(0, ranked.count - next),
            nextCursor: next < ranked.count ? makeCursor(snapshot: snapshot, metric: metric, range: window, offset: next) : nil,
            coveredStart: covered?.lowerBound, coveredEnd: covered?.upperBound,
            coverageNote: "Own-user processes grouped by app; other users' processes are not readable without the helper."
        )
    }

    // MARK: History

    public static func history(
        _ snapshot: DiagnosticSnapshot, metric: HistoryMetric, range: ClosedRange<Date>? = nil,
        maximumPoints requested: Int = maximumPoints
    ) throws -> MetricHistory {
        guard (2...maximumPoints).contains(requested) else {
            throw DiagnosticError.invalidArgument("maximumPoints must be 2-\(maximumPoints)")
        }
        let window = try boundedRange(range, snapshot: snapshot)
        let (points, unit) = series(snapshot, metric: metric)
        let inRange = points.filter { window.contains($0.time) }
        let buckets = requested / 2
        let reduced = Decimation.extremes(
            inRange, start: window.lowerBound, end: window.upperBound, buckets: buckets,
            time: \.time, value: \.value, segment: \.segment
        )
        return MetricHistory(
            snapshotID: snapshot.id, metric: metric, unit: unit,
            points: reduced.map { MetricHistory.Point(time: $0.time, value: $0.value, segment: $0.segment) },
            decimated: reduced.count < inRange.count
        )
    }

    // MARK: Processes, sources, sleep

    public static func processDetails(_ snapshot: DiagnosticSnapshot, pid: Int32) -> ProcessDetails? {
        guard let processes = snapshot.processes,
              let process = processes.processes.first(where: { $0.id.pid == pid }) else { return nil }
        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .name, grouping: .app)
        let app = rows.first { row in row.children?.contains { $0.process?.id == process.id } ?? (row.process?.id == process.id) }
        return ProcessDetails(
            pid: process.id.pid, startSeconds: process.id.startSeconds, startMicroseconds: process.id.startMicroseconds,
            name: process.name, app: app?.appName ?? process.name, uid: process.uid,
            cpuPercentOfMachine: process.cpuPercentOfMachine, memoryFootprintBytes: process.memoryFootprintBytes,
            diskReadBytesPerSecond: process.diskReadBytesPerSecond, diskWriteBytesPerSecond: process.diskWriteBytesPerSecond
        )
    }

    public static func dataSources(_ snapshot: DiagnosticSnapshot) -> [DataSourceStatus] {
        var readings: [(String, MetricReading)] = []
        if let host = snapshot.host.last {
            readings += [
                ("cpu", host.cpuPercentOfMachine), ("memoryUsed", host.memoryUsedBytes),
                ("swapUsed", host.memory.swapUsedBytes), ("memoryPressure", host.memory.pressure),
                ("thermalPressure", host.thermalPressure)
            ]
        }
        if let network = snapshot.network.last { readings.append(("networkInterfaces", network.enumeration)) }
        if let gpu = snapshot.gpu.last { readings.append(("gpu", gpu.enumeration)) }
        if let power = snapshot.power.last { readings.append(("battery", power.batteryChargePercent)) }
        if let sensors = snapshot.sensors.last {
            readings += [("sensors", sensors.source), ("systemPower", sensors.systemPowerWatts)]
        }
        if let processes = snapshot.processes { readings.append(("processes", processes.enumeration)) }
        return readings.map {
            DataSourceStatus(metric: $0.0, availability: $0.1.availability, source: $0.1.source, reason: $0.1.reason)
        }
    }

    public static func sleepHistory(_ snapshot: DiagnosticSnapshot) throws -> Never {
        throw DiagnosticError.unavailable("Sleep and wake history needs the pmset and log import (spike S8)")
    }

    // MARK: Helpers

    private static func value(_ unit: String, _ reading: MetricReading, _ frame: UUID) -> DiagnosticValue {
        DiagnosticValue(unit: unit, reading: reading, evidence: "frame:\(frame)")
    }

    private static func recent<Frame>(_ frames: [Frame], before end: Date, _ time: (Frame) -> Date) -> [Frame] {
        frames.filter { time($0) <= end && time($0) >= end.addingTimeInterval(-summaryWindow) }
    }

    /// Defaults to the last summary window; refuses ranges beyond live history.
    private static func boundedRange(_ range: ClosedRange<Date>?, snapshot: DiagnosticSnapshot) throws -> ClosedRange<Date> {
        let window = range ?? snapshot.takenAt.addingTimeInterval(-summaryWindow)...snapshot.takenAt
        guard window.upperBound.timeIntervalSince(window.lowerBound) <= TimeInterval(maximumRangeSeconds) else {
            throw DiagnosticError.rangeTooLarge(maximumSeconds: maximumRangeSeconds)
        }
        return window
    }

    private static func series(_ snapshot: DiagnosticSnapshot, metric: HistoryMetric) -> ([DashboardPoint], String) {
        func points<Frame>(
            _ frames: [Frame], unit: String, time: (Frame) -> Date, id: (Frame) -> UUID,
            interrupted: (Frame) -> Bool, value: (Frame) -> Double?
        ) -> ([DashboardPoint], String) {
            var result: [DashboardPoint] = []
            var segment = 0
            for frame in frames {
                if interrupted(frame) { segment += 1 }
                guard let number = value(frame) else {
                    segment += 1
                    continue
                }
                result.append(DashboardPoint(id: id(frame), time: time(frame), value: number, segment: segment))
            }
            return (result, unit)
        }
        let host = { (unit: String, value: @escaping (CapturedSnapshot) -> Double?) in
            points(snapshot.host, unit: unit, time: { $0.stamp.wallTime }, id: \.id,
                   interrupted: { $0.continuity == .interrupted }, value: value)
        }
        let network = { (sent: Bool) in
            points(snapshot.network, unit: "bytes/s", time: { $0.stamp.wallTime }, id: \.id,
                   interrupted: { $0.continuity == .interrupted }) { frame in
                frame.interfaces.first { $0.id == frame.primaryInterface }
                    .flatMap { (sent ? $0.sentBytesPerSecond : $0.receivedBytesPerSecond).numericValue }
            }
        }
        switch metric {
        case .cpu: return host("% of machine") { $0.cpuPercentOfMachine.numericValue }
        case .memoryUsed: return host("bytes") { $0.memoryUsedBytes.numericValue }
        case .networkReceived: return network(false)
        case .networkSent: return network(true)
        case .gpuBusy:
            return points(snapshot.gpu, unit: "%", time: { $0.stamp.wallTime }, id: \.id,
                          interrupted: { $0.continuity == .interrupted }) { $0.devices.first?.utilizationPercent.numericValue }
        case .hottestCelsius:
            return points(snapshot.sensors, unit: "°C", time: { $0.stamp.wallTime }, id: \.id,
                          interrupted: { $0.continuity == .interrupted }) { $0.hottest?.celsius.numericValue }
        case .systemPower:
            return points(snapshot.sensors, unit: "W", time: { $0.stamp.wallTime }, id: \.id,
                          interrupted: { $0.continuity == .interrupted }) { $0.systemPowerWatts.numericValue }
        }
    }

    // Cursor: "<snapshot>|<metric>|<start>|<end>|<offset>", valid only for the same query.
    private static func makeCursor(
        snapshot: DiagnosticSnapshot, metric: ActivityMetric, range: ClosedRange<Date>, offset: Int
    ) -> String {
        [snapshot.id.uuidString, metric.rawValue, "\(range.lowerBound.timeIntervalSince1970)",
         "\(range.upperBound.timeIntervalSince1970)", "\(offset)"].joined(separator: "|")
    }

    private static func cursorOffset(
        _ cursor: String?, snapshot: DiagnosticSnapshot, metric: ActivityMetric, range: ClosedRange<Date>
    ) throws -> Int {
        guard let cursor else { return 0 }
        let parts = cursor.split(separator: "|").map(String.init)
        guard parts.count == 5, let offset = Int(parts[4]), offset >= 0,
              cursor == makeCursor(snapshot: snapshot, metric: metric, range: range, offset: offset) else {
            throw DiagnosticError.invalidCursor
        }
        return offset
    }
}
