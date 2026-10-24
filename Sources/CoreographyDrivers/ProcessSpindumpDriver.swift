import Foundation

/// The helper's spindump for one process identity: `/usr/sbin/spindump` is
/// an allowlisted system path run with fixed arguments, a runtime cap and
/// a report path the helper itself picks and removes, so only the report's
/// text can leave (plan: allowlisted tools, bounded time and output, never
/// a caller-selected path). The tool samples the whole system and sorts the
/// target topmost; only root may run it.
public struct ProcessSpindumpDriver: Sendable {
    private static let tool = URL(fileURLWithPath: "/usr/sbin/spindump")
    /// The tool still walks and symbolicates every stack after the window ends.
    private static let overhead: Duration = .seconds(45)
    /// spindump prints progress, not the report; the cap is a runaway guard.
    private static let keepBytes = 1024 * 1024
    private let runner = BoundedCommandRunner()

    public init() {}

    public func spindump(
        pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, seconds: Int
    ) async -> Result<String, ProcessSampleError> {
        #if os(macOS)
        guard pid > 0, HelperWire.spindumpSeconds.contains(Int32(seconds)) else { return .failure(.failed("Invalid spindump request")) }
        // spindump resolves the pid when it starts, so only the instant between
        // this check and that launch could meet a reused pid.
        guard ProcessIdentityCheck.matches(pid, startSeconds, startMicroseconds) else { return .failure(.exited) }

        let report = FileManager.default.temporaryDirectory
            .appendingPathComponent("coreo-spindump-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: report) }
        let output: CommandOutput
        do {
            output = try await runner.run(
                Self.tool, arguments: [String(pid), String(seconds), "-file", report.path],
                timeout: .seconds(seconds) + Self.overhead, keepBytes: Self.keepBytes
            )
        } catch {
            return .failure(.failed("spindump could not start: \(error)"))
        }
        guard !output.timedOut else { return .failure(.failed("spindump did not finish in time")) }
        guard output.exitStatus == 0 else {
            let message = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.failed(message.isEmpty ? "spindump exited with status \(output.exitStatus)" : message))
        }
        // A clean exit without a readable report is its own failure, not "status 0".
        do {
            return .success(try String(contentsOf: report, encoding: .utf8))
        } catch {
            return .failure(.failed("spindump finished but its report could not be read: \(error)"))
        }
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }
}
