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

    /// The names of the UIDs that have one, and the UIDs to ask about again.
    public func lookup(_ uids: Set<UInt32>) -> AccountLookup {
        lock.withLock {
            var lookup = AccountLookup(names: [:], unanswered: [])
            for uid in uids {
                // An answer, account or none, is kept; a failure is not.
                if cache[uid] == nil {
                    do { cache[uid] = .some(try reader.name(of: uid)) } catch { lookup.unanswered.insert(uid) }
                }
                if let name = cache[uid] ?? nil { lookup.names[uid] = name }
            }
            return lookup
        }
    }
}

public struct AccountLookup: Equatable, Sendable {
    public var names: [UInt32: String]
    /// UIDs the user database failed to answer for, as opposed to UIDs without an account.
    public var unanswered: Set<UInt32>
}
