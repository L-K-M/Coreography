import Foundation
import CoreographyDrivers

/// Caches answers and misses while peers remain connected. Retired peers
/// leave the cache, bounding it to the current table rather than uptime.
public actor ServerNameResolver {
    /// More addresses than this wait for the next pass; each lookup can block.
    public static let batchLimit = 64
    private static let concurrentLimit = 4
    private let driver: any ServerNameResolving
    /// nil values mean "asked, no name": never asked twice.
    private var cache: [String: String?] = [:]

    public init() { self.init(driver: ServerNameDriver()) }

    init(driver: any ServerNameResolving) { self.driver = driver }

    /// Hostnames by address, freshly resolved where needed. The returned
    /// dictionary covers only the requested peers, including cached answers.
    @discardableResult
    public func resolve(_ addresses: [String]) async -> [String: String] {
        let peers = Set(addresses)
        cache = cache.filter { peers.contains($0.key) }
        let unique = peers.sorted()
        var unknown = unique.filter { cache[$0] == nil }
        if unknown.count > Self.batchLimit { unknown = Array(unknown.prefix(Self.batchLimit)) }
        if !unknown.isEmpty {
            let found = await withTaskGroup(of: (String, String?).self) { group in
                var remaining = unknown.makeIterator()
                let driver = driver
                for _ in 0..<Self.concurrentLimit {
                    guard let address = remaining.next() else { break }
                    group.addTask { (address, await driver.lookup(address)) }
                }
                var results: [(String, String?)] = []
                while let result = await group.next() {
                    results.append(result)
                    if !Task.isCancelled, let address = remaining.next() {
                        group.addTask { (address, await driver.lookup(address)) }
                    }
                }
                return results
            }
            if !Task.isCancelled {
                for (address, name) in found { cache[address] = name }
            }
        }
        return cache.reduce(into: [:]) { names, entry in
            if let name = entry.value { names[entry.key] = name }
        }
    }
}
