import Foundation
import CoreographyDrivers

/// A call-stack sample of one process, as `sample` wrote it.
public struct ProcessSampleReport: Identifiable, Sendable {
    public let id = UUID()
    public let process: ProcessIdentity
    public let name: String
    public let takenAt: Date
    public let seconds: Int
    public let text: String
}

/// Samples a process on request with the system tool; never while sampling metrics.
public struct ProcessSampler: Sendable {
    /// Long enough to catch a busy loop, short enough to wait for.
    public static let defaultSeconds = 3
    private let driver: any ProcessSampling

    public init() { self.init(driver: ProcessSampleDriver()) }

    init(driver: any ProcessSampling) { self.driver = driver }

    public func sample(_ process: ProcessReading, seconds: Int = defaultSeconds) async -> Result<ProcessSampleReport, ProcessSampleFailure> {
        let start = Date()
        let result = await driver.sample(
            pid: process.id.pid, startSeconds: process.id.startSeconds, startMicroseconds: process.id.startMicroseconds,
            seconds: seconds
        )
        switch result {
        case .success(let text):
            return .success(ProcessSampleReport(process: process.id, name: process.name, takenAt: start, seconds: seconds, text: text))
        case .failure(.unsupportedPlatform):
            return .failure(ProcessSampleFailure(reason: "Sampling needs macOS"))
        case .failure(.exited):
            return .failure(ProcessSampleFailure(reason: "The process exited before it could be sampled"))
        case .failure(.failed(let message)):
            return .failure(ProcessSampleFailure(reason: message))
        }
    }
}

public struct ProcessSampleFailure: Error, Equatable, Sendable {
    public let reason: String
}
