import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// The user database could not answer, which is not the same as "no account".
public struct AccountLookupError: Error, Equatable, Sendable {
    public let code: Int32
}

/// Account names from the user database (`getpwuid_r`); no privilege needed.
public protocol AccountNameReading: Sendable {
    /// The short account name, or nil when the UID has no account.
    func name(of uid: UInt32) throws -> String?
}

public struct AccountNameDriver: AccountNameReading {
    /// Enough for any passwd entry; the call says so when it is not.
    private static let bufferBytes = 16 * 1024

    public init() {}

    public func name(of uid: UInt32) throws -> String? {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: Self.bufferBytes)
        let code = getpwuid_r(uid_t(uid), &entry, &buffer, buffer.count, &result)
        guard code == 0 else { throw AccountLookupError(code: code) }
        guard result != nil, let name = entry.pw_name else { return nil }
        let text = String(cString: name)
        return text.isEmpty ? nil : text
    }
}
