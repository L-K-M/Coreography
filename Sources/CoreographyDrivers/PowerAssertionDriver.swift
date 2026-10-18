import Foundation

#if os(macOS)
import IOKit
import IOKit.pwr_mgt
#endif

/// One active power assertion as powerd reports it.
public struct RawAssertion: Equatable, Sendable {
    public let pid: Int32
    /// The assertion type, e.g. `PreventUserIdleSystemSleep`.
    public let type: String
    /// What the holder said it is for, e.g. `Playing audio`.
    public let name: String?
    public let since: Date?

    public init(pid: Int32, type: String, name: String?, since: Date?) {
        self.pid = pid
        self.type = type
        self.name = name
        self.since = since
    }
}

public enum PowerAssertionError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case systemCall(code: Int32)
}

public protocol PowerAssertionReading: Sendable {
    func read() async -> Result<[RawAssertion], PowerAssertionError>
}

/// Reads every process's power assertions in one public IOKit call to
/// powerd (`IOPMCopyAssertionsByProcess`), cheap enough to run with each
/// process sample.
public struct PowerAssertionDriver: PowerAssertionReading {
    public init() {}

    public func read() async -> Result<[RawAssertion], PowerAssertionError> {
        #if os(macOS)
        var byProcess: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&byProcess)
        guard status == kIOReturnSuccess else { return .failure(.systemCall(code: status)) }
        guard let dictionary = byProcess?.takeRetainedValue() as NSDictionary? else { return .success([]) }
        var decoded: [Int32: [[String: Any]]] = [:]
        for (key, value) in dictionary {
            guard let pid = (key as? NSNumber)?.int32Value, let list = value as? [[String: Any]] else { continue }
            decoded[pid] = list
        }
        return .success(PowerAssertionDecoder.assertions(decoded))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }
}

/// Decodes powerd's assertion dictionaries (IOPMLib.h keys).
public enum PowerAssertionDecoder {
    private static let typeKey = "AssertType"
    private static let nameKey = "AssertName"
    private static let levelKey = "AssertLevel"
    private static let startKey = "AssertStartWhen"
    /// kIOPMAssertionLevelOff: tracked but released.
    private static let levelOff = 0

    public static func assertions(_ byProcess: [Int32: [[String: Any]]]) -> [RawAssertion] {
        byProcess.flatMap { pid, list in
            list.compactMap { entry -> RawAssertion? in
                guard let type = entry[typeKey] as? String else { return nil }
                if let level = (entry[levelKey] as? NSNumber)?.intValue, level == levelOff { return nil }
                return RawAssertion(pid: pid, type: type, name: entry[nameKey] as? String, since: entry[startKey] as? Date)
            }
        }
        .sorted { ($0.pid, $0.type) < ($1.pid, $1.type) }
    }
}
