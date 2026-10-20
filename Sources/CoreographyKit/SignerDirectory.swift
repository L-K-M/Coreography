import Foundation
import CoreographyDrivers

/// Who signed each program, by executable path, for the process table's
/// signer column. A program's signature does not change while it sits on
/// disk, so each path is checked once; an unreadable one is checked again
/// next time, since the program may have been mid-update.
public actor SignerDirectory {
    private let driver: any ProcessDetailReading
    private var cache: [String: ProcessSigner] = [:]

    public init() { self.init(driver: ProcessDetailDriver()) }

    init(driver: any ProcessDetailReading) { self.driver = driver }

    /// Checks running at once: a column shown for the first time fills in
    /// without one slow bundle holding up the rest, nor hundreds of disk reads at once.
    private static let concurrentChecks = 4

    /// The signers of the paths that could be checked.
    public func signers(for paths: Set<String>) async -> [String: ProcessSigner] {
        var signers = cache.filter { paths.contains($0.key) }
        var unchecked = paths.filter { cache[$0] == nil }.makeIterator()
        let driver = self.driver

        await withTaskGroup(of: (String, ProcessSigner).self) { group in
            func checkNext() {
                guard let path = unchecked.next() else { return }
                group.addTask { (path, ProcessSigner(await driver.signing(path: path))) }
            }

            for _ in 0..<Self.concurrentChecks { checkNext() }
            while let (path, signer) = await group.next() {
                checkNext()
                guard signer != .unknown else { continue }
                cache[path] = signer
                signers[path] = signer
            }
        }
        return signers
    }
}
