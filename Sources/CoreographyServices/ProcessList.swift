import Foundation
import CoreographyKit

public typealias CapturedProcesses = ProcessSnapshot
public typealias ObservedProcess = ProcessReading

public enum ProcessSort: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, diskRead, diskWrite, network, gpu, power, name
    /// Most lifetime CPU time first.
    case cpuTime
    /// Newest first.
    case started

    public var id: Self { self }
}

enum ProcessList {
    static func rows(
        in snapshot: CapturedProcesses?, matching filter: String, sortedBy sort: ProcessSort,
        isNew: (ProcessIdentity) -> Bool = { _ in false }, facts: ProcessFacts = ProcessFacts(),
        appNames: [ProcessIdentity: String] = [:]
    ) -> [ObservedProcess] {
        let parsed = ProcessFilter.parse(filter)
        // Text matches a process's app as in grouped mode, so both modes hold the same processes.
        let rows = (snapshot?.processes ?? []).filter {
            parsed.matches($0, isNew: isNew($0.id), appName: appNames[$0.id], facts: facts)
        }
        return rows.sorted { lhs, rhs in
            if sort == .name {
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
            } else {
                let left = value(lhs, sort: sort, facts: facts)
                let right = value(rhs, sort: sort, facts: facts)
                if left != right {
                    if let left, let right { return left > right }
                    return left != nil
                }
            }
            return lhs.id.pid < rhs.id.pid
        }
    }

    private static func value(_ row: ObservedProcess, sort: ProcessSort, facts: ProcessFacts) -> Double? {
        if sort == .network {
            let rates = ProcessNetwork.rates(for: row, in: facts.traffic)
            return ProcessNetwork.total(rates.received, rates.sent)
        }
        return switch sort {
        case .cpu: row.cpuPercentOfMachine.numericValue
        case .memory: row.memoryFootprintBytes.numericValue
        case .diskRead: row.diskReadBytesPerSecond.numericValue
        case .diskWrite: row.diskWriteBytesPerSecond.numericValue
        case .gpu: row.gpuMillisecondsPerSecond.numericValue
        case .power: row.cpuPowerWatts.numericValue
        case .cpuTime: row.cpuTimeSeconds.numericValue
        case .started: row.id.startTime.timeIntervalSince1970
        case .name, .network: nil
        }
    }
}
