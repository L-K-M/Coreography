import SwiftUI
import WidgetKit
import CoreographyServices

@main
private struct CoreographyWidgets: WidgetBundle {
    var body: some Widget {
        OverviewWidget()
        CPUWidget()
        MemoryWidget()
        NetworkWidget()
        DiskWidget()
        BriefingWidget()
    }
}

// WidgetKit recreates each kind with init(), so each needs its own type.
private struct OverviewWidget: Widget {
    // Only the overview advertises a large family; its cards reflow to two columns.
    var body: some WidgetConfiguration {
        statsConfiguration(.overview, families: [.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct CPUWidget: Widget {
    var body: some WidgetConfiguration { statsConfiguration(.cpu) }
}

private struct MemoryWidget: Widget {
    var body: some WidgetConfiguration { statsConfiguration(.memory) }
}

private struct NetworkWidget: Widget {
    var body: some WidgetConfiguration { statsConfiguration(.network) }
}

private struct DiskWidget: Widget {
    var body: some WidgetConfiguration { statsConfiguration(.disk) }
}

private struct BriefingWidget: Widget {
    var body: some WidgetConfiguration { statsConfiguration(.briefing) }
}

private enum Statistic: String {
    case overview, cpu, memory, network, disk, briefing

    var title: LocalizedStringKey {
        switch self {
        case .overview: "System Overview"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk"
        case .briefing: "Briefing"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "desktopcomputer"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        case .disk: "internaldrive"
        case .briefing: "text.bubble"
        }
    }

    var color: Color {
        switch self {
        case .overview, .cpu: .blue
        case .memory: .teal
        case .network: .indigo
        case .disk: .purple
        case .briefing: .orange
        }
    }

    var description: LocalizedStringKey {
        switch self {
        case .briefing:
            "What your Mac did in the last five minutes, written by the model you choose in Coreography's Settings. Without one, a hint from a short sample."
        default:
            "A short system sample. macOS controls refreshes; open Coreography for live readings."
        }
    }

    /// The dashboard section opened when the widget is tapped.
    var section: DashboardSection {
        switch self {
        case .overview, .briefing: .overview
        case .cpu: .cpu
        case .memory: .memory
        case .network: .network
        case .disk: .storage
        }
    }
}

@MainActor
private func statsConfiguration(
    _ statistic: Statistic,
    families: [WidgetFamily] = [.systemSmall, .systemMedium]
) -> some WidgetConfiguration {
    StaticConfiguration(kind: "ch.lkmc.Coreography.widget.\(statistic.rawValue)", provider: StatsProvider(statistic: statistic)) { entry in
        StatsView(statistic: statistic, entry: entry)
            .containerBackground(.background, for: .widget)
            .widgetURL(statistic.section.url)
    }
    .configurationDisplayName(statistic.title)
    .description(statistic.description)
    .supportedFamilies(families)
}

private struct StatsEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: WidgetSnapshot?
    let problem: String?
    /// Read only for the Briefing widget; the others show `.none`.
    var briefing = StoredBriefing.none

    // A second entry ages the sample even when macOS postpones the next refresh.
    static let refreshInterval: TimeInterval = 15 * 60
    static let staleInterval = refreshInterval * 2

    var isStale: Bool {
        guard let snapshot else { return false }
        return date.timeIntervalSince(snapshot.sampledAt) >= Self.staleInterval
    }
}

private struct StatsProvider: TimelineProvider {
    let statistic: Statistic

    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: .now, snapshot: nil, problem: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StatsEntry) -> Void) {
        Task { completion(await sample()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StatsEntry>) -> Void) {
        Task {
            let entry = await sample()
            var entries = [entry]
            if let snapshot = entry.snapshot {
                entries.append(StatsEntry(
                    date: snapshot.sampledAt.addingTimeInterval(StatsEntry.staleInterval),
                    snapshot: snapshot, problem: nil, briefing: entry.briefing
                ))
            }
            if let expiry = entry.briefing.expiry(after: entry.date) {
                entries.append(StatsEntry(date: expiry, snapshot: entry.snapshot, problem: entry.problem, briefing: entry.briefing))
                entries.sort { $0.date < $1.date }
            }
            completion(Timeline(entries: entries, policy: .after(entry.date.addingTimeInterval(StatsEntry.refreshInterval))))
        }
    }

    private func sample() async -> StatsEntry {
        let briefing = statistic == .briefing ? StoredBriefing.read() : .none
        do {
            let snapshot = try await WidgetSampler().sample()
            return StatsEntry(date: .now, snapshot: snapshot, problem: nil, briefing: briefing)
        } catch {
            return StatsEntry(date: .now, snapshot: nil, problem: error.localizedDescription, briefing: briefing)
        }
    }
}

private struct StatsView: View {
    let statistic: Statistic
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if statistic == .briefing {
            BriefingView(entry: entry)
        } else {
            stats
        }
    }

    private var stats: some View {
        // Tight spacing leaves the overview's five rows room in a small widget.
        VStack(alignment: .leading, spacing: 4) {
            Label(statistic.title, systemImage: statistic.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statistic.color)
            Spacer(minLength: 0)

            if let snapshot = entry.snapshot {
                readings(snapshot)
                    .opacity(entry.isStale ? 0.6 : 1)
            } else if let problem = entry.problem {
                Text("Sample unavailable").font(.headline)
                Text(problem).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            } else {
                Text("Collecting…").font(.title2)
            }

            Spacer(minLength: 0)
            if let snapshot = entry.snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    if entry.isStale { Text("Older sample · open app for live stats") }
                    Text("Sampled \(snapshot.sampledAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            } else {
                Text("Open Coreography for live stats").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        // Overview cards are links and must stay separate accessibility
        // elements; everything else reads as one combined element.
        .accessibilityElement(children: statistic == .overview && family != .systemSmall ? .contain : .combine)
    }

    @ViewBuilder private func readings(_ snapshot: WidgetSnapshot) -> some View {
        switch statistic {
        case .briefing:
            // BriefingView draws this kind; body never routes it here.
            EmptyView()
        case .cpu:
            VStack(alignment: .leading, spacing: 6) {
                Text(WidgetText.value(snapshot.host.cpuPercentOfMachine, as: .percent)).font(.largeTitle.weight(.semibold))
                if let value = snapshot.host.cpuPercentOfMachine.numericValue {
                    ProgressView(value: value, total: WidgetText.percentScale).tint(statistic.color)
                        .accessibilityLabel("CPU, whole machine")
                }
                Text(snapshot.host.cpuPercentOfMachine.numericValue == nil
                     ? WidgetText.status(snapshot.host.cpuPercentOfMachine)
                     : String(localized: "Whole machine"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if family == .systemMedium, let system = snapshot.host.cpuSystemPercentOfMachine {
                    Text("System \(WidgetText.value(system, as: .percent)) · \(snapshot.host.inventory.logicalCPUCount) logical CPUs")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .memory:
            VStack(alignment: .leading, spacing: 6) {
                Text(WidgetText.value(snapshot.host.memoryUsedBytes, as: .bytes)).font(.title.weight(.semibold))
                if let fraction = snapshot.memoryFraction {
                    ProgressView(value: fraction).tint(memoryColor(snapshot))
                        .accessibilityLabel("Used memory, estimated")
                }
                Text("of \(WidgetText.bytes(Double(snapshot.host.inventory.physicalMemoryBytes)))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(pressure(snapshot)).font(.caption).foregroundStyle(memoryColor(snapshot)).lineLimit(2)
                if family == .systemMedium {
                    Text("Swap \(WidgetText.value(snapshot.host.memory.swapUsedBytes, as: .bytes))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .network:
            VStack(alignment: .leading, spacing: 8) {
                if family == .systemMedium {
                    HStack(spacing: 24) {
                        networkValue("Download", symbol: "arrow.down", reading: snapshot.primaryInterface?.receivedBytesPerSecond)
                        networkValue("Upload", symbol: "arrow.up", reading: snapshot.primaryInterface?.sentBytesPerSecond)
                    }
                } else {
                    overviewRow("Download", symbol: "arrow.down", value: WidgetText.value(snapshot.primaryInterface?.receivedBytesPerSecond, as: .rate))
                    overviewRow("Upload", symbol: "arrow.up", value: WidgetText.value(snapshot.primaryInterface?.sentBytesPerSecond, as: .rate))
                }
                Text(networkStatus(snapshot)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        case .disk:
            VStack(alignment: .leading, spacing: 6) {
                switch snapshot.disk {
                case .measured(let total, let available):
                    Text(WidgetText.bytes(Double(available))).font(.title.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    if let fraction = snapshot.disk.usedFraction {
                        ProgressView(value: fraction).tint(statistic.color)
                            .accessibilityLabel("Used disk space")
                    }
                    Text("available of \(WidgetText.bytes(Double(total)))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if family == .systemMedium, let used = snapshot.disk.usedBytes {
                        Text("\(WidgetText.bytes(Double(used))) used on the startup volume")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .unavailable(let reason):
                    Text("–").font(.title.weight(.semibold))
                    Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        case .overview:
            let items = overviewItems(snapshot)
            switch family {
            case .systemLarge:
                overviewCardGrid(items, columns: Self.overviewLargeColumns, detail: .context)
            case .systemMedium:
                overviewCardGrid(items, columns: Self.overviewMediumColumns, detail: .summary)
            default:
                // Small keeps the compact rows; six cards and links would not fit.
                let rows = summaryItems(items)
                VStack(alignment: .leading, spacing: Self.overviewRowSpacing) {
                    ForEach(rows.indices, id: \.self) { overviewRow(rows[$0]) }
                }
            }
        }
    }

    /// One overview metric: a card linking to its dashboard section on medium
    /// and large, a summary row on small.
    private struct OverviewItem {
        let title: LocalizedStringKey
        let symbol: String
        let section: DashboardSection
        let value: String
        var context: String? = nil
        var valueTint: Color? = nil
    }

    /// Medium fits three cards per row, large two with room for a context line.
    private static let overviewMediumColumns = 3
    private static let overviewLargeColumns = 2
    private static let overviewCardRadius: CGFloat = 10
    private static let overviewCardPadding: CGFloat = 8
    private static let overviewGridSpacing: CGFloat = 10
    private static let overviewRowSpacing: CGFloat = 4

    /// The order matters: `summaryItems` folds the pressure item into memory.
    private func overviewItems(_ snapshot: WidgetSnapshot) -> [OverviewItem] {
        [
            OverviewItem(
                title: "CPU", symbol: "cpu", section: .cpu,
                value: WidgetText.value(snapshot.host.cpuPercentOfMachine, as: .percent),
                context: cpuContext(snapshot)
            ),
            OverviewItem(
                title: "Memory", symbol: "memorychip", section: .memory,
                value: WidgetText.value(snapshot.host.memoryUsedBytes, as: .bytes),
                context: String(localized: "of \(WidgetText.bytes(Double(snapshot.host.inventory.physicalMemoryBytes)))")
            ),
            OverviewItem(
                title: "Pressure", symbol: "gauge.medium", section: .memory,
                value: pressureWord(snapshot), context: swapContext(snapshot),
                valueTint: pressureTint(snapshot)
            ),
            OverviewItem(
                title: "Disk", symbol: "internaldrive", section: .storage,
                value: WidgetText.free(snapshot), context: diskContext(snapshot)
            ),
            OverviewItem(
                title: "Download", symbol: "arrow.down", section: .network,
                value: WidgetText.value(snapshot.primaryInterface?.receivedBytesPerSecond, as: .rate),
                context: interfaceContext(snapshot, for: snapshot.primaryInterface?.receivedBytesPerSecond)
            ),
            OverviewItem(
                title: "Upload", symbol: "arrow.up", section: .network,
                value: WidgetText.value(snapshot.primaryInterface?.sentBytesPerSecond, as: .rate),
                context: interfaceContext(snapshot, for: snapshot.primaryInterface?.sentBytesPerSecond)
            )
        ]
    }

    /// The small widget has no room for a sixth row or card links: pressure
    /// rides with the memory row and taps go through the widgetURL.
    private func summaryItems(_ items: [OverviewItem]) -> [OverviewItem] {
        guard items.count > 2 else { return items }
        var rows = items
        let memory = rows[1], pressure = rows[2]
        rows[1] = OverviewItem(
            title: memory.title, symbol: memory.symbol, section: memory.section,
            value: memory.value == "–" ? pressure.value : "\(memory.value) · \(pressure.value)",
            context: memory.context, valueTint: pressure.valueTint
        )
        rows.remove(at: 2)
        return rows
    }

    private enum OverviewDetail { case summary, context }

    private func overviewCardGrid(_ items: [OverviewItem], columns: Int, detail: OverviewDetail) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Self.overviewGridSpacing, verticalSpacing: Self.overviewGridSpacing) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + columns, items.count), id: \.self) { index in
                        Link(destination: items[index].section.url) {
                            overviewCard(items[index], detail: detail)
                        }
                        .accessibilityLabel(cardAccessibilityLabel(items[index]))
                    }
                }
            }
        }
    }

    private func overviewCard(_ item: OverviewItem, detail: OverviewDetail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(item.title).foregroundStyle(.secondary)
            } icon: {
                Image(systemName: item.symbol).foregroundStyle(statistic.color)
            }
            .font(.subheadline)
            Text(item.value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(item.valueTint ?? .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if detail == .context, let context = item.context {
                Text(context).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(Self.overviewCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: .rect(cornerRadius: Self.overviewCardRadius))
    }

    private func cardAccessibilityLabel(_ item: OverviewItem) -> Text {
        guard let context = item.context, !context.isEmpty else {
            return Text("\(Text(item.title)): \(item.value)")
        }
        return Text("\(Text(item.title)): \(item.value), \(context)")
    }

    private func overviewRow(_ item: OverviewItem) -> some View {
        overviewRow(item.title, symbol: item.symbol, value: item.value, valueTint: item.valueTint)
    }

    private func overviewRow(_ title: LocalizedStringKey, symbol: String, value: String, valueTint: Color? = nil) -> some View {
        HStack {
            Label(title, systemImage: symbol).labelStyle(.iconOnly).foregroundStyle(statistic.color)
            Spacer(minLength: 4)
            // Without priority the row shrinks the value to fit before the spacer gives way.
            Text(value).fontWeight(.semibold).foregroundStyle(valueTint ?? .primary).lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(title)): \(value)"))
    }

    private func networkValue(_ title: LocalizedStringKey, symbol: String, reading: DashboardReading?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(WidgetText.value(reading, as: .rate)).font(.title2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private func networkStatus(_ snapshot: WidgetSnapshot) -> String {
        guard let primary = snapshot.primaryInterface else {
            let issue = snapshot.network.enumeration.numericValue == nil ? snapshot.network.enumeration : snapshot.network.primaryIssue
            return issue.map(WidgetText.status) ?? String(localized: "No primary interface")
        }
        if primary.receivedBytesPerSecond.numericValue == nil { return WidgetText.status(primary.receivedBytesPerSecond) }
        if primary.sentBytesPerSecond.numericValue == nil { return WidgetText.status(primary.sentBytesPerSecond) }
        return String(localized: "Primary interface: \(primary.id.name)")
    }

    private func pressure(_ snapshot: WidgetSnapshot) -> String {
        guard snapshot.host.memoryUsedBytes.numericValue != nil else { return WidgetText.status(snapshot.host.memoryUsedBytes) }
        switch snapshot.host.memory.pressureLevel {
        case .normal: return String(localized: "Normal pressure")
        case .warning: return String(localized: "Elevated pressure")
        case .critical: return String(localized: "Critical pressure")
        case nil: return WidgetText.status(snapshot.host.memory.pressure)
        }
    }

    private func memoryColor(_ snapshot: WidgetSnapshot) -> Color {
        switch snapshot.host.memory.pressureLevel {
        case .warning: .orange
        case .critical: .red
        default: .teal
        }
    }

    /// Short level word for cards and the merged small row; an explicit
    /// status when the kernel pressure reading is missing.
    private func pressureWord(_ snapshot: WidgetSnapshot) -> String {
        switch snapshot.host.memory.pressureLevel {
        case .normal: String(localized: "Normal")
        case .warning: String(localized: "Elevated")
        case .critical: String(localized: "Critical")
        case nil: WidgetText.status(snapshot.host.memory.pressure)
        }
    }

    /// Elevated and critical pressure tint the value; normal stays primary.
    private func pressureTint(_ snapshot: WidgetSnapshot) -> Color? {
        switch snapshot.host.memory.pressureLevel {
        case .warning: .orange
        case .critical: .red
        default: nil
        }
    }

    private func cpuContext(_ snapshot: WidgetSnapshot) -> String {
        let cores = String(localized: "\(snapshot.host.inventory.logicalCPUCount) logical CPUs")
        guard let system = snapshot.host.cpuSystemPercentOfMachine, system.numericValue != nil else { return cores }
        return String(localized: "System \(WidgetText.value(system, as: .percent)) · \(cores)")
    }

    private func swapContext(_ snapshot: WidgetSnapshot) -> String {
        let swap = snapshot.host.memory.swapUsedBytes
        guard swap.numericValue != nil else { return WidgetText.status(swap) }
        return String(localized: "Swap \(WidgetText.value(swap, as: .bytes))")
    }

    private func diskContext(_ snapshot: WidgetSnapshot) -> String {
        switch snapshot.disk {
        case .measured(let total, _):
            guard let used = snapshot.disk.usedBytes else {
                return String(localized: "of \(WidgetText.bytes(Double(total)))")
            }
            return String(localized: "\(WidgetText.bytes(Double(used))) used of \(WidgetText.bytes(Double(total)))")
        case .unavailable(let reason):
            return reason
        }
    }

    private func interfaceContext(_ snapshot: WidgetSnapshot, for reading: DashboardReading?) -> String {
        guard let primary = snapshot.primaryInterface else {
            let issue = snapshot.network.enumeration.numericValue == nil ? snapshot.network.enumeration : snapshot.network.primaryIssue
            return issue.map(WidgetText.status) ?? String(localized: "No primary interface")
        }
        if let reading, reading.numericValue == nil { return WidgetText.status(reading) }
        return primary.id.name
    }
}

/// The app's briefing while it is fresh; otherwise a rule-based hint from
/// the widget's own sample, labelled as such, with why there is no briefing.
private struct BriefingView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let card = entry.briefing.card(at: entry.date)
        VStack(alignment: .leading, spacing: 4) {
            Label(Statistic.briefing.title, systemImage: Statistic.briefing.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Statistic.briefing.color)
            Spacer(minLength: 0)
            Text(text(card))
                .font(family == .systemSmall ? .callout : .body)
                .lineLimit(family == .systemSmall ? 6 : 4)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            footer(card)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func text(_ card: BriefingCard) -> String {
        if case .briefing(let text, _, _) = card { return text }
        if let snapshot = entry.snapshot { return OfflineHint.text(snapshot) }
        return entry.problem.map { String(localized: "No sample: \($0)") } ?? String(localized: "Collecting…")
    }

    private func footer(_ card: BriefingCard) -> Text {
        switch card {
        case .briefing(_, let model, let end):
            Text("\(model) · 5 min to \(end.formatted(date: .omitted, time: .shortened))")
        case .offline(.off):
            Text("Hint from one sample. Turn on briefings in Coreography's Settings.")
        case .offline(.stale(let since)):
            Text("Hint from one sample. Last briefing \(since.formatted(.dateTime.month(.abbreviated).day().hour().minute())).")
        case .offline(.failed(let message)):
            Text("Hint from one sample. Briefing failed: \(message)")
        case .offline(.unreadable(let reason)):
            Text("Hint from one sample. Briefing unreadable: \(reason)")
        }
    }
}

private enum WidgetText {
    static let percentScale = 100.0
    private static let wholePercentThreshold = 10.0
    enum Format { case percent, bytes, rate }

    static func value(_ reading: DashboardReading?, as format: Format) -> String {
        guard let reading, let value = reading.numericValue else { return "–" }
        let text: String
        switch format {
        case .percent:
            if value > 0, value < 1 {
                text = String(localized: "<1%")
            } else {
                let digits = value >= wholePercentThreshold ? 0 : 1
                text = (value / percentScale).formatted(.percent.precision(.fractionLength(0...digits)))
            }
        case .bytes: text = bytes(value)
        case .rate: text = bytes(value) + "/s"
        }
        return reading.availability == .estimated ? "≈" + text : text
    }

    static func free(_ snapshot: WidgetSnapshot) -> String {
        guard case .measured(_, let available) = snapshot.disk else { return "–" }
        return String(localized: "\(bytes(Double(available))) free")
    }

    static func bytes(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value < Double(Int64.max) else { return "–" }
        return Int64(value).formatted(.byteCount(style: .file))
    }

    static func status(_ reading: DashboardReading) -> String {
        if let reason = reading.reason { return reason }
        switch reading.availability {
        case .measured: return String(localized: "Measured")
        case .estimated: return String(localized: "Estimated")
        case .collecting: return String(localized: "Collecting…")
        case .gap: return String(localized: "Sampling interrupted")
        case .restricted: return String(localized: "Access restricted")
        case .unsupported: return String(localized: "Not supported on this Mac")
        case .unavailable: return String(localized: "Unavailable")
        }
    }
}
