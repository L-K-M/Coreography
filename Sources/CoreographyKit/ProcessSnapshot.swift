import Foundation
import CoreographyDrivers

public struct ProcessIdentity: Hashable, Codable, Sendable {
    public let pid: Int32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64

    /// When the process started, on the wall clock.
    public var startTime: Date {
        Date(timeIntervalSince1970: Double(startSeconds) + Double(startMicroseconds) / 1_000_000)
    }

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

/// The code a process runs (plan: opt-in architecture column).
public enum ProcessArchitecture: String, Codable, Sendable {
    case appleSilicon
    case intel
    /// Intel code that Rosetta translates on Apple silicon.
    case intelTranslated
}

/// The QoS class a CPU-time slice ran under (plan: opt-in QoS column).
/// rusage_info_v6 splits a process's CPU time across these classes;
/// the case order and raw values mirror the driver's ProcessQoSClass.
public enum ProcessQoS: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case userInteractive
    case userInitiated
    case `default`
    case utility
    case background
    case maintenance
    /// Threads under the pre-QoS scheduler policy.
    case legacy

    init(_ driverClass: ProcessQoSClass) {
        switch driverClass {
        case .userInteractive: self = .userInteractive
        case .userInitiated: self = .userInitiated
        case .default: self = .default
        case .utility: self = .utility
        case .background: self = .background
        case .maintenance: self = .maintenance
        case .legacy: self = .legacy
        }
    }
}

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
    /// Package-idle and interrupt wakeups per second (plan: wakeups beside CPU).
    public let wakeupsPerSecond: MetricReading
    /// GPU time the process's command queues used, in ms per second; not a busy %.
    public let gpuMillisecondsPerSecond: MetricReading
    /// CPU power the kernel's energy model attributes to the process; an estimate.
    public let cpuPowerWatts: MetricReading
    /// User plus system CPU time over the process's life, in seconds.
    public let cpuTimeSeconds: MetricReading
    /// Threads the process has now (plan: opt-in threads column).
    public let threadCount: MetricReading
    /// Retired instructions per second over the sample interval (plan:
    /// opt-in instructions column).
    public let instructionsPerSecond: MetricReading
    /// CPU percent of the machine per QoS class over the interval, on the
    /// cpuPercentOfMachine scale; nil when the counters could not be read.
    public let qosCPUPercent: [ProcessQoS: MetricReading]?
    /// Nil when the OS did not say; it never changes while the process runs.
    public let architecture: ProcessArchitecture?
    public let executablePath: String?
    /// PID the OS holds responsible (e.g. Safari for a WebContent helper).
    /// A bare PID; consumers must check it against a live identity.
    public let responsiblePID: Int32?

    /// Wakeups, GPU and power default to "not collected" for readings built without them.
    init(
        id: ProcessIdentity, parentPID: UInt32, uid: UInt32, name: String, stamp: SampleStamp,
        cpuPercentOfMachine: MetricReading, memoryFootprintBytes: MetricReading,
        diskReadBytesPerSecond: MetricReading, diskWriteBytesPerSecond: MetricReading,
        wakeupsPerSecond: MetricReading = .unsupported(reason: "Wakeups were not collected"),
        gpuMillisecondsPerSecond: MetricReading = .unsupported(reason: "GPU time was not collected"),
        cpuPowerWatts: MetricReading = .unsupported(reason: "Energy was not collected"),
        cpuTimeSeconds: MetricReading = .unsupported(reason: "CPU time was not collected"),
        threadCount: MetricReading = .unsupported(reason: "Threads were not collected"),
        instructionsPerSecond: MetricReading = .unsupported(reason: "Instructions were not collected"),
        qosCPUPercent: [ProcessQoS: MetricReading]? = nil,
        architecture: ProcessArchitecture? = nil,
        executablePath: String?, responsiblePID: Int32?
    ) {
        self.id = id
        self.parentPID = parentPID
        self.uid = uid
        self.name = name
        self.stamp = stamp
        self.cpuPercentOfMachine = cpuPercentOfMachine
        self.memoryFootprintBytes = memoryFootprintBytes
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.wakeupsPerSecond = wakeupsPerSecond
        self.gpuMillisecondsPerSecond = gpuMillisecondsPerSecond
        self.cpuPowerWatts = cpuPowerWatts
        self.cpuTimeSeconds = cpuTimeSeconds
        self.threadCount = threadCount
        self.instructionsPerSecond = instructionsPerSecond
        self.qosCPUPercent = qosCPUPercent
        self.architecture = architecture
        self.executablePath = executablePath
        self.responsiblePID = responsiblePID
    }
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

    /// Threads across the processes whose count was read, and how many were not.
    public var threadTotal: (threads: Int, unread: Int) {
        let counts = processes.map { $0.threadCount.numericValue }
        return (counts.compactMap { $0 }.reduce(0) { $0 + Int($1) }, counts.filter { $0 == nil }.count)
    }
}

extension ProcessIdentity {
    /// The same process as the privileged helper names it.
    var helperIdentity: HelperProcessIdentity {
        HelperProcessIdentity(pid: pid, startSeconds: startSeconds, startMicroseconds: startMicroseconds)
    }
}
