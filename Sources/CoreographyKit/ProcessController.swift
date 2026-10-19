import Foundation
import CoreographyDrivers

public typealias ProcessQuitMode = ProcessTermination
public typealias ProcessSignalIntent = ProcessSignal

/// The result of one quit request, phrased for the person who asked.
public enum ProcessActionOutcome: Equatable, Sendable {
    case requested
    case failed(reason: String)
}

/// Quits, signals and renices processes by identity; never by a bare PID.
public struct ProcessController: Sendable {
    /// Lowered priority for work that should yield to everything else.
    public static let lowPriorityNice: Int32 = 10
    private let driver: any ProcessTerminating
    private let signaler: any ProcessSignaling

    public init() { self.init(driver: ProcessControlDriver()) }

    init(driver: any ProcessTerminating, signaler: any ProcessSignaling = ProcessControlDriver()) {
        self.driver = driver
        self.signaler = signaler
    }

    public func send(_ signal: ProcessSignalIntent, to identity: ProcessIdentity) -> ProcessActionOutcome {
        outcome(signaler.send(
            signal, pid: identity.pid, startSeconds: identity.startSeconds, startMicroseconds: identity.startMicroseconds
        ))
    }

    /// Only lowering: raising priority again needs an administrator.
    public func lowerPriority(of identity: ProcessIdentity) -> ProcessActionOutcome {
        outcome(signaler.renice(
            pid: identity.pid, startSeconds: identity.startSeconds, startMicroseconds: identity.startMicroseconds,
            to: Self.lowPriorityNice
        ))
    }

    private func outcome(_ result: Result<Void, ProcessControlError>) -> ProcessActionOutcome {
        switch result {
        case .success: .requested
        case .failure(let error): .failed(reason: Self.reason(error))
        }
    }

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
        case .needsAdministrator: "Its priority was not changed; only an administrator can change it"
        case .refusedByApp: "The app could not be asked to quit"
        case .systemCall(let code): "The request failed (\(code))"
        }
    }
}
