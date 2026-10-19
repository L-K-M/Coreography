import Foundation
import CoreographyDrivers

/// Account names by UID, each read once: they do not change while the app
/// runs, and a process list holds only a few distinct UIDs. A lookup the
/// user database could not answer is tried again next time.
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
                // An answer, account or none, is kept; a failure is not.
                if cache[uid] == nil {
                    do { cache[uid] = .some(try reader.name(of: uid)) } catch {}
                }
                if let name = cache[uid] ?? nil { names[uid] = name }
            }
            return names
        }
    }
}
