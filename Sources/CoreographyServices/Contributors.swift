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

/// Where a contributor snapshot came from: a live process sample, or the
/// stored app ledger, which keeps CPU, disk and network per app only.
public enum ContributorOrigin: Sendable {
    case processSample
    case storedLedger
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
    /// TCP and UDP in plus out; empty when no traffic sample matched.
    public let network: [Contributor]
    /// GPU time in ms per second; not a share of the GPU's busy percentage.
    public let gpu: [Contributor]
    /// CPU power from the kernel's energy model, always an estimate.
    public let power: [Contributor]
    public var origin: ContributorOrigin = .processSample
}

enum Contributors {
    static let limit = 3

    static func snapshot(from processes: CapturedProcesses, traffic: CapturedTraffic? = nil, id: UUID = UUID()) -> ContributorSnapshot {
        let rows = ProcessGroups.rows(
            in: processes, matching: "", sortedBy: .name, grouping: .app, facts: ProcessFacts(traffic: traffic)
        )
        return ContributorSnapshot(
            id: id, time: processes.stamp.wallTime,
            cpu: top(rows) { $0.cpuPercentOfMachine },
            memory: top(rows) { $0.memoryFootprintBytes },
            disk: top(rows) {
                ProcessGroups.total([$0.diskReadBytesPerSecond, $0.diskWriteBytesPerSecond], overlap: nil)
            },
            network: top(rows) {
                ProcessGroups.total([$0.networkReceivedBytesPerSecond, $0.networkSentBytesPerSecond], overlap: nil)
            },
            gpu: top(rows) { $0.gpuMillisecondsPerSecond },
            power: top(rows) { $0.cpuPowerWatts }
        )
    }

    /// Positive readings only: an idle or unreadable app is not a contributor.
    private static func top(_ rows: [ProcessRow], _ reading: (ProcessRow) -> MetricReading) -> [Contributor] {
        ranked(rows.compactMap { row -> Contributor? in
            let value = reading(row)
            guard let number = value.numericValue else { return nil }
            return Contributor(name: row.name, value: number, isEstimate: value.availability == .estimated)
        })
    }

    /// The leaders among positive values, ties by name.
    static func ranked(_ contributors: [Contributor]) -> [Contributor] {
        contributors.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }
}
