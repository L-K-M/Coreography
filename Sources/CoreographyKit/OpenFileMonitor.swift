import Foundation
import CoreographyDrivers

/// Every readable process's open file paths at one moment, with what could
/// not be read named rather than dropped.
public struct OpenFileSnapshot: Sendable {
    public let takenAt: Date
    public let files: [ProcessIdentity: [String]]
    /// Processes of other users the helper did not read: it is not installed, or they exited.
    public let restrictedProcesses: Int
    public let truncatedProcesses: Int
    public let failedProcesses: Int
    public let unavailableReason: String?
}

/// Reads open files per observed process, only on request: a pass touches
/// every descriptor of every process.
public actor OpenFileMonitor {
    private let driver: any ProcessFileReading
    /// Reads other users' processes, when installed.
    private let helper: PrivilegedHelper?

    public init() { self.init(driver: ProcessFileDriver(), helper: .shared) }

    init(driver: any ProcessFileReading, helper: PrivilegedHelper? = nil) {
        self.driver = driver
        self.helper = helper
    }

    public func sample(_ processes: ProcessSnapshot, at time: Date = Date()) async -> OpenFileSnapshot {
        var files: [ProcessIdentity: [String]] = [:]
        var restricted: [ProcessIdentity] = []
        var truncated = 0
        var failed = 0
        for process in processes.processes where process.id.pid > 0 {
            switch await read(process) {
            case .success(let read):
                files[process.id] = read.paths
                if read.truncated { truncated += 1 }
            case .failure(.notPermitted):
                restricted.append(process.id)
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
        let asked = Dictionary(restricted.map { ($0.helperIdentity, $0) }, uniquingKeysWith: { first, _ in first })
        for read in await helper?.openFiles(of: restricted.map(\.helperIdentity)) ?? [] {
            guard let process = asked[read.process] else { continue }
            files[process] = read.files.paths
            if read.files.truncated { truncated += 1 }
        }
        return OpenFileSnapshot(
            takenAt: time, files: files, restrictedProcesses: restricted.count(where: { files[$0] == nil }),
            truncatedProcesses: truncated, failedProcesses: failed, unavailableReason: nil
        )
    }

    /// One process's open files, for the inspector; nil when they cannot be read.
    public func files(of process: ProcessReading) async -> OpenFileList? {
        switch await read(process) {
        case .success(let read):
            return OpenFileList(paths: read.paths, isComplete: !read.truncated)
        case .failure(.notPermitted):
            guard let read = await helper?.openFiles(of: [process.id.helperIdentity])?.first?.files else { return nil }
            return OpenFileList(paths: read.paths, isComplete: !read.truncated)
        case .failure:
            return nil
        }
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
