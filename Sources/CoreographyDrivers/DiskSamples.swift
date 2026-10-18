import Foundation

public enum DiskDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case unavailable(reason: String)
    case restricted(code: Int32)
    case systemCall(operation: String, code: Int32)
}

public struct DiskByteCounters: Equatable, Sendable {
    public let readBytes: UInt64
    public let writtenBytes: UInt64

    public init(readBytes: UInt64, writtenBytes: UInt64) {
        self.readBytes = readBytes
        self.writtenBytes = writtenBytes
    }
}

public struct RawDiskDevice: Sendable {
    public let registryEntryID: UInt64
    public let name: String
    public let monotonicNanoseconds: UInt64
    public let counters: Result<DiskByteCounters, DiskDriverError>

    public init(
        registryEntryID: UInt64, name: String, monotonicNanoseconds: UInt64,
        counters: Result<DiskByteCounters, DiskDriverError>
    ) {
        self.registryEntryID = registryEntryID
        self.name = name
        self.monotonicNanoseconds = monotonicNanoseconds
        self.counters = counters
    }
}

public struct DiskReadFailure: Sendable {
    public let registryEntryID: UInt64?
    public let error: DiskDriverError

    public init(registryEntryID: UInt64?, error: DiskDriverError) {
        self.registryEntryID = registryEntryID
        self.error = error
    }
}

public struct DiskEnumeration: Sendable {
    public let devices: [RawDiskDevice]
    public let failures: [DiskReadFailure]
    public let isTruncated: Bool

    public init(
        devices: [RawDiskDevice], failures: [DiskReadFailure] = [], isTruncated: Bool = false
    ) {
        self.devices = devices
        self.failures = failures
        self.isTruncated = isTruncated
    }
}

public struct RawDiskSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let enumeration: Result<DiskEnumeration, DiskDriverError>

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date,
        enumeration: Result<DiskEnumeration, DiskDriverError>
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.enumeration = enumeration
    }
}

public protocol DiskSampleReading: Sendable {
    func read() async -> RawDiskSnapshot
}
