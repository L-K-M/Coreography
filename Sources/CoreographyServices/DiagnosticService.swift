import Foundation
import CoreographyKit

public typealias CapturedSnapshot = SystemSnapshot
public typealias DashboardReading = MetricReading
public typealias CapturedMemoryPressure = MemoryPressureLevel
public typealias CapturedThermalPressure = ThermalPressureLevel
public typealias CapturedGPU = GPUSnapshot
public typealias CapturedGPUDevice = GPUDeviceReading

public enum NativeSamplingSupport: String, Codable, Sendable {
    case supported
    case unsupported
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

    public init() throws {
        monitor = try SystemMonitor()
        processMonitor = try ProcessMonitor()
        networkMonitor = try NetworkMonitor()
        diskMonitor = try DiskMonitor()
        gpuMonitor = try GPUMonitor()
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

    public static var nativeSamplingSupport: NativeSamplingSupport {
        #if os(macOS)
        .supported
        #else
        .unsupported
        #endif
    }
}
