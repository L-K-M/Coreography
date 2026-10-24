import Foundation

public enum BackgroundItemsError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case failed(String)
}

/// The Background Task Management database as `sfltool dumpbtm` prints it:
/// every user's login items, agents, daemons and background registrations.
/// Only root may dump it, so the privileged helper runs the fixed tool and
/// argument; the app parses the text. `keepBytes` is a runaway guard — the
/// reply cap decides what actually crosses back.
public struct BackgroundItemsDriver: Sendable {
    private static let tool = URL(fileURLWithPath: "/usr/bin/sfltool")
    private static let timeout: Duration = .seconds(20)
    private static let keepBytes = 4 * 1024 * 1024
    private let runner = BoundedCommandRunner()

    public init() {}

    /// The dump text, or why it could not be read.
    public func dump() async -> Result<String, BackgroundItemsError> {
        #if os(macOS)
        let output: CommandOutput
        do {
            output = try await runner.run(
                Self.tool, arguments: ["dumpbtm"], timeout: Self.timeout, keepBytes: Self.keepBytes
            )
        } catch {
            return .failure(.failed("sfltool could not start: \(error)"))
        }
        guard !output.timedOut else { return .failure(.failed("sfltool did not finish in time")) }
        guard output.exitStatus == 0 else {
            let detail = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.failed(detail.isEmpty ? "sfltool exited with status \(output.exitStatus)" : detail))
        }
        return .success(String(decoding: output.data, as: UTF8.self))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }
}
