import Foundation
import CoreographyDrivers

/// Account names by UID, each read once: they do not change while the app
/// runs, and a process list holds only a few distinct UIDs.
public final class AccountDirectory: @unchecked Sendable {
    private let reader: any AccountNameReading
    private let lock = NSLock()
    /// nil marks a UID already looked up without an account.
    private var cache: [UInt32: String?] = [:]

    public convenience init() { self.init(reader: AccountNameDriver()) }

    init(reader: any AccountNameReading) { self.reader = reader }

    /// The names of the UIDs that have one.
    public func names(for uids: Set<UInt32>) -> [UInt32: String] {
        lock.withLock {
            var names: [UInt32: String] = [:]
            for uid in uids {
                if cache[uid] == nil { cache[uid] = .some(reader.name(of: uid)) }
                if let name = cache[uid] ?? nil { names[uid] = name }
            }
            return names
        }
    }
}
