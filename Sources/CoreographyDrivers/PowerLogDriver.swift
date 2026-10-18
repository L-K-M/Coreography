import Foundation

/// The `pmset -g log` text the caps let through.
public struct RawPowerLog: Sendable {
    public let text: String
    /// The oldest records were dropped to stay within the byte cap.
    public let truncated: Bool
    /// pmset was stopped at the time limit; the newest records may be missing.
    public let timedOut: Bool
    public let exitStatus: Int32

    public init(text: String, truncated: Bool, timedOut: Bool, exitStatus: Int32) {
        self.text = text
        self.truncated = truncated
        self.timedOut = timedOut
        self.exitStatus = exitStatus
    }
}

public enum PowerLogError: Error, Equatable, Sendable {
    case unavailable(String)
}

public protocol PowerLogReading: Sendable {
    func read() async throws -> RawPowerLog
}

/// Reads the power-management log with a fixed path and arguments, a
/// runtime cap and a tail-keeping output cap (plan: bounded sleep import).
public struct PowerLogDriver: PowerLogReading {
    private static let executable = URL(fileURLWithPath: "/usr/bin/pmset")
    private static let arguments = ["-g", "log"]
    private static let timeout: Duration = .seconds(20)
    /// Tens of thousands of records; the tail holds the newest.
    private static let keepBytes = 8 * 1024 * 1024
    private let runner = BoundedCommandRunner()

    public init() {}

    public func read() async throws -> RawPowerLog {
        #if os(macOS)
        let output: CommandOutput
        do {
            output = try await runner.run(
                Self.executable, arguments: Self.arguments, timeout: Self.timeout, keepBytes: Self.keepBytes
            )
        } catch CommandRunnerError.launchFailed(let detail) {
            throw PowerLogError.unavailable("pmset could not start: \(detail)")
        }

        // A cut tail starts mid-record; drop that fragment so it never parses.
        var data = output.data
        if output.truncated, let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            data = data[data.index(after: newline)...]
        }
        return RawPowerLog(
            text: String(decoding: data, as: UTF8.self), truncated: output.truncated,
            timedOut: output.timedOut, exitStatus: output.exitStatus
        )
        #else
        throw PowerLogError.unavailable("The power-management log needs macOS")
        #endif
    }
}
