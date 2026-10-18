import Foundation
import CoreFoundation

enum DiskStatisticsDecoder {
    // IOStorageFamily/IOBlockStorageDriver.h defines these byte-counter keys.
    private static let readKey = "Bytes (Read)"
    private static let writeKey = "Bytes (Write)"

    static func counters(_ statistics: [String: Any]) -> Result<DiskByteCounters, DiskDriverError> {
        guard let read = unsignedCounter(statistics[readKey]) else {
            return .failure(.unavailable(reason: "Missing or invalid \(readKey) storage counter"))
        }
        guard let written = unsignedCounter(statistics[writeKey]) else {
            return .failure(.unavailable(reason: "Missing or invalid \(writeKey) storage counter"))
        }
        return .success(DiskByteCounters(readBytes: read, writtenBytes: written))
    }

    private static func unsignedCounter(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
        // NSNumber is toll-free bridged only after its CF type has been checked.
        let native = unsafeBitCast(number, to: CFNumber.self)
        guard !CFNumberIsFloatType(native) else { return nil }
        return number as? UInt64
    }
}
