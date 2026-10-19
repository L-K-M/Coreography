import Foundation

#if os(macOS)
import CoreographySystem
#endif

public enum ProcessSampleError: Error, Equatable, Sendable {
    case unsupportedPlatform
    /// Gone, or the pid now names another process.
    case exited
    case failed(String)
}

public protocol ProcessSampling: Sendable {
    func sample(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, seconds: Int) async -> Result<String, ProcessSampleError>
}

/// Runs the allowlisted `/usr/bin/sample` for one process identity: a fixed
/// path, validated arguments, a runtime cap and an output cap (plan: sample
/// and spindump use allowlisted system tools). The report is written to a
/// private temporary file, read back and removed.
public struct ProcessSampleDriver: ProcessSampling {
    private static let tool = URL(fileURLWithPath: "/usr/bin/sample")
    public static let allowedSeconds = 1...10
    /// The tool needs a little time beyond the sampling window to symbolicate.
    private static let overhead: Duration = .seconds(20)
    private static let keepBytes = 4 * 1024 * 1024
    private let runner = BoundedCommandRunner()

    public init() {}

    public func sample(
        pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, seconds: Int
    ) async -> Result<String, ProcessSampleError> {
        #if os(macOS)
        guard pid > 0, Self.allowedSeconds.contains(seconds) else { return .failure(.failed("Invalid sample request")) }
        // sample attaches to the task at launch, so only the instant between
        // this check and that launch could meet a reused pid.
        guard Self.matches(pid, startSeconds, startMicroseconds) else { return .failure(.exited) }

        let report = FileManager.default.temporaryDirectory
            .appendingPathComponent("coreo-sample-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: report) }
        let output: CommandOutput
        do {
            output = try await runner.run(
                Self.tool, arguments: [String(pid), String(seconds), "-mayDie", "-file", report.path],
                timeout: .seconds(seconds) + Self.overhead, keepBytes: Self.keepBytes
            )
        } catch {
            return .failure(.failed("sample could not start: \(error)"))
        }
        guard !output.timedOut else { return .failure(.failed("sample did not finish in time")) }
        guard output.exitStatus == 0 else {
            let message = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.failed(message.isEmpty ? "sample exited with status \(output.exitStatus)" : message))
        }
        // A clean exit without a readable report is its own failure, not "status 0".
        guard let text = try? String(contentsOf: report, encoding: .utf8) else {
            return .failure(.failed("sample finished but its report could not be read"))
        }
        return .success(text)
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    private static func matches(_ pid: Int32, _ seconds: UInt64, _ microseconds: UInt64) -> Bool {
        var sample = coreo_process_sample()
        guard coreo_process_read(pid, &sample) == 0 else { return false }
        return sample.start_seconds == seconds && sample.start_microseconds == microseconds
    }
    #endif
}
