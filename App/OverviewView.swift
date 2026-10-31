import SwiftUI
import Charts
import CoreographyServices

@MainActor
struct OverviewView: View {
    let model: DashboardModel
    private static let cardSpacing: CGFloat = 16
    private static let minimumCardWidth: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: Self.cardSpacing) {
            if model.scopedApp != nil {
                Text("Cards show subsystem readings. App scope applies to detailed charts and processes.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            ForEach(model.activeAlerts.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { lane in
                Button {
                    model.navigate(to: Self.section(for: lane))
                } label: {
                    Label(model.activeAlerts[lane] ?? "", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.minimumCardWidth), spacing: Self.cardSpacing)],
                      spacing: Self.cardSpacing) {
                ForEach(DashboardSection.allCases.filter { !$0.lanes.isEmpty }) { section in
                    Button {
                        model.navigate(to: section)
                    } label: {
                        OverviewCard(model: model, section: section)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open detailed charts")
                    .accessibilityIdentifier("overview-\(section.rawValue)")
                }
            }

            HStack {
                Text("Busiest apps by CPU").font(.headline)
                Spacer()
                Button("All Processes", systemImage: "arrow.right") { model.navigate(to: .processes) }
            }
            if let snapshot = model.displayedContributors {
                if snapshot.cpu.isEmpty {
                    Text("No CPU activity attributed to apps in this sample.").foregroundStyle(.secondary)
                }
                ForEach(snapshot.cpu) { app in
                    Button {
                        model.scopedApp = app.name
                        model.navigate(to: .timeline)
                    } label: {
                        HStack {
                            Text(app.name)
                            Spacer()
                            Text(MetricText.percent(app.value) + (app.isEstimate ? " est." : ""))
                                .monospacedDigit()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("Recorded contributors at \(snapshot.time.formatted(date: .omitted, time: .standard)); not every process is attributable.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(model.cursorTime == nil ? "Collecting app activity…" : "No app sample near the cursor.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func section(for lane: AlertLane) -> DashboardSection {
        switch lane {
        case .cpu: .cpu
        case .memory: .memory
        case .gpu: .gpu
        case .disk: .storage
        case .network: .network
        case .power, .thermal: .power
        }
    }
}

@MainActor
private struct OverviewCard: View {
    let model: DashboardModel
    let section: DashboardSection
    private static let cornerRadius: CGFloat = 12
    private static let trendHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(LocalizedStringKey(section.title), systemImage: section.symbol)
                    .foregroundStyle(section.tint)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .font(.subheadline.weight(.medium))

            Text(value).font(.system(size: 28, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(context).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).frame(minHeight: 28, alignment: .topLeading)

            trend
        }
        .monospacedDigit()
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private var reading: DashboardReading? {
        switch section {
        case .cpu: model.reading(for: .cpu)
        case .memory: model.reading(for: .memory)
        case .gpu: model.displayedGPUFrame?.devices.first?.utilizationPercent
        case .storage: model.reading(for: .diskRead)
        case .network: model.reading(for: .networkReceived)
        case .power: model.displayedSystemPower
        default: nil
        }
    }

    private var value: String {
        switch section {
        case .cpu, .gpu: MetricText.percent(reading?.numericValue)
        case .memory: MetricText.bytes(reading?.numericValue)
        case .storage, .network: MetricText.rate(reading?.numericValue)
        case .power: MetricText.watts(reading?.numericValue)
        default: "–"
        }
    }

    private var context: String {
        if section == .power {
            let draw = reading?.numericValue == nil ? (reading?.reason ?? String(localized: "System draw unavailable"))
                : String(localized: "System draw")
            return String(localized: "\(draw) · thermal pressure \(ThermalText.level(model.displayedFrame?.thermalPressure))")
        }
        if section == .gpu, reading == nil {
            return model.displayedGPUFrame?.enumeration.reason ?? String(localized: "No GPU observed")
        }
        guard reading?.numericValue != nil else {
            return reading?.reason ?? (model.cursorTime == nil
                ? String(localized: "No reading yet; open for details")
                : String(localized: "No reading near the cursor"))
        }
        switch section {
        case .cpu:
            return String(localized: "Whole machine · \(model.displayedFrame?.inventory.logicalCPUCount ?? 0) logical CPUs")
        case .memory:
            let capacity = MetricText.bytes(model.displayedFrame.map { Double($0.inventory.physicalMemoryBytes) })
            let pressure: String = switch model.displayedFrame?.memory.pressureLevel {
            case .normal: String(localized: "normal")
            case .warning: String(localized: "warning")
            case .critical: String(localized: "critical")
            case nil: String(localized: "unavailable")
            }
            return String(localized: "of \(capacity), estimated · pressure \(pressure)")
        case .gpu:
            return model.displayedGPUFrame?.devices.first?.name ?? String(localized: "GPU busy")
        case .storage:
            return String(localized: "Read · write \(MetricText.rate(model.reading(for: .diskWritten)?.numericValue))")
        case .network:
            return String(localized: "Download · upload \(MetricText.rate(model.reading(for: .networkSent)?.numericValue))")
        case .power:
            return String(localized: "System draw · thermal pressure \(ThermalText.level(model.displayedFrame?.thermalPressure))")
        default: return ""
        }
    }

    private var points: [DashboardPoint] {
        switch section {
        case .cpu: model.points(for: .cpu)
        case .memory: model.points(for: .memory)
        case .gpu:
            // Match the named device, never splice different GPUs into one trend.
            model.gpuSeries().first { $0.id == model.displayedGPUFrame?.devices.first?.id }?.points ?? []
        case .storage: model.points(for: .diskRead)
        case .network: model.points(for: .networkReceived)
        case .power: model.hottestTemperaturePoints()
        default: []
        }
    }

    @ViewBuilder private var trend: some View {
        let end = model.visibleWindow?.upperBound ?? model.displayedEndTime ?? Date()
        let range = model.visibleWindow ?? end.addingTimeInterval(-model.timeRange.seconds)...end
        let visible = visiblePoints(points, range.lowerBound, range.upperBound)
        VStack(alignment: .leading, spacing: 2) {
            if visible.isEmpty {
                Text("No trend in this range").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Self.trendHeight, alignment: .leading)
            } else {
                Chart(visible) { point in
                    LineMark(x: .value("Time", point.time), y: .value("Value", point.value),
                             series: .value("Segment", point.segment))
                        .foregroundStyle(section.tint)
                        .interpolationMethod(.linear)
                }
                .chartXScale(domain: range)
                .chartYScale(domain: 0...maximum(visible))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: Self.trendHeight)
                .accessibilityHidden(true)
            }
            Text(section == .power ? String(localized: "Hottest sensor · \(ThermalText.celsius(model.displayedSensorFrame?.hottest?.celsius.numericValue))")
                 : String(localized: "Trend over the selected time range"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func maximum(_ points: [DashboardPoint]) -> Double {
        switch section {
        case .cpu, .gpu: MetricText.percentScale
        case .memory: max(1, Double(model.latest?.inventory.physicalMemoryBytes ?? 1))
        case .power: ThermalText.celsiusCeiling
        default: max(1, points.map(\.value).max() ?? 1)
        }
    }
}

extension DashboardSection {
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "display"
        case .storage: "internaldrive"
        case .network: "network"
        case .power: "bolt.heart"
        case .processes: "list.bullet.rectangle"
        case .timeline: "chart.xyaxis.line"
        case .startup: "power"
        case .recordings: "record.circle"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: .blue
        case .memory: .teal
        case .gpu: .purple
        case .storage: .indigo
        case .network: .cyan
        case .power: .orange
        default: .accentColor
        }
    }
}
