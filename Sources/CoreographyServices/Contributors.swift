import Foundation
import CoreographyKit

/// One app's share of a subsystem at one process sample.
public struct Contributor: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let value: Double
    /// Lower bounds and footprint sums are estimates; the UI marks them.
    public let isEstimate: Bool
}

/// The leading apps per subsystem at one process sample (plan: "top then").
///
/// Stored per sample so the cursor can replay who led at a past instant,
/// without retaining every process row.
public struct ContributorSnapshot: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let cpu: [Contributor]
    public let memory: [Contributor]
    public let disk: [Contributor]
}

enum Contributors {
    static let limit = 3

    static func snapshot(from processes: CapturedProcesses, id: UUID = UUID()) -> ContributorSnapshot {
        let rows = ProcessGroups.rows(in: processes, matching: "", sortedBy: .name, grouping: .app)
        return ContributorSnapshot(
            id: id, time: processes.stamp.wallTime,
            cpu: top(rows) { $0.cpuPercentOfMachine },
            memory: top(rows) { $0.memoryFootprintBytes },
            disk: top(rows) {
                ProcessGroups.total([$0.diskReadBytesPerSecond, $0.diskWriteBytesPerSecond], overlap: nil)
            }
        )
    }

    /// Positive readings only: an idle or unreadable app is not a contributor.
    private static func top(_ rows: [ProcessRow], _ reading: (ProcessRow) -> MetricReading) -> [Contributor] {
        rows.compactMap { row -> Contributor? in
            let value = reading(row)
            guard let number = value.numericValue, number > 0 else { return nil }
            return Contributor(name: row.name, value: number, isEstimate: value.availability == .estimated)
        }
        .sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }
        .prefix(limit)
        .map { $0 }
    }
}
