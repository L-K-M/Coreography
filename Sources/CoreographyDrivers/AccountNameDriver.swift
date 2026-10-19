import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Account names from the user database (`getpwuid_r`); no privilege needed.
public protocol AccountNameReading: Sendable {
    /// The short account name, or nil when the UID has no account.
    func name(of uid: UInt32) -> String?
}

public struct AccountNameDriver: AccountNameReading {
    /// Enough for any passwd entry; the call says so when it is not.
    private static let bufferBytes = 16 * 1024

    public init() {}

    public func name(of uid: UInt32) -> String? {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: Self.bufferBytes)
        guard getpwuid_r(uid_t(uid), &entry, &buffer, buffer.count, &result) == 0,
              result != nil, let name = entry.pw_name else { return nil }
        let text = String(cString: name)
        return text.isEmpty ? nil : text
    }
}
