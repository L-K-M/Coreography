import Foundation
import CoreographyKit

public enum ProcessGrouping: String, CaseIterable, Identifiable, Sendable {
    case app
    case flat

    public var id: Self { self }
}

/// How a process joined its app group.
public enum ProcessGroupingMethod: String, Sendable {
    /// The OS's responsible process, alive and started no later than the member.
    case responsibleProcess
    /// The outermost `.app` bundle in the executable path.
    case appBundle
    /// No owner was found; the process stands alone.
    case standalone
}

/// One process-pane row: an app group with member rows, or a single process.
public struct ProcessRow: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// The process for a leaf row; nil for a group.
    public let process: ObservedProcess?
    public let groupingMethod: ProcessGroupingMethod?
    /// The app this row belongs to; the key for scope and the app ledger.
    public let appName: String
    public let memberCount: Int
    public let cpuPercentOfMachine: MetricReading
    public let memoryFootprintBytes: MetricReading
    public let diskReadBytesPerSecond: MetricReading
    public let diskWriteBytesPerSecond: MetricReading
    /// Member rows for a group; nil for a leaf so tables show no disclosure.
    public let children: [ProcessRow]?
}

/// Fold helpers into the app that owns them, the way Activity Monitor does.
///
/// ```text
/// WebContent (responsible: Safari) ─┐
/// Safari (/Applications/Safari.app) ┴─> Safari group
/// Chrome Helper (…/Google Chrome.app/…/Helper.app) ──> Google Chrome group
/// ```
/// Group totals cover every member even when a filter hides some.
enum ProcessGroups {
    private static let appBundleSuffix = ".app"
    private static let footprintMethod = "Sum of member footprints; shared pages can count more than once"

    static func rows(
        in snapshot: CapturedProcesses?, matching filter: String,
        sortedBy sort: ProcessSort, grouping: ProcessGrouping,
        isNew: (ProcessIdentity) -> Bool = { _ in false }, listening: Set<ProcessIdentity>? = nil
    ) -> [ProcessRow] {
        if grouping == .flat {
            return ProcessList.rows(in: snapshot, matching: filter, sortedBy: sort, isNew: isNew, listening: listening)
                .map { leaf($0, method: nil, appName: $0.name) }
        }

        let parsed = ProcessFilter.parse(filter)
        let processes = snapshot?.processes ?? []
        let byPID = Dictionary(processes.map { ($0.id.pid, $0) }) { first, _ in first }

        // Assign each process to its owner's group, preserving first-seen order.
        var keys: [String] = []
        var names: [String: String] = [:]
        var members: [String: [(ObservedProcess, ProcessGroupingMethod)]] = [:]
        for process in processes {
            let (owner, method) = owner(of: process, in: byPID)
            let bundle = appBundle(of: owner)
            let key = bundle.map { "bundle:\($0.path)" } ?? "process:\(identityKey(owner))"
            if members[key] == nil {
                keys.append(key)
                names[key] = bundle?.name ?? owner.name
            }
            members[key, default: []].append((process, method))
        }

        var rows: [ProcessRow] = []
        for key in keys {
            let group = members[key] ?? []
            let name = names[key] ?? key
            // Free text naming the app shows all its members; predicates test each member.
            let nameMatches = parsed.isEmpty || (parsed.isTextOnly && parsed.matchesName(name))
            let visible = group.filter { nameMatches || parsed.matches($0.0, isNew: isNew($0.0.id), listening: listening) }
            guard !visible.isEmpty else { continue }

            if group.count == 1, let (process, method) = group.first {
                rows.append(leaf(process, method: method, appName: process.name))
                continue
            }
            let children = sorted(visible.map { leaf($0.0, method: $0.1, appName: name) }, by: sort)
            let all = group.map(\.0)
            rows.append(ProcessRow(
                id: "group-\(key)", name: name, process: nil, groupingMethod: nil, appName: name,
                memberCount: all.count,
                cpuPercentOfMachine: total(all.map(\.cpuPercentOfMachine), overlap: nil),
                memoryFootprintBytes: total(all.map(\.memoryFootprintBytes), overlap: footprintMethod),
                diskReadBytesPerSecond: total(all.map(\.diskReadBytesPerSecond), overlap: nil),
                diskWriteBytesPerSecond: total(all.map(\.diskWriteBytesPerSecond), overlap: nil),
                children: children
            ))
        }
        return sorted(rows, by: sort)
    }

    /// The responsible process owns a member only if it is observed and not
    /// younger; a later start means its PID was reused.
    private static func owner(
        of process: ObservedProcess, in byPID: [Int32: ObservedProcess]
    ) -> (ObservedProcess, ProcessGroupingMethod) {
        let standalone = appBundle(of: process) == nil ? ProcessGroupingMethod.standalone : .appBundle
        guard let responsible = process.responsiblePID, responsible != process.id.pid,
              let owner = byPID[responsible] else { return (process, standalone) }

        let ownerStart = (owner.id.startSeconds, owner.id.startMicroseconds)
        let processStart = (process.id.startSeconds, process.id.startMicroseconds)
        guard ownerStart <= processStart else { return (process, standalone) }

        // A shared owner such as launchd must not merge unrelated apps.
        guard appBundle(of: owner) != nil else { return (process, standalone) }
        return (owner, .responsibleProcess)
    }

    /// Outermost bundle, so nested helper apps fold into their host app.
    /// Example: `/Applications/Foo.app/Contents/Helpers/Bar.app/…` -> Foo.
    private static func appBundle(of process: ObservedProcess) -> (path: String, name: String)? {
        guard let path = process.executablePath else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: {
            $0.count > appBundleSuffix.count && $0.hasSuffix(appBundleSuffix)
        }) else { return nil }
        let bundle = components[index]
        return (
            path: components[...index].joined(separator: "/"),
            name: String(bundle.dropLast(appBundleSuffix.count))
        )
    }

    private static func identityKey(_ process: ObservedProcess) -> String {
        "\(process.id.pid)-\(process.id.startSeconds)-\(process.id.startMicroseconds)"
    }

    private static func leaf(
        _ process: ObservedProcess, method: ProcessGroupingMethod?, appName: String
    ) -> ProcessRow {
        ProcessRow(
            id: "process-\(identityKey(process))", name: process.name, process: process,
            groupingMethod: method, appName: appName, memberCount: 1,
            cpuPercentOfMachine: process.cpuPercentOfMachine,
            memoryFootprintBytes: process.memoryFootprintBytes,
            diskReadBytesPerSecond: process.diskReadBytesPerSecond,
            diskWriteBytesPerSecond: process.diskWriteBytesPerSecond,
            children: nil
        )
    }

    /// Sum member readings without inventing values for unreadable members.
    ///
    /// All members readable and additive: measured. Some unreadable: an
    /// estimated lower bound naming the coverage. None readable: the most
    /// informative member state. `overlap` names a non-additive quantity.
    static func total(_ readings: [MetricReading], overlap: String?) -> MetricReading {
        let values = readings.compactMap(\.numericValue)
        guard !values.isEmpty else {
            return readings.first { $0.availability == .collecting }
                ?? readings.first { $0.availability == .restricted }
                ?? readings.first
                ?? .gap(reason: "No members")
        }

        let sum = values.reduce(0, +)
        let source = readings.first { $0.numericValue != nil }?.source
        var methods: [String] = []
        if let overlap { methods.append(overlap) }
        if values.count < readings.count {
            methods.append("Lower bound: \(values.count) of \(readings.count) members readable")
        }
        let allMeasured = readings.allSatisfy { $0.availability == .measured }
        let reading = methods.isEmpty && allMeasured
            ? try? MetricReading.measured(sum, source: source)
            : try? MetricReading.estimated(
                sum, method: methods.isEmpty ? "Sum of member readings" : methods.joined(separator: "; "),
                source: source
            )
        return reading ?? .gap(reason: "Non-finite total", source: source)
    }

    private static func sorted(_ rows: [ProcessRow], by sort: ProcessSort) -> [ProcessRow] {
        rows.sorted { lhs, rhs in
            if sort != .name {
                let left = value(lhs, sort: sort)
                let right = value(rhs, sort: sort)
                if left != right {
                    if let left, let right { return left > right }
                    return left != nil
                }
            }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    private static func value(_ row: ProcessRow, sort: ProcessSort) -> Double? {
        switch sort {
        case .cpu: row.cpuPercentOfMachine.numericValue
        case .memory: row.memoryFootprintBytes.numericValue
        case .diskRead: row.diskReadBytesPerSecond.numericValue
        case .diskWrite: row.diskWriteBytesPerSecond.numericValue
        case .name: nil
        }
    }
}
