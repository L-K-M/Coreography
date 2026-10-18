import Foundation

public struct ProcessIdentity: Hashable, Codable, Sendable {
    public let pid: Int32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64

    public init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) throws {
        guard pid >= 0, startMicroseconds < 1_000_000 else {
            throw ProcessIdentityError.invalidIdentity
        }
        self.pid = pid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
    }

    private enum CodingKeys: String, CodingKey { case pid, startSeconds, startMicroseconds }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            pid: values.decode(Int32.self, forKey: .pid),
            startSeconds: values.decode(UInt64.self, forKey: .startSeconds),
            startMicroseconds: values.decode(UInt64.self, forKey: .startMicroseconds)
        )
    }
}

enum ProcessIdentityError: Error { case invalidIdentity }

public struct ProcessReading: Identifiable, Codable, Sendable {
    public let id: ProcessIdentity
    public let parentPID: UInt32
    public let uid: UInt32
    public let name: String
    public let stamp: SampleStamp
    public let cpuPercentOfMachine: MetricReading
    public let memoryFootprintBytes: MetricReading
    public let diskReadBytesPerSecond: MetricReading
    public let diskWriteBytesPerSecond: MetricReading
    public let executablePath: String?
    /// PID the OS holds responsible (e.g. Safari for a WebContent helper).
    /// A bare PID; consumers must check it against a live identity.
    public let responsiblePID: Int32?
}

public struct ProcessCollectionIssue: Codable, Sendable {
    public let pid: Int32
    public let reading: MetricReading
}

public struct ProcessSnapshot: Codable, Sendable {
    public let stamp: SampleStamp
    public let collectorPID: Int32
    public let enumeration: MetricReading
    public let enumerationTruncated: Bool
    public let processes: [ProcessReading]
    public let issues: [ProcessCollectionIssue]
    public let continuity: SamplingContinuity

    public var restrictedUsageCount: Int {
        processes.filter { $0.cpuPercentOfMachine.availability == .restricted }.count
    }
}
