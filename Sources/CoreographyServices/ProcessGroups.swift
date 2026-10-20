import Foundation
import CoreographyKit

public enum ProcessGrouping: String, CaseIterable, Identifiable, Sendable {
    case app
    /// Each process under its parent.
    case tree
    case flat
    case user

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

/// What a process-pane row stands for.
public enum ProcessRowKind: Equatable, Sendable {
    case process
    /// An app's processes folded under it.
    case app
    /// Every process one user runs, by UID.
    case user(UInt32)
}

/// One process-pane row: a group with member rows, or a single process,
/// which in the tree also carries its child processes.
public struct ProcessRow: Identifiable, Sendable {
    public let id: String
    public let kind: ProcessRowKind
    public let name: String
    /// The process for a process row; nil for a group.
    public let process: ObservedProcess?
    public let groupingMethod: ProcessGroupingMethod?
    /// The app this row belongs to; the key for scope and the app ledger.
    /// Empty for a user group, which belongs to no app.
    public let appName: String
    public let memberCount: Int
    public let cpuPercentOfMachine: MetricReading
    public let memoryFootprintBytes: MetricReading
    public let diskReadBytesPerSecond: MetricReading
    public let diskWriteBytesPerSecond: MetricReading
    public let wakeupsPerSecond: MetricReading
    /// TCP and UDP bytes per second; zero for a process with no socket open.
    public let networkReceivedBytesPerSecond: MetricReading
    public let networkSentBytesPerSecond: MetricReading
    /// GPU ms per second; zero for a process with no GPU client. Not additive like a share.
    public let gpuMillisecondsPerSecond: MetricReading
    /// CPU power from the kernel's energy model; an estimate.
    public let cpuPowerWatts: MetricReading
    /// User plus system CPU time over each member's life, in seconds.
    public let cpuTimeSeconds: MetricReading
    /// Threads now; an app sums its processes.
    public let threadCount: MetricReading
    /// Retired instructions per second; an app sums its processes.
    public let instructionsPerSecond: MetricReading
    /// CPU percent of the machine per QoS class; an app sums per class.
    /// Nil when no member's counters could be read.
    public let qosCPUPercent: [ProcessQoS: MetricReading]?
    /// The architectures its processes run; empty when none was read.
    /// Example: a native app with one Rosetta helper has both.
    public let architectures: Set<ProcessArchitecture>
    /// Who signed its programs; empty until checked or when none could be.
    public let signers: Set<CapturedSigner>
    /// When the process started; for a group, its first member.
    public let started: Date?
    /// Member rows for a group, or child processes in the tree; nil for a
    /// leaf so tables show no disclosure.
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
        isNew: (ProcessIdentity) -> Bool = { _ in false }, facts: ProcessFacts = ProcessFacts(),
        currentUser: UInt32 = UInt32(getuid())
    ) -> [ProcessRow] {
        switch grouping {
        case .app:
            return appRows(in: snapshot, matching: filter, sortedBy: sort, isNew: isNew, facts: facts)
        case .flat:
            // A flat row still belongs to its app: scope and the ledger key on it.
            let apps = snapshot.map(appNames) ?? [:]
            return ProcessList.rows(in: snapshot, matching: filter, sortedBy: sort, isNew: isNew, facts: facts, appNames: apps)
                .map { leaf($0, method: nil, appName: apps[$0.id] ?? $0.name, facts: facts) }
        case .tree:
            return treeRows(in: snapshot, matching: filter, sortedBy: sort, isNew: isNew, facts: facts, currentUser: currentUser)
        case .user:
            return userRows(in: snapshot, matching: filter, sortedBy: sort, isNew: isNew, facts: facts, currentUser: currentUser)
        }
    }

    /// Rows whose app is `app`, with the groups and parents that lead to them.
    /// Example: scoping the tree to Terminal keeps launchd > Terminal > zsh.
    static func scoped(_ rows: [ProcessRow], to app: String) -> [ProcessRow] {
        rows.compactMap { row in
            // An app group's members all share its app.
            if row.kind == .app { return row.appName == app ? row : nil }
            let children = scoped(row.children ?? [], to: app)
            guard row.appName == app || !children.isEmpty else { return nil }
            return row.replacingChildren(children.isEmpty ? nil : children)
        }
    }

    private static func appRows(
        in snapshot: CapturedProcesses?, matching filter: String, sortedBy sort: ProcessSort,
        isNew: (ProcessIdentity) -> Bool, facts: ProcessFacts
    ) -> [ProcessRow] {
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
            let visible = group.filter {
                nameMatches || parsed.matches($0.0, isNew: isNew($0.0.id), appName: name, facts: facts)
            }
            guard !visible.isEmpty else { continue }

            if group.count == 1, let (process, method) = group.first {
                rows.append(leaf(process, method: method, appName: process.name, facts: facts))
                continue
            }
            let children = sorted(visible.map { leaf($0.0, method: $0.1, appName: name, facts: facts) }, by: sort)
            rows.append(groupRow(
                id: "group-\(key)", kind: .app, name: name, appName: name, members: group.map(\.0),
                children: children, facts: facts
            ))
        }
        return sorted(rows, by: sort)
    }

    /// Each process under its parent, as Activity Monitor's hierarchy shows it.
    /// A parent counts only if observed and started no later than the child,
    /// so a reused PID never adopts another process's children. A filter
    /// keeps each match with the parents that lead to it.
    ///
    /// ```text
    /// launchd ─┬─ Terminal ── zsh ── python3
    ///          └─ Safari
    /// ```
    private static func treeRows(
        in snapshot: CapturedProcesses?, matching filter: String, sortedBy sort: ProcessSort,
        isNew: (ProcessIdentity) -> Bool, facts: ProcessFacts, currentUser: UInt32
    ) -> [ProcessRow] {
        guard let snapshot else { return [] }
        let parsed = ProcessFilter.parse(filter, currentUser: currentUser)
        let apps = appNames(snapshot)
        let processes = snapshot.processes
        let byPID = Dictionary(processes.map { ($0.id.pid, $0) }) { first, _ in first }

        var roots: [ObservedProcess] = []
        var children: [ProcessIdentity: [ObservedProcess]] = [:]
        for process in processes {
            guard let parent = parent(of: process, in: byPID) else {
                roots.append(process)
                continue
            }
            children[parent.id, default: []].append(process)
        }

        // Walk down from each root; a parent loop has no root, so its first
        // member stands in for one. Each process joins the tree once.
        var order: [ObservedProcess] = []
        var tree: [ProcessIdentity: [ObservedProcess]] = [:]
        var visited: Set<ProcessIdentity> = []
        var starts: [ObservedProcess] = []
        for start in roots + processes where !visited.contains(start.id) {
            starts.append(start)
            visited.insert(start.id)
            var pending = [start]
            while let process = pending.popLast() {
                order.append(process)
                for child in children[process.id] ?? [] where visited.insert(child.id).inserted {
                    tree[process.id, default: []].append(child)
                    pending.append(child)
                }
            }
        }

        // Parents precede their children in the walk, so building it backwards
        // finishes every subtree before its parent.
        var built: [ProcessIdentity: ProcessRow] = [:]
        for process in order.reversed() {
            let kids = (tree[process.id] ?? []).compactMap { built[$0.id] }
            let appName = apps[process.id] ?? process.name
            let matches = parsed.isEmpty
                || parsed.matches(process, isNew: isNew(process.id), appName: appName, facts: facts, currentUser: currentUser)
            guard matches || !kids.isEmpty else { continue }
            built[process.id] = leaf(process, method: nil, appName: appName, facts: facts)
                .replacingChildren(kids.isEmpty ? nil : sorted(kids, by: sort))
        }
        return sorted(starts.compactMap { built[$0.id] }, by: sort)
    }

    /// One group per UID, totalled like an app group.
    private static func userRows(
        in snapshot: CapturedProcesses?, matching filter: String, sortedBy sort: ProcessSort,
        isNew: (ProcessIdentity) -> Bool, facts: ProcessFacts, currentUser: UInt32
    ) -> [ProcessRow] {
        guard let snapshot else { return [] }
        let parsed = ProcessFilter.parse(filter, currentUser: currentUser)
        let apps = appNames(snapshot)
        let byUser = Dictionary(grouping: snapshot.processes, by: \.uid)

        var rows: [ProcessRow] = []
        for (uid, members) in byUser {
            let name = userName(uid, currentUser: currentUser, account: facts.accountNames[uid])
            let nameMatches = parsed.isEmpty || (parsed.isTextOnly && parsed.matchesName(name))
            let visible = members.filter {
                nameMatches || parsed.matches(
                    $0, isNew: isNew($0.id), appName: apps[$0.id] ?? $0.name, facts: facts, currentUser: currentUser
                )
            }
            guard !visible.isEmpty else { continue }
            let children = sorted(visible.map { leaf($0, method: nil, appName: apps[$0.id] ?? $0.name, facts: facts) }, by: sort)
            rows.append(groupRow(
                id: "user-\(uid)", kind: .user(uid), name: name, appName: "", members: members,
                children: children, facts: facts
            ))
        }
        return sorted(rows, by: sort)
    }

    /// Example: 0 -> "root", the current user 501 -> "You, alice", an account
    /// "_spotlight", and a UID without an account -> "UID 502".
    private static func userName(_ uid: UInt32, currentUser: UInt32, account: String?) -> String {
        if uid == 0 { return "root" }
        let name = account ?? "UID \(uid)"
        return uid == currentUser ? "You, \(name)" : name
    }

    /// A group row totals every member, even those a filter hides.
    private static func groupRow(
        id: String, kind: ProcessRowKind, name: String, appName: String, members: [ObservedProcess],
        children: [ProcessRow], facts: ProcessFacts
    ) -> ProcessRow {
        let network = members.map { ProcessNetwork.rates(for: $0, in: facts.traffic) }
        return ProcessRow(
            id: id, kind: kind, name: name, process: nil, groupingMethod: nil, appName: appName,
            memberCount: members.count,
            cpuPercentOfMachine: total(members.map(\.cpuPercentOfMachine), overlap: nil),
            memoryFootprintBytes: total(members.map(\.memoryFootprintBytes), overlap: footprintMethod),
            diskReadBytesPerSecond: total(members.map(\.diskReadBytesPerSecond), overlap: nil),
            diskWriteBytesPerSecond: total(members.map(\.diskWriteBytesPerSecond), overlap: nil),
            wakeupsPerSecond: total(members.map(\.wakeupsPerSecond), overlap: nil),
            networkReceivedBytesPerSecond: total(network.map(\.received), overlap: nil),
            networkSentBytesPerSecond: total(network.map(\.sent), overlap: nil),
            gpuMillisecondsPerSecond: total(members.map(\.gpuMillisecondsPerSecond), overlap: nil),
            cpuPowerWatts: total(members.map(\.cpuPowerWatts), overlap: nil),
            cpuTimeSeconds: total(members.map(\.cpuTimeSeconds), overlap: nil),
            threadCount: total(members.map(\.threadCount), overlap: nil),
            instructionsPerSecond: total(members.map(\.instructionsPerSecond), overlap: nil),
            qosCPUPercent: qosTotal(members),
            architectures: Set(members.compactMap(\.architecture)),
            signers: Set(members.compactMap { $0.executablePath.flatMap { facts.signers[$0] } }),
            started: members.map(\.id.startTime).min(),
            children: children
        )
    }

    /// The observed parent, unless it started after the child (a reused PID).
    private static func parent(of process: ObservedProcess, in byPID: [Int32: ObservedProcess]) -> ObservedProcess? {
        guard let pid = Int32(exactly: process.parentPID), pid != process.id.pid, let parent = byPID[pid] else { return nil }
        let parentStart = (parent.id.startSeconds, parent.id.startMicroseconds)
        let processStart = (process.id.startSeconds, process.id.startMicroseconds)
        return parentStart <= processStart ? parent : nil
    }

    /// Each process's app, as the grouped table names it.
    static func appNames(_ processes: CapturedProcesses) -> [ProcessIdentity: String] {
        var names: [ProcessIdentity: String] = [:]
        for row in rows(in: processes, matching: "", sortedBy: .name, grouping: .app) {
            if let process = row.process { names[process.id] = row.appName }
            for child in row.children ?? [] {
                if let process = child.process { names[process.id] = row.appName }
            }
        }
        return names
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
    static func appBundle(of process: ObservedProcess) -> (path: String, name: String)? {
        guard let path = process.executablePath else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        // Volumes are usually case-insensitive, so "Old.APP" is a bundle too.
        guard let index = components.firstIndex(where: {
            $0.count > appBundleSuffix.count && $0.lowercased().hasSuffix(appBundleSuffix)
        }) else { return nil }
        let bundle = components[index]
        return (
            path: components[...index].joined(separator: "/"),
            name: String(bundle.dropLast(appBundleSuffix.count))
        )
    }

    /// The table row id of one process, stable while its identity holds.
    static func rowID(_ process: ObservedProcess) -> ProcessRow.ID { "process-\(identityKey(process))" }

    private static func identityKey(_ process: ObservedProcess) -> String {
        "\(process.id.pid)-\(process.id.startSeconds)-\(process.id.startMicroseconds)"
    }

    private static func leaf(
        _ process: ObservedProcess, method: ProcessGroupingMethod?, appName: String, facts: ProcessFacts
    ) -> ProcessRow {
        let network = ProcessNetwork.rates(for: process, in: facts.traffic)
        return ProcessRow(
            id: rowID(process), kind: .process, name: process.name, process: process,
            groupingMethod: method, appName: appName, memberCount: 1,
            cpuPercentOfMachine: process.cpuPercentOfMachine,
            memoryFootprintBytes: process.memoryFootprintBytes,
            diskReadBytesPerSecond: process.diskReadBytesPerSecond,
            diskWriteBytesPerSecond: process.diskWriteBytesPerSecond,
            wakeupsPerSecond: process.wakeupsPerSecond,
            networkReceivedBytesPerSecond: network.received,
            networkSentBytesPerSecond: network.sent,
            gpuMillisecondsPerSecond: process.gpuMillisecondsPerSecond,
            cpuPowerWatts: process.cpuPowerWatts,
            cpuTimeSeconds: process.cpuTimeSeconds,
            threadCount: process.threadCount,
            instructionsPerSecond: process.instructionsPerSecond,
            qosCPUPercent: process.qosCPUPercent,
            architectures: Set([process.architecture].compactMap { $0 }),
            signers: Set([process.executablePath.flatMap { facts.signers[$0] }].compactMap { $0 }),
            started: process.id.startTime,
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

    /// A group's split sums each class across members, a member without
    /// counters counting as an unreadable share, not zero: its CPU reading
    /// says why (restricted, collecting), and the sum is a lower bound. Nil
    /// when no member's counters could be read at all.
    private static func qosTotal(_ members: [ObservedProcess]) -> [ProcessQoS: MetricReading]? {
        guard members.contains(where: { $0.qosCPUPercent != nil }) else { return nil }
        return Dictionary(uniqueKeysWithValues: ProcessQoS.allCases.map { qosClass in
            (qosClass, total(members.map { member in
                member.qosCPUPercent?[qosClass]
                    ?? (member.cpuPercentOfMachine.numericValue == nil
                        ? member.cpuPercentOfMachine
                        : .gap(reason: "No QoS counters for this process", source: member.cpuPercentOfMachine.source))
            }, overlap: nil))
        })
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
        case .network: ProcessNetwork.total(row.networkReceivedBytesPerSecond, row.networkSentBytesPerSecond)
        case .cpu: row.cpuPercentOfMachine.numericValue
        case .memory: row.memoryFootprintBytes.numericValue
        case .diskRead: row.diskReadBytesPerSecond.numericValue
        case .diskWrite: row.diskWriteBytesPerSecond.numericValue
        case .gpu: row.gpuMillisecondsPerSecond.numericValue
        case .power: row.cpuPowerWatts.numericValue
        case .cpuTime: row.cpuTimeSeconds.numericValue
        case .started: row.started?.timeIntervalSince1970
        case .threads: row.threadCount.numericValue
        case .instructions: row.instructionsPerSecond.numericValue
        case .name: nil
        }
    }
}

extension ProcessRow {
    /// The outermost app bundle its program, or its first member's, runs
    /// from, for the row's icon; nil outside a bundle.
    /// Example: ".../Safari.app/Contents/MacOS/Safari" is "/Applications/Safari.app".
    public var appBundlePath: String? {
        var pending = [self]
        while !pending.isEmpty {
            let row = pending.removeFirst()
            if let process = row.process, let bundle = ProcessGroups.appBundle(of: process) { return bundle.path }
            pending += row.children ?? []
        }
        return nil
    }

    /// The same row over other children, for the tree and scope to prune.
    func replacingChildren(_ children: [ProcessRow]?) -> ProcessRow {
        ProcessRow(
            id: id, kind: kind, name: name, process: process, groupingMethod: groupingMethod, appName: appName,
            memberCount: memberCount, cpuPercentOfMachine: cpuPercentOfMachine, memoryFootprintBytes: memoryFootprintBytes,
            diskReadBytesPerSecond: diskReadBytesPerSecond, diskWriteBytesPerSecond: diskWriteBytesPerSecond,
            wakeupsPerSecond: wakeupsPerSecond, networkReceivedBytesPerSecond: networkReceivedBytesPerSecond,
            networkSentBytesPerSecond: networkSentBytesPerSecond, gpuMillisecondsPerSecond: gpuMillisecondsPerSecond,
            cpuPowerWatts: cpuPowerWatts, cpuTimeSeconds: cpuTimeSeconds, threadCount: threadCount,
            instructionsPerSecond: instructionsPerSecond, qosCPUPercent: qosCPUPercent,
            architectures: architectures, signers: signers, started: started, children: children
        )
    }
}
