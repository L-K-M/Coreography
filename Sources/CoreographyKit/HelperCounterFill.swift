import Foundation
import CoreographyDrivers

/// Completes a process sample with counters only the privileged helper can
/// read, such as other users' processes, when it is installed and answering.
///
/// ```text
/// ProcessStatisticsDriver ──sample──> restricted rows? ──PIDs──> PrivilegedHelper (root)
///                                         <── counters for the same PID and start time
/// ```
/// A row whose start time differs is a reused PID and stays restricted.
struct HelperCounterFill: ProcessSampleReading {
    private let base: any ProcessSampleReading
    private let helper: PrivilegedHelper

    init(base: any ProcessSampleReading, helper: PrivilegedHelper) {
        self.base = base
        self.helper = helper
    }

    func read() async -> RawProcessSnapshot {
        let raw = await base.read()
        guard case .success(let enumeration) = raw.enumeration else { return raw }

        let restricted = enumeration.processes.filter(\.isRestricted).map(\.pid)
        guard let filled = await helper.counters(for: Array(restricted.prefix(HelperWire.maximumPIDs))),
              !filled.isEmpty else { return raw }

        let byPID = Dictionary(filled.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let processes = enumeration.processes.map { process in
            guard process.isRestricted, let counters = byPID[process.pid],
                  counters.startSeconds == process.startSeconds,
                  counters.startMicroseconds == process.startMicroseconds else { return process }
            return process.filled(from: counters)
        }
        return RawProcessSnapshot(
            clockID: raw.clockID, monotonicNanoseconds: raw.monotonicNanoseconds, wallTime: raw.wallTime,
            logicalCPUCount: raw.logicalCPUCount, collectorPID: raw.collectorPID,
            enumeration: .success(ProcessEnumeration(
                processes: processes, failures: enumeration.failures, isTruncated: enumeration.isTruncated
            ))
        )
    }
}

private extension RawProcessInfo {
    var isRestricted: Bool {
        guard case .failure(.restricted) = counters else { return false }
        return true
    }

    /// The helper's counters, read at its own time so rates stay exact.
    func filled(from helper: IdentifiedProcessCounters) -> RawProcessInfo {
        let threads: Result<Int, ProcessDriverError> = switch (self.threads, helper.threads) {
        case (.failure, .some(let count)): .success(count)
        default: self.threads
        }
        return RawProcessInfo(
            pid: pid, parentPID: parentPID, uid: uid, startSeconds: startSeconds, startMicroseconds: startMicroseconds,
            name: name, monotonicNanoseconds: helper.monotonicNanoseconds, counters: .success(helper.counters),
            executablePath: executablePath, responsiblePID: responsiblePID, threads: threads, cpuType: cpuType
        )
    }
}
