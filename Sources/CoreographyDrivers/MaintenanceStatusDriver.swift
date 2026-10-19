import Foundation

/// One status tool's text as its caps let it through.
public struct RawToolStatus: Sendable {
    public let text: String
    public let timedOut: Bool
    public let exitStatus: Int32

    public init(text: String, timedOut: Bool, exitStatus: Int32) {
        self.text = text
        self.timedOut = timedOut
        self.exitStatus = exitStatus
    }
}

public enum MaintenanceStatusError: Error, Equatable, Sendable {
    case unavailable(String)
}

public protocol MaintenanceStatusReading: Sendable {
    func timeMachineStatus() async throws -> RawToolStatus
    func spotlightStatus() async throws -> RawToolStatus
}

/// Reads the two maintenance status sources macOS offers, with fixed
/// paths and arguments, off the sampling path (plan: maintenance states
/// only where a real status source exists).
///
/// - `tmutil status` reports whether a backup runs, its phase and progress.
/// - `mdutil -s /` reports only whether the startup disk is indexed.
public struct MaintenanceStatusDriver: MaintenanceStatusReading {
    private static let tmutil = URL(fileURLWithPath: "/usr/bin/tmutil")
    private static let mdutil = URL(fileURLWithPath: "/usr/bin/mdutil")
    private static let timeout: Duration = .seconds(5)
    /// Both answers are a few hundred bytes.
    private static let keepBytes = 64 * 1024
    private let runner = BoundedCommandRunner()

    public init() {}

    public func timeMachineStatus() async throws -> RawToolStatus {
        try await run(Self.tmutil, ["status"], tool: "tmutil")
    }

    public func spotlightStatus() async throws -> RawToolStatus {
        try await run(Self.mdutil, ["-s", "/"], tool: "mdutil")
    }

    private func run(_ executable: URL, _ arguments: [String], tool: String) async throws -> RawToolStatus {
        #if os(macOS)
        let output: CommandOutput
        do {
            output = try await runner.run(executable, arguments: arguments, timeout: Self.timeout, keepBytes: Self.keepBytes)
        } catch CommandRunnerError.launchFailed(let detail) {
            throw MaintenanceStatusError.unavailable("\(tool) could not start: \(detail)")
        }
        return RawToolStatus(
            text: String(decoding: output.data, as: UTF8.self), timedOut: output.timedOut, exitStatus: output.exitStatus
        )
        #else
        throw MaintenanceStatusError.unavailable("\(tool) needs macOS")
        #endif
    }
}
