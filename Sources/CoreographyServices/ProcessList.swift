import Foundation
import CoreographyKit

public typealias CapturedProcesses = ProcessSnapshot
public typealias ObservedProcess = ProcessReading

public enum ProcessSort: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, diskRead, diskWrite, name

    public var id: Self { self }
}

enum ProcessList {
    static func rows(
        in snapshot: CapturedProcesses?, matching filter: String, sortedBy sort: ProcessSort
    ) -> [ObservedProcess] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = (snapshot?.processes ?? []).filter { matches($0, query: query) }
        return rows.sorted { lhs, rhs in
            if sort == .name {
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
            } else {
                let left = value(lhs, sort: sort)
                let right = value(rhs, sort: sort)
                if left != right {
                    if let left, let right { return left > right }
                    return left != nil
                }
            }
            return lhs.id.pid < rhs.id.pid
        }
    }

    /// Match a trimmed query against name, PID or UID; empty matches all.
    static func matches(_ process: ObservedProcess, query: String) -> Bool {
        query.isEmpty || process.name.localizedCaseInsensitiveContains(query)
            || String(process.id.pid).contains(query) || String(process.uid).contains(query)
    }

    private static func value(_ row: ObservedProcess, sort: ProcessSort) -> Double? {
        switch sort {
        case .cpu: row.cpuPercentOfMachine.numericValue
        case .memory: row.memoryFootprintBytes.numericValue
        case .diskRead: row.diskReadBytesPerSecond.numericValue
        case .diskWrite: row.diskWriteBytesPerSecond.numericValue
        case .name: nil
        }
    }
}
