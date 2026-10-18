import Foundation
import CoreographyKit

public typealias CapturedStartupInventory = StartupInventory
public typealias CapturedStartupItem = StartupItem
public typealias CapturedStartupKind = StartupItemKind
public typealias CapturedStartupState = StartupEnabledState

/// Which startup items the tab lists (plan: Apple items hidden by default).
public enum StartupVisibility: String, CaseIterable, Identifiable, Sendable {
    case thirdParty, all

    public var id: Self { self }
}

/// A startup item joined to what it costs now (plan: the Startup tab).
public struct StartupRow: Identifiable, Sendable {
    public var id: String { item.id }
    public let item: CapturedStartupItem
    /// Observed processes whose executable is the item's program.
    public let processCount: Int
    /// Summed over those processes' readable values; nil when none is running or readable.
    public let cpuPercentOfMachine: Double?
    public let memoryFootprintBytes: Double?
    /// CPU-seconds of those processes' apps over the last hour, helpers included.
    public let appCPUSecondsLastHour: Double?
}

enum StartupRows {
    private static let ledgerWindow: TimeInterval = 3600

    static func rows(
        _ inventory: CapturedStartupInventory, processes: CapturedProcesses?, ledger: AppLedger,
        now: Date, visibility: StartupVisibility
    ) -> [StartupRow] {
        let running = processes?.processes ?? []
        let byProgram = Dictionary(grouping: running.filter { $0.executablePath != nil }) { $0.executablePath! }
        let appNames = processes.map(ProcessGroups.appNames) ?? [:]
        let appCPU = Dictionary(
            ledger.totals(in: now.addingTimeInterval(-ledgerWindow)...now).apps.map { ($0.name, $0.cpuSeconds) }
        ) { first, _ in first }

        return inventory.items
            .filter { visibility == .all || !$0.isApple }
            .map { item in
                let matched = item.program.flatMap { byProgram[$0] } ?? []
                let apps = Set(matched.compactMap { appNames[$0.id] })
                let cpu = matched.compactMap(\.cpuPercentOfMachine.numericValue)
                let memory = matched.compactMap(\.memoryFootprintBytes.numericValue)
                let appSeconds = apps.compactMap { appCPU[$0] }
                return StartupRow(
                    item: item, processCount: matched.count,
                    cpuPercentOfMachine: cpu.isEmpty ? nil : cpu.reduce(0, +),
                    memoryFootprintBytes: memory.isEmpty ? nil : memory.reduce(0, +),
                    appCPUSecondsLastHour: appSeconds.isEmpty ? nil : appSeconds.reduce(0, +)
                )
            }
    }
}
