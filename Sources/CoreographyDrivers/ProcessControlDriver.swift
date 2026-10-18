import Foundation

#if os(macOS)
import AppKit
import Darwin
import CoreographySystem
#endif

/// How a process is asked to end.
public enum ProcessTermination: Sendable {
    /// A regular app quits through AppKit, so it can save or ask; other
    /// processes receive SIGTERM.
    case graceful
    /// SIGKILL; the process gets no chance to clean up.
    case forced
}

public enum ProcessControlError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case invalidTarget
    case exited
    case identityChanged
    case notPermitted
    case refusedByApp
    case systemCall(code: Int32)
}

public protocol ProcessTerminating: Sendable {
    @MainActor
    func terminate(
        pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, mode: ProcessTermination
    ) -> Result<Void, ProcessControlError>
}

/// Sends quit requests only to the exact process identity the caller saw.
public struct ProcessControlDriver: ProcessTerminating {
    public init() {}

    @MainActor
    public func terminate(
        pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64, mode: ProcessTermination
    ) -> Result<Void, ProcessControlError> {
        #if os(macOS)
        if mode == .graceful, let app = NSRunningApplication(processIdentifier: pid),
           app.activationPolicy == .regular {
            // AppKit offers no identity-checked quit, so check, then ask at once.
            if let failure = identityFailure(pid: pid, startSeconds: startSeconds, startMicroseconds: startMicroseconds) {
                return .failure(failure)
            }
            return app.terminate() ? .success(()) : .failure(.refusedByApp)
        }
        let kind = mode == .forced ? Int32(COREO_SIGNAL_KILL) : Int32(COREO_SIGNAL_TERMINATE)
        let status = coreo_process_signal(pid, startSeconds, startMicroseconds, kind)
        return status == 0 ? .success(()) : .failure(Self.error(status))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    private func identityFailure(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) -> ProcessControlError? {
        guard pid > 0 else { return .invalidTarget }
        var sample = coreo_process_sample()
        let status = coreo_process_read(pid, &sample)
        guard status == 0 else { return Self.error(status) }
        let matches = sample.start_seconds == startSeconds && sample.start_microseconds == startMicroseconds
        return matches ? nil : .identityChanged
    }

    private static func error(_ code: Int32) -> ProcessControlError {
        switch code {
        case EINVAL: .invalidTarget
        case ESRCH: .exited
        case EAGAIN: .identityChanged
        case EPERM, EACCES: .notPermitted
        case ENOTSUP: .unsupportedPlatform
        default: .systemCall(code: code)
        }
    }
    #endif
}
