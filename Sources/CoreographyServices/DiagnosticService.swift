import Foundation
import CoreographyKit

public typealias CapturedSnapshot = SystemSnapshot
public typealias DashboardReading = MetricReading
public typealias CapturedMemoryPressure = MemoryPressureLevel
public typealias CapturedThermalPressure = ThermalPressureLevel
public typealias CapturedGPU = GPUSnapshot
public typealias CapturedGPUDevice = GPUDeviceReading
public typealias CapturedPower = PowerSnapshot
public typealias CapturedSensors = SensorSnapshot

public enum NativeSamplingSupport: String, Codable, Sendable {
    case supported
    case unsupported
}

/// One `coreo diagnose` answer: facts and coverage for a person or an assistant.
public struct DiagnosisReport: Codable, Sendable {
    public let summary: SystemSummary
    public let topCPUApps: TopAppsPage
    public let topDiskApps: TopAppsPage
    public let dataSources: [DataSourceStatus]
}

/// Stored readings for `coreo history`.
public struct HistoryReport: Codable, Sendable {
    public struct Sample: Codable, Sendable {
        public let time: Date
        public let value: Double?
        public let availability: MetricAvailability
    }

    public let metric: String
    public let storedSamples: Int
    public let samples: [Sample]
}

public struct DiagnosticReport: Codable, Sendable {
    public let schemaVersion: Int
    public let buildVersion: String
    public let nativeSampling: NativeSamplingSupport
    public let snapshot: CapturedSnapshot
}

public actor DiagnosticService {
    private static let schemaVersion = 1
    private static let warmupInterval: Duration = .seconds(1)
    private let monitor: SystemMonitor
    private let processMonitor: ProcessMonitor
    private let networkMonitor: NetworkMonitor
    private let diskMonitor: DiskMonitor
    private let gpuMonitor: GPUMonitor
    private let powerMonitor: PowerMonitor
    private let sensorMonitor: SensorMonitor

    public init() throws {
        monitor = try SystemMonitor()
        processMonitor = try ProcessMonitor()
        networkMonitor = try NetworkMonitor()
        diskMonitor = try DiskMonitor()
        gpuMonitor = try GPUMonitor()
        powerMonitor = try PowerMonitor()
        sensorMonitor = try SensorMonitor()
    }

    public func report() async throws -> DiagnosticReport {
        DiagnosticReport(
            schemaVersion: Self.schemaVersion,
            buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "development",
            nativeSampling: Self.nativeSamplingSupport,
            snapshot: try await monitor.sample()
        )
    }

    /// Rates need a baseline; the one-shot CLI waits for a real second sample.
    public func captureOnce() async throws -> CapturedSnapshot {
        _ = try await monitor.sample()
        try await Task.sleep(for: Self.warmupInterval)
        return try await monitor.sample()
    }

    public func captureProcessesOnce() async throws -> CapturedProcesses {
        _ = try await processMonitor.sample()
        try await Task.sleep(for: .seconds(2))
        return try await processMonitor.sample()
    }

    public func captureNetworkOnce() async throws -> CapturedNetwork {
        _ = try await networkMonitor.sample()
        try await Task.sleep(for: Self.warmupInterval)
        return try await networkMonitor.sample()
    }

    public func captureDisksOnce() async throws -> CapturedDisks {
        _ = try await diskMonitor.sample()
        try await Task.sleep(for: Self.warmupInterval)
        return try await diskMonitor.sample()
    }

    /// GPU utilization is a driver gauge; one read needs no baseline.
    public func captureGPUOnce() async throws -> CapturedGPU {
        try await gpuMonitor.sample()
    }

    /// Battery and adapter values are gauges; one read needs no baseline.
    public func capturePowerOnce() async throws -> CapturedPower {
        try await powerMonitor.sample()
    }

    /// SMC temperatures, fans and power rails are gauges; one read suffices.
    public func captureSensorsOnce() async throws -> CapturedSensors {
        try await sensorMonitor.sample()
    }

    /// Sample every monitor for a bounded window, then answer from one snapshot.
    /// Example: `coreo diagnose --json` waits 5 s and reports summary, top apps and sources.
    public func diagnose(seconds: Int) async throws -> DiagnosisReport {
        let bounded = min(max(seconds, Self.minimumDiagnosisSeconds), Self.maximumDiagnosisSeconds)
        var ledger = AppLedger(capacity: bounded)
        var processes: CapturedProcesses?
        for second in 0...bounded {
            _ = try await monitor.sample()
            _ = try await networkMonitor.sample()
            _ = try await gpuMonitor.sample()
            _ = try await powerMonitor.sample()
            _ = try await sensorMonitor.sample()
            if second.isMultiple(of: Self.processEverySeconds) {
                let sample = try await processMonitor.sample()
                processes = sample
                ledger.record(sample, logicalCPUCount: await monitor.history().last?.inventory.logicalCPUCount)
            }
            if second < bounded { try await Task.sleep(for: Self.warmupInterval) }
        }
        let snapshot = DiagnosticSnapshot(
            takenAt: Date(), host: await monitor.history(), network: await networkMonitor.history(),
            gpu: await gpuMonitor.history(), power: await powerMonitor.history(),
            sensors: await sensorMonitor.history(), processes: processes, ledger: ledger
        )
        return DiagnosisReport(
            summary: DiagnosticTools.summary(snapshot),
            topCPUApps: try DiagnosticTools.topApps(snapshot, metric: .cpu),
            topDiskApps: try DiagnosticTools.topApps(snapshot, metric: .disk),
            dataSources: DiagnosticTools.dataSources(snapshot)
        )
    }

    /// Read what the app has recorded; the CLI never writes history.
    public func history(metric name: String, minutes: Int) async throws -> HistoryReport {
        guard let metric = HistoryMetric.allCases.first(where: { "\($0)" == name }) else {
            throw DiagnosticError.invalidArgument("Unknown metric; use one of " + HistoryMetric.allCases.map { "\($0)" }.joined(separator: ", "))
        }
        let (recorder, problem) = HistoryRecorder.makeDefault()
        guard let recorder else { throw DiagnosticError.unavailable(problem ?? "History store unavailable") }
        let end = Date()
        let window = TimeInterval(min(max(minutes, 1), Int(HistoryStore.retention / 60)) * 60)
        let samples = try await recorder.samples(metric, from: end.addingTimeInterval(-window), to: end)
        return HistoryReport(
            metric: name, storedSamples: samples.count,
            samples: samples.map { HistoryReport.Sample(time: $0.time, value: $0.value, availability: $0.availability) }
        )
    }

    private static let minimumDiagnosisSeconds = 3
    private static let maximumDiagnosisSeconds = 60
    private static let processEverySeconds = 2

    public static var nativeSamplingSupport: NativeSamplingSupport {
        #if os(macOS)
        .supported
        #else
        .unsupported
        #endif
    }
}
