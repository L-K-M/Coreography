import Foundation

struct CommandOutput: Sendable {
    let data: Data
    /// Older output was dropped to stay within the byte cap.
    let truncated: Bool
    /// The child was stopped at the time limit.
    let timedOut: Bool
    let exitStatus: Int32
}

enum CommandRunnerError: Error, Equatable, Sendable {
    case launchFailed(String)
}

/// Runs one fixed system tool with fixed arguments, off the hot path
/// (plan: no subprocesses while sampling; imports have runtime and output
/// caps, and reaching a cap reports partial coverage and stops the child).
///
/// Output keeps its newest bytes: logs grow oldest-first, so the tail
/// holds the recent events a person asks about.
struct BoundedCommandRunner: Sendable {
    init() {}

    func run(
        _ executable: URL, arguments: [String], timeout: Duration, keepBytes: Int
    ) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try Self.runBlocking(executable, arguments, timeout, keepBytes) })
            }
        }
    }

    private static func runBlocking(
        _ executable: URL, _ arguments: [String], _ timeout: Duration, _ keepBytes: Int
    ) throws -> CommandOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw CommandRunnerError.launchFailed("\(error)") }

        let stopped = StopFlag()
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            stopped.set()
            // Not SIGTERM: a child spawned from a dispatch worker inherits its
            // blocked signal mask and would never see it. SIGKILL cannot be blocked.
            kill(process.processIdentifier, SIGKILL)
        }
        let components = timeout.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: watchdog)

        var kept = Data()
        var truncated = false
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            kept.append(chunk)
            if kept.count > keepBytes {
                kept.removeFirst(kept.count - keepBytes)
                truncated = true
            }
        }
        process.waitUntilExit()
        watchdog.cancel()
        return CommandOutput(data: kept, truncated: truncated, timedOut: stopped.isSet, exitStatus: process.terminationStatus)
    }
}

/// Set once by the watchdog thread, read after the child exits.
private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
