import Foundation
import CoreographyDrivers

/// Every readable process's open file paths at one moment, with what could
/// not be read named rather than dropped.
public struct OpenFileSnapshot: Sendable {
    public let takenAt: Date
    public let files: [ProcessIdentity: [String]]
    /// Processes of other users; reading their files needs the helper.
    public let restrictedProcesses: Int
    public let truncatedProcesses: Int
    public let failedProcesses: Int
    public let unavailableReason: String?
}

/// Reads open files per observed process, only on request: a pass touches
/// every descriptor of every process.
public actor OpenFileMonitor {
    private let driver: any ProcessFileReading

    public init() { self.init(driver: ProcessFileDriver()) }

    init(driver: any ProcessFileReading) { self.driver = driver }

    public func sample(_ processes: ProcessSnapshot, at time: Date = Date()) async -> OpenFileSnapshot {
        var files: [ProcessIdentity: [String]] = [:]
        var restricted = 0
        var truncated = 0
        var failed = 0
        for process in processes.processes where process.id.pid > 0 {
            switch await read(process) {
            case .success(let read):
                files[process.id] = read.paths
                if read.truncated { truncated += 1 }
            case .failure(.notPermitted):
                restricted += 1
            case .failure(.exited):
                continue
            case .failure(.unsupportedPlatform):
                return OpenFileSnapshot(
                    takenAt: time, files: [:], restrictedProcesses: 0, truncatedProcesses: 0, failedProcesses: 0,
                    unavailableReason: "Open files need macOS"
                )
            case .failure(.systemCall):
                failed += 1
            }
        }
        return OpenFileSnapshot(
            takenAt: time, files: files, restrictedProcesses: restricted, truncatedProcesses: truncated,
            failedProcesses: failed, unavailableReason: nil
        )
    }

    /// One process's open files, for the inspector; nil when they cannot be read.
    public func files(of process: ProcessReading) async -> OpenFileList? {
        guard case .success(let read) = await read(process) else { return nil }
        return OpenFileList(paths: read.paths, isComplete: !read.truncated)
    }

    private func read(_ process: ProcessReading) async -> Result<RawProcessFiles, DescriptorReadError> {
        await driver.files(pid: process.id.pid, startSeconds: process.id.startSeconds, startMicroseconds: process.id.startMicroseconds)
    }
}

/// One process's open files, and whether that is all of them.
public struct OpenFileList: Equatable, Sendable {
    public let paths: [String]
    /// False when the process held more descriptors than one read keeps.
    public let isComplete: Bool
}
