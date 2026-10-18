import AppKit
import SwiftUI
import Observation
import CoreographyServices

/// Draws the optional live Dock graph (plan: Dock icon, as Activity
/// Monitor offers). It redraws once per sample, and only while a graph
/// is chosen; the app icon needs no drawing.
@MainActor
final class DockTileController {
    private static let size = NSSize(width: 128, height: 128)
    private let model: DashboardModel

    init(model: DashboardModel) {
        self.model = model
        render()
    }

    private func render() {
        // Reading these registers them; any change schedules the next render.
        withObservationTracking {
            let points = model.dockIconPoints
            let tile = NSApplication.shared.dockTile
            if let metric = model.dockIcon.metric, let scale = model.dockIconScale {
                let view = DockGraph(points: points, scale: scale, metric: metric)
                if let hosting = tile.contentView as? NSHostingView<DockGraph> {
                    hosting.rootView = view
                } else {
                    let hosting = NSHostingView(rootView: view)
                    hosting.frame = NSRect(origin: .zero, size: Self.size)
                    tile.contentView = hosting
                }
            } else {
                tile.contentView = nil
            }
            tile.display()
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
    }
}

/// A minute of one lane on a dark tile, with the current value.
struct DockGraph: View {
    let points: [DashboardPoint]
    let scale: Double
    let metric: DashboardMetric

    var body: some View {
        let color: Color = metric == .cpu ? .blue : .teal
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.85))
            GeometryReader { geometry in
                let segments = Dictionary(grouping: points, by: \.segment).values.map { $0.sorted { $0.time < $1.time } }
                let start = points.first?.time ?? Date()
                let span = max(points.last.map { $0.time.timeIntervalSince(start) } ?? 1, 1)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Path { path in
                        for (index, point) in segment.enumerated() {
                            let x = point.time.timeIntervalSince(start) / span * geometry.size.width
                            let y = geometry.size.height * (1 - min(max(point.value / scale, 0), 1))
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(color, lineWidth: 4)
                }
            }
            .padding(EdgeInsets(top: 48, leading: 12, bottom: 12, trailing: 12))
            Text(value)
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(12)
        }
        .frame(width: 128, height: 128)
    }

    private var value: String {
        let latest = points.last?.value
        return metric == .cpu ? MetricText.percent(latest) : MetricText.bytes(latest)
    }
}
