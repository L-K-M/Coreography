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
                Button(model.samplingPaused ? "Resume" : "Pause") {
                    model.samplingPaused ? model.resumeSampling() : model.pauseSampling()
                }
                .help(model.samplingPaused
                      ? "Resume recording; the pause stays as a labelled gap"
                      : "Pause recording; the pause stays as a labelled gap")
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
    let automation: AutomationRouter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content
            // Always shown while the app runs, so links can open a closed window.
            .onAppear { automation.openDashboard = { openWindow(id: "dashboard") } }
    }

    /// The default CPU value stays plain text; anything richer becomes one
    /// template image, the only label a menu bar extra draws reliably.
    @ViewBuilder private var content: some View {
        if model.samplingPaused {
            Text(String(localized: "Paused"))
        } else if model.menuBarItems == MenuBarLayout.defaultItems {
            Text(MetricText.percent(model.reading(for: .cpu)?.numericValue)).monospacedDigit()
        } else if let image = MenuBarRenderer.image(model) {
            Image(nsImage: image)
                .accessibilityLabel(model.menuBarItems.map { MenuBarRenderer.text($0.metric, model) }.joined(separator: ", "))
        } else {
            // A render that produced nothing still shows the values.
            Text(model.menuBarItems.map { MenuBarRenderer.text($0.metric, model) }.joined(separator: " ")).monospacedDigit()
        }
    }
}

@MainActor
enum MenuBarRenderer {
    static func image(_ model: DashboardModel) -> NSImage? {
        let renderer = ImageRenderer(content: MenuBarStrip(model: model))
        // Every display can show a menu bar; the sharpest one sets the scale.
        renderer.scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        guard let image = renderer.nsImage else { return nil }
        // Drawn in black, so the menu bar tints it for light, dark and accent bars.
        image.isTemplate = true
        return image
    }

    static func text(_ metric: MenuBarMetric, _ model: DashboardModel) -> String {
        let value = model.menuBarValue(metric)?.numericValue
        return switch metric {
        case .cpu, .gpu: MetricText.percent(value)
        case .memory: MetricText.bytes(value)
        case .download: "↓" + MetricText.rate(value)
        case .upload: "↑" + MetricText.rate(value)
        case .temperature: ThermalText.celsius(value)
        }
    }

    /// Fixed tops for shares and memory; rates and temperatures scale to their minute.
    static func scale(_ metric: MenuBarMetric, _ model: DashboardModel) -> Double? {
        switch metric {
        case .cpu, .gpu: MetricText.percentScale
        case .memory: model.latest.map { Double($0.inventory.physicalMemoryBytes) }
        case .download, .upload, .temperature: nil
        }
    }
}

private struct MenuBarStrip: View {
    let model: DashboardModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.menuBarItems) { item in
                HStack(spacing: 3) {
                    if item.style != .value {
                        MenuBarSparkline(
                            points: model.menuBarPoints(item.metric), maximum: MenuBarRenderer.scale(item.metric, model)
                        )
                        .frame(width: 28, height: 14)
                    }
                    if item.style != .graph {
                        Text(MenuBarRenderer.text(item.metric, model))
                    }
                }
            }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(.black)
        .frame(height: 18)
    }
}

/// A minute of one series, gaps kept, without axes.
private struct MenuBarSparkline: View {
    let points: [DashboardPoint]
    let maximum: Double?

    var body: some View {
        GeometryReader { geometry in
            let top = maximum ?? max(points.map(\.value).max() ?? 1, 1)
            let bottom = maximum == nil ? (points.map(\.value).min() ?? 0) : 0
            let span = max(top - bottom, .ulpOfOne)
            let start = points.first?.time ?? Date()
            let seconds = max(points.last.map { $0.time.timeIntervalSince(start) } ?? 1, 1)
            Path { path in
                var previous: Int?
                for point in points {
                    let x = point.time.timeIntervalSince(start) / seconds * geometry.size.width
                    let y = geometry.size.height * (1 - min(max((point.value - bottom) / span, 0), 1))
                    if previous == point.segment { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)) }
                    previous = point.segment
                }
            }
            .stroke(Color.black, lineWidth: 1.5)
        }
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
