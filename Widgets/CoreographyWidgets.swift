import SwiftUI
import WidgetKit
import CoreographyServices

@main
private struct CoreographyWidgets: WidgetBundle {
    var body: some Widget {
        StatsWidget(statistic: .overview)
        StatsWidget(statistic: .cpu)
        StatsWidget(statistic: .memory)
        StatsWidget(statistic: .network)
    }
}

private enum Statistic: String {
    case overview, cpu, memory, network

    var title: LocalizedStringKey {
        switch self {
        case .overview: "System Overview"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "desktopcomputer"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        }
    }

    var color: Color {
        switch self {
        case .overview, .cpu: .blue
        case .memory: .teal
        case .network: .indigo
        }
    }
}

private struct StatsWidget: Widget {
    let statistic: Statistic

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ch.lkmc.Coreography.widget.\(statistic.rawValue)", provider: StatsProvider()) { entry in
            StatsView(statistic: statistic, entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "coreography://show"))
        }
        .configurationDisplayName(statistic.title)
        .description("A short system sample. macOS controls refreshes; open Coreography for live readings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StatsEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: WidgetSnapshot?
    let problem: String?

    // A second entry ages the sample even when macOS postpones the next refresh.
    static let refreshInterval: TimeInterval = 15 * 60
    static let staleInterval = refreshInterval * 2

    var isStale: Bool {
        guard let snapshot else { return false }
        return date.timeIntervalSince(snapshot.sampledAt) >= Self.staleInterval
    }
}

private struct StatsProvider: TimelineProvider {
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
                    snapshot: snapshot, problem: nil
                ))
            }
            completion(Timeline(entries: entries, policy: .after(entry.date.addingTimeInterval(StatsEntry.refreshInterval))))
        }
    }

    private func sample() async -> StatsEntry {
        do {
            let snapshot = try await WidgetSampler().sample()
            return StatsEntry(date: .now, snapshot: snapshot, problem: nil)
        } catch {
            return StatsEntry(date: .now, snapshot: nil, problem: error.localizedDescription)
        }
    }
}

private struct StatsView: View {
    let statistic: Statistic
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(statistic.title, systemImage: statistic.symbol)
                .font(.caption.weight(.semibold))
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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func readings(_ snapshot: WidgetSnapshot) -> some View {
        switch statistic {
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
        case .overview:
            VStack(alignment: .leading, spacing: 6) {
                overviewRow("CPU", symbol: "cpu", value: WidgetText.value(snapshot.host.cpuPercentOfMachine, as: .percent))
                overviewRow("Memory", symbol: "memorychip", value: WidgetText.value(snapshot.host.memoryUsedBytes, as: .bytes))
                overviewRow("Download", symbol: "arrow.down", value: WidgetText.value(snapshot.primaryInterface?.receivedBytesPerSecond, as: .rate))
                overviewRow("Upload", symbol: "arrow.up", value: WidgetText.value(snapshot.primaryInterface?.sentBytesPerSecond, as: .rate))
            }
        }
    }

    private func overviewRow(_ title: LocalizedStringKey, symbol: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).labelStyle(.iconOnly).foregroundStyle(statistic.color)
            if family == .systemMedium { Text(title).foregroundStyle(.secondary) }
            Spacer(minLength: 4)
            Text(value).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.75)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title) + Text(": \(value)"))
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
