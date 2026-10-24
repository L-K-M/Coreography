import Foundation
import CoreographyDrivers

/// Resolves connection peers to hostnames, once each: answered and
/// unanswerable addresses are both cached so a busy table does not re-ask.
/// Lookups are blocking DNS calls run in a bounded batch.
public actor ServerNameResolver {
    /// More addresses than this wait for the next pass; each lookup can block.
    public static let batchLimit = 64
    private let driver: any ServerNameResolving
    /// nil values mean "asked, no name": never asked twice.
    private var cache: [String: String?] = [:]

    public init() { self.init(driver: ServerNameDriver()) }

    init(driver: any ServerNameResolving) { self.driver = driver }

    /// Hostnames by address, freshly resolved where needed. The returned
    /// dictionary covers every address ever answered, not just this batch.
    @discardableResult
    public func resolve(_ addresses: [String]) async -> [String: String] {
        let unique = Array(Set(addresses))
        var unknown = unique.filter { cache[$0] == nil }
        if unknown.count > Self.batchLimit { unknown = Array(unknown.prefix(Self.batchLimit)) }
        if !unknown.isEmpty {
            let found = await withTaskGroup(of: (String, String?).self) { group in
                for address in unknown {
                    group.addTask { (address, await self.driver.lookup(address)) }
                }
                var results: [(String, String?)] = []
                for await result in group { results.append(result) }
                return results
            }
            for (address, name) in found { cache[address] = name }
        }
        return cache.reduce(into: [:]) { names, entry in
            if let name = entry.value { names[entry.key] = name }
        }
    }
}
