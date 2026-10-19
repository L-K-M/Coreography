import Foundation

#if os(macOS)
import Darwin
import CoreographySystem
#endif

/// Reading any descriptor table fails the same ways as reading sockets.
public typealias DescriptorReadError = SocketReadError

public struct RawProcessFiles: Equatable, Sendable {
    /// Open file and directory paths, in descriptor order.
    public let paths: [String]
    /// The process held more open files than one read keeps.
    public let truncated: Bool

    public init(paths: [String], truncated: Bool) {
        self.paths = paths
        self.truncated = truncated
    }
}

public protocol ProcessFileReading: Sendable {
    func files(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<RawProcessFiles, DescriptorReadError>
}

/// Reads one process's open file paths through libproc, only for the exact
/// process identity the caller saw.
public actor ProcessFileDriver: ProcessFileReading {
    /// Enough for most processes; more are reported as truncated.
    private static let capacity = 512
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.file-sampling")
    #if os(macOS)
    // About 500 KB, reused: a pass over every process would otherwise allocate per process.
    private var buffer = [coreo_file_sample](repeating: coreo_file_sample(), count: ProcessFileDriver.capacity)
    #endif

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func files(
        pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64
    ) -> Result<RawProcessFiles, DescriptorReadError> {
        #if os(macOS)
        var count: Int32 = 0
        var truncated: Int32 = 0
        let status = buffer.withUnsafeMutableBufferPointer {
            coreo_process_files(pid, startSeconds, startMicroseconds, $0.baseAddress, Int32(Self.capacity), &count, &truncated)
        }
        switch status {
        case 0:
            let paths = buffer.prefix(Int(count)).map { sample in
                withUnsafeBytes(of: sample.path) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
            }
            return .success(RawProcessFiles(paths: paths, truncated: truncated != 0))
        case ESRCH, EAGAIN: return .failure(.exited)
        case EPERM, EACCES: return .failure(.notPermitted)
        case ENOTSUP: return .failure(.unsupportedPlatform)
        default: return .failure(.systemCall(code: status))
        }
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }
}
