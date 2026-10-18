import AppKit
import SwiftUI
import Charts
import CoreographyServices

/// The menu bar extra: mini lanes from the window's own model, the top
/// offender and a way into the window. It points into the window rather
/// than competing with dedicated menu bar monitors.
@MainActor
struct MenuBarView: View {
    @Bindable var model: DashboardModel
    let hud: HUDController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let capacity = Double(model.latest?.inventory.physicalMemoryBytes ?? 0)
        VStack(alignment: .leading, spacing: 10) {
            MiniLane(
                title: String(localized: "CPU"), value: MetricText.percent(model.reading(for: .cpu)?.numericValue),
                points: model.points(for: .cpu), maximum: MetricText.percentScale, color: .blue
            )
            MiniLane(
                title: String(localized: "Memory"), value: MetricText.bytes(model.reading(for: .memory)?.numericValue),
                points: model.points(for: .memory), maximum: capacity > 0 ? capacity : nil, color: .teal
            )
            MiniLane(
                title: String(localized: "Network ↓"), value: MetricText.rate(model.reading(for: .networkReceived)?.numericValue),
                points: model.points(for: .networkReceived), maximum: nil, color: .blue
            )
            Text(topOffender).font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button(model.displayMode == .live ? "Hold display" : "Return to live") { model.toggleDisplayHold() }
                Button(hud.isShown ? "Hide HUD" : "Show HUD") { hud.toggle() }
                Spacer()
                Button("Open Coreography") {
                    openWindow(id: "dashboard")
                    NSApplication.shared.activate()
                }
            }
        }
        .monospacedDigit()
        .padding(12)
        .frame(width: 280)
    }

    private var topOffender: String {
        guard let top = model.displayedContributors?.cpu.first else { return String(localized: "Top: collecting…") }
        return String(localized: "Top: \(top.name) \(MetricText.percent(top.value))")
    }
}

/// The menu bar title: whole-machine CPU, or a dash while collecting.
struct MenuBarLabel: View {
    let model: DashboardModel

    var body: some View {
        Text(MetricText.percent(model.reading(for: .cpu)?.numericValue)).monospacedDigit()
    }
}

/// One compact lane: title, value and the last minute without axes.
private struct MiniLane: View {
    private static let visibleSeconds: TimeInterval = 60
    let title: String
    let value: String
    let points: [DashboardPoint]
    /// Fixed scale for percentages and capacity; nil autoscales rates.
    let maximum: Double?
    let color: Color

    var body: some View {
        let end = points.last?.time ?? Date()
        let start = end.addingTimeInterval(-Self.visibleSeconds)
        let visible = visiblePoints(points, start, end)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption.weight(.semibold))
            }
            Chart(visible) { point in
                LineMark(
                    x: .value("Time", point.time), y: .value(title, point.value),
                    series: .value("Segment", "mini-\(point.segment)")
                )
                .foregroundStyle(color)
            }
            .chartXScale(domain: start...end)
            .chartYScale(domain: 0...max(1, maximum ?? (visible.map(\.value).max() ?? 1)))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 32)
            .accessibilityLabel("\(title) \(value)")
        }
    }
}
