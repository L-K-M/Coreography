import Foundation
import CoreographyDrivers

/// What an assertion holds off.
public enum AssertionEffect: String, Codable, Sendable {
    case preventsSystemSleep, preventsDisplaySleep, other
}

/// One active power assertion (plan P2: sleep assertions by process, with age).
public struct SleepAssertion: Codable, Identifiable, Sendable {
    public let pid: Int32
    public let type: String
    public let name: String?
    public let since: Date?
    public let effect: AssertionEffect

    public var id: String { "\(pid)-\(type)-\(name ?? "")" }
}

public struct AssertionSnapshot: Sendable {
    public let takenAt: Date
    public let assertions: [SleepAssertion]
    /// Why nothing could be read, e.g. off macOS.
    public let unavailableReason: String?

    /// PIDs holding the Mac or its display awake. Assertions name a PID
    /// only, so they are matched to the processes observed at the same time.
    public var sleepPreventers: Set<Int32> {
        Set(assertions.filter { $0.effect != .other }.map(\.pid))
    }
}

/// Reads live assertions; past ones are never reconstructed (plan).
public struct AssertionReader: Sendable {
    // Types that hold off idle system sleep or display sleep (IOPMLib.h and powerd's internal names).
    private static let systemSleep: Set<String> = [
        "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion", "InternalPreventSleep"
    ]
    private static let displaySleep: Set<String> = [
        "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion", "InternalPreventDisplaySleep"
    ]
    private let driver: any PowerAssertionReading

    public init() { self.init(driver: PowerAssertionDriver()) }

    init(driver: any PowerAssertionReading) { self.driver = driver }

    public func read(at time: Date = Date()) async -> AssertionSnapshot {
        switch await driver.read() {
        case .success(let raw):
            return AssertionSnapshot(takenAt: time, assertions: raw.map(Self.assertion), unavailableReason: nil)
        case .failure(.unsupportedPlatform):
            return AssertionSnapshot(takenAt: time, assertions: [], unavailableReason: "Power assertions need macOS")
        case .failure(.systemCall(let code)):
            return AssertionSnapshot(takenAt: time, assertions: [], unavailableReason: "powerd did not answer (\(code))")
        }
    }

    private static func assertion(_ raw: RawAssertion) -> SleepAssertion {
        let effect: AssertionEffect = systemSleep.contains(raw.type) ? .preventsSystemSleep
            : displaySleep.contains(raw.type) ? .preventsDisplaySleep : .other
        return SleepAssertion(pid: raw.pid, type: raw.type, name: raw.name, since: raw.since, effect: effect)
    }
}
