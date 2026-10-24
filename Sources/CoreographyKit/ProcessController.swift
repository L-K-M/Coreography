import Foundation
import CoreographyDrivers

public typealias ProcessQuitMode = ProcessTermination
public typealias ProcessSignalIntent = ProcessSignal

/// The result of one quit request, phrased for the person who asked.
public enum ProcessActionOutcome: Equatable, Sendable {
    case requested
    case failed(reason: String)
    /// Refused for permission: another user's process, or a priority only
    /// root may raise. The privileged helper may be able to do it.
    case notPermitted(reason: String)
}

/// Quits, signals and renices processes by identity; never by a bare PID.
public struct ProcessController: Sendable {
    /// Lowered priority for work that should yield to everything else.
    public static let lowPriorityNice: Int32 = 10
    /// Raised priority for work that should run first; only root may set it.
    public static let highPriorityNice: Int32 = -10
    private let driver: any ProcessTerminating
    private let signaler: any ProcessSignaling
    private let helper: PrivilegedHelper?

    public init() { self.init(driver: ProcessControlDriver(), helper: .shared) }

    init(driver: any ProcessTerminating, signaler: any ProcessSignaling = ProcessControlDriver(), helper: PrivilegedHelper? = nil) {
        self.driver = driver
        self.signaler = signaler
        self.helper = helper
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

    /// Raising is never permitted to the app, so the answer is a refusal the
    /// caller may retry through the helper.
    public func raisePriority(of identity: ProcessIdentity) -> ProcessActionOutcome {
        outcome(signaler.renice(
            pid: identity.pid, startSeconds: identity.startSeconds, startMicroseconds: identity.startMicroseconds,
            to: Self.highPriorityNice
        ))
    }

    /// Whether refusals for permission can be retried through the helper.
    public var canAskHelper: Bool { helper != nil }

    /// The same requests through the privileged helper, after a refusal for
    /// permission; nil while it is not installed, approved and answering.
    /// A quit is a plain SIGTERM there: the helper has no session to ask an app in.
    public func sendThroughHelper(_ signal: ProcessSignalIntent, to identity: ProcessIdentity) async -> ProcessActionOutcome? {
        let request: HelperSignal = switch signal {
        case .suspend: .suspend
        case .resume: .resume
        case .hangUp: .hangUp
        case .interrupt: .interrupt
        case .user1: .user1
        case .user2: .user2
        case .info: .info
        }
        return await act(.signal(process: identity.helperIdentity, signal: request))
    }

    public func terminateThroughHelper(_ identity: ProcessIdentity, mode: ProcessQuitMode) async -> ProcessActionOutcome? {
        await act(.signal(process: identity.helperIdentity, signal: mode == .forced ? .kill : .terminate))
    }

    public func lowerPriorityThroughHelper(of identity: ProcessIdentity) async -> ProcessActionOutcome? {
        await act(.renice(process: identity.helperIdentity, niceValue: Self.lowPriorityNice))
    }

    public func raisePriorityThroughHelper(of identity: ProcessIdentity) async -> ProcessActionOutcome? {
        await act(.renice(process: identity.helperIdentity, niceValue: Self.highPriorityNice))
    }

    private func act(_ request: HelperRequest) async -> ProcessActionOutcome? {
        switch await helper?.act(request) {
        case nil: nil
        case .success: .requested
        case .failure(let failure): .failed(reason: Self.reason(failure))
        }
    }

    private func outcome(_ result: Result<Void, ProcessControlError>) -> ProcessActionOutcome {
        switch result {
        case .success: .requested
        case .failure(let error) where error == .notPermitted || error == .needsAdministrator: .notPermitted(reason: Self.reason(error))
        case .failure(let error): .failed(reason: Self.reason(error))
        }
    }

    @MainActor
    public func terminate(_ identity: ProcessIdentity, mode: ProcessQuitMode) -> ProcessActionOutcome {
        let result = driver.terminate(
            pid: identity.pid, startSeconds: identity.startSeconds,
            startMicroseconds: identity.startMicroseconds, mode: mode
        )
        return outcome(result)
    }

    private static func reason(_ failure: HelperActionFailure) -> String {
        switch failure {
        case .exited: reason(ProcessControlError.exited)
        case .identityChanged: reason(ProcessControlError.identityChanged)
        case .invalidTarget: reason(ProcessControlError.invalidTarget)
        case .notPermitted: "Not permitted even for the privileged helper: the process is protected"
        case .failed: "The privileged helper could not send the request"
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
