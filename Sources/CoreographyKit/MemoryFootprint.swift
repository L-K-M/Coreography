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

    /// Activity Monitor's App Memory: used minus wired and compressed.
    ///
    /// Example: 210 resident pages - 5 purgeable - 25 file-backed = 180 used;
    /// 180 - 20 wired - 30 compressed = 130 app pages.
    static func appBytes(from pages: MemoryPages, physicalBytes: UInt64) throws -> UInt64 {
        let used = try usedBytes(from: pages, physicalBytes: physicalBytes)
        let wired = try bytes(pages.wired, pageSize: pages.pageSizeBytes)
        let compressed = try bytes(pages.compressed, pageSize: pages.pageSizeBytes)
        let (withoutWired, wiredUnderflow) = used.subtractingReportingOverflow(wired)
        let (app, compressedUnderflow) = withoutWired.subtractingReportingOverflow(compressed)
        guard !wiredUnderflow, !compressedUnderflow else {
            throw MemoryDerivationError.inconsistentCounters
        }
        return app
    }

    /// Cached files: purgeable plus file-backed pages the system can reclaim.
    static func cachedBytes(from pages: MemoryPages, physicalBytes: UInt64) throws -> UInt64 {
        let (cachedPages, overflow) = pages.purgeable.addingReportingOverflow(pages.fileBacked)
        guard !overflow else { throw MemoryDerivationError.overflow }
        let cached = try bytes(cachedPages, pageSize: pages.pageSizeBytes)
        guard cached <= physicalBytes else { throw MemoryDerivationError.inconsistentCounters }
        return cached
    }

    static func bytes(_ count: UInt64, pageSize: UInt64) throws -> UInt64 {
        guard pageSize > 0 else { throw MemoryDerivationError.invalidCapacity }
        let (bytes, overflow) = count.multipliedReportingOverflow(by: pageSize)
        guard !overflow else { throw MemoryDerivationError.overflow }
        return bytes
    }
}
