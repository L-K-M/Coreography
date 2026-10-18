import CoreographyDrivers

enum MemoryDerivationError: Error {
    case invalidCapacity
    case inconsistentCounters
    case overflow
}

enum MemoryFootprint {
    /// Match the documented VM composition without clamping invalid reads to zero.
    static func usedBytes(from pages: MemoryPages, physicalBytes: UInt64) throws -> UInt64 {
        guard pages.pageSizeBytes > 0, physicalBytes > 0 else {
            throw MemoryDerivationError.invalidCapacity
        }

        let residentCounts = [
            pages.active, pages.inactive, pages.speculative,
            pages.wired, pages.compressed
        ]
        var usedPages: UInt64 = 0
        for count in residentCounts {
            let addition = usedPages.addingReportingOverflow(count)
            guard !addition.overflow else { throw MemoryDerivationError.overflow }
            usedPages = addition.partialValue
        }

        for count in [pages.purgeable, pages.fileBacked] {
            let subtraction = usedPages.subtractingReportingOverflow(count)
            guard !subtraction.overflow else {
                throw MemoryDerivationError.inconsistentCounters
            }
            usedPages = subtraction.partialValue
        }

        let bytes = usedPages.multipliedReportingOverflow(by: pages.pageSizeBytes)
        guard !bytes.overflow else { throw MemoryDerivationError.overflow }
        guard bytes.partialValue <= physicalBytes else {
            throw MemoryDerivationError.inconsistentCounters
        }
        return bytes.partialValue
    }
}
