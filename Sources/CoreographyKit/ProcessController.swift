import Foundation
import CoreographyDrivers

public typealias ProcessQuitMode = ProcessTermination

/// The result of one quit request, phrased for the person who asked.
public enum ProcessActionOutcome: Equatable, Sendable {
    case requested
    case failed(reason: String)
}

/// Quits processes by identity; never by a bare PID.
public struct ProcessController: Sendable {
    private let driver: any ProcessTerminating

    public init() { self.init(driver: ProcessControlDriver()) }

    init(driver: any ProcessTerminating) { self.driver = driver }

    @MainActor
    public func terminate(_ identity: ProcessIdentity, mode: ProcessQuitMode) -> ProcessActionOutcome {
        let result = driver.terminate(
            pid: identity.pid, startSeconds: identity.startSeconds,
            startMicroseconds: identity.startMicroseconds, mode: mode
        )
        switch result {
        case .success: return .requested
        case .failure(let error): return .failed(reason: Self.reason(error))
        }
    }

    private static func reason(_ error: ProcessControlError) -> String {
        switch error {
        case .unsupportedPlatform: "Process control requires macOS"
        case .invalidTarget: "This process cannot be targeted"
        case .exited: "The process already exited"
        case .identityChanged: "The PID now belongs to a different process; nothing was sent"
        case .notPermitted: "Not permitted: the process belongs to another user or is protected"
        case .refusedByApp: "The app could not be asked to quit"
        case .systemCall(let code): "The request failed (\(code))"
        }
    }
}
