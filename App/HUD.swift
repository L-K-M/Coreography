import AppKit
import SwiftUI
import Observation
import CoreographyServices

/// A small always-on-top readout over full-screen apps and games (plan:
/// the HUD). It never takes focus or clicks, joins every Space, and reads
/// the window's own model, so one sampler serves it. Frame rate waits for
/// the performance-mode spikes (S4, S6).
@MainActor
@Observable
final class HUDController {
    private static let size = NSSize(width: 230, height: 146)
    private static let margin: CGFloat = 16

    private(set) var isShown = false
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private let model: DashboardModel

    init(model: DashboardModel) { self.model = model }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
        isShown = true
    }

    func hide() {
        panel?.orderOut(nil)
        isShown = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false
        )
        // Above full-screen apps in their own Space, and on every Space.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }

    /// The top-right corner of the screen with the menu bar, inside its visible frame.
    private func place(_ panel: NSPanel) {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - Self.size.width - Self.margin, y: frame.maxY - Self.size.height - Self.margin
        ))
    }
}

/// Four readings, large enough to glance at during a game.
private struct HUDView: View {
    let model: DashboardModel

    var body: some View {
        let gpu = model.displayedGPUFrame?.devices.compactMap(\.utilizationPercent.numericValue).max()
        VStack(alignment: .leading, spacing: 3) {
            row("CPU", MetricText.percent(model.latest?.cpuPercentOfMachine.numericValue))
            row("Cores", model.displayedSiliconFrame?.topTier.map(SiliconText.tier) ?? "–")
            row("GPU", MetricText.percent(gpu))
            row("GPU clock", MetricText.frequency(model.displayedSiliconFrame?.gpuFrequencyMHz.numericValue))
            row("Temp", ThermalText.celsius(model.displayedSensorFrame?.hottest?.celsius.numericValue))
            row("Power", MetricText.watts(model.displayedSystemPower?.numericValue))
            if let hint = model.bottleneckHints.first {
                Text(hint.title).foregroundStyle(.orange)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).opacity(0.7)
            Spacer()
            Text(value)
        }
    }
}
