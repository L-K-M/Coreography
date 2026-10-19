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

    /// The signers of the paths that could be checked.
    public func signers(for paths: Set<String>) async -> [String: ProcessSigner] {
        var signers: [String: ProcessSigner] = [:]
        for path in paths {
            if let known = cache[path] {
                signers[path] = known
                continue
            }
            let signer = ProcessSigner(await driver.signing(path: path))
            guard signer != .unknown else { continue }
            cache[path] = signer
            signers[path] = signer
        }
        return signers
    }
}
