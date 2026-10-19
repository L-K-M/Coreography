import AppKit
import SwiftUI
import Observation
import CoreographyServices

/// A small always-on-top readout over full-screen apps and games (plan:
/// the HUD). It never takes focus, joins every Space, and reads the
/// window's own model, so one sampler serves it. One density control
/// picks how much it shows; frame rate waits for macOS 27's source (S4).
@MainActor
@Observable
final class HUDController {
    private static let margin: CGFloat = 16
    /// Points per line at text scale 1, with the panel's padding.
    private static let lineHeight: CGFloat = 17
    private static let padding: CGFloat = 20
    private static let blockWidth: CGFloat = 250
    private static let lineWidth: CGFloat = 430
    private static let positionsKey = "hud.positions"

    private(set) var isShown = false
    var settings = HUDSettings.saved() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.corner != oldValue.corner { forgetDraggedPosition() }
            if isShown, let panel { configure(panel) }
        }
    }
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private let model: DashboardModel
    @ObservationIgnored private var moveObserver: NSObjectProtocol?

    init(model: DashboardModel) { self.model = model }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    func cycleDensity() { settings.density = settings.density.next }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        configure(panel)
        panel.orderFrontRegardless()
        isShown = true
    }

    func hide() {
        panel?.orderOut(nil)
        isShown = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size()),
            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false
        )
        // Above full-screen apps in their own Space, and on every Space.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(model: model, controller: self))
        // A drag (click-through off) is remembered for the display it ends on.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rememberPosition() }
        }
        return panel
    }

    private func configure(_ panel: NSPanel) {
        panel.ignoresMouseEvents = settings.clickThrough
        panel.isMovableByWindowBackground = !settings.clickThrough
        panel.alphaValue = settings.opacity
        panel.setContentSize(size())
        place(panel)
    }

    /// One line for level 2, a block otherwise; rows grow with density.
    private func size() -> NSSize {
        let scale = CGFloat(settings.textScale)
        let items = HUDLayout.items(settings.density, frameRateAvailable: false, hasHint: true).count
        if settings.density == .line {
            return NSSize(width: Self.lineWidth * scale, height: Self.lineHeight * scale + Self.padding)
        }
        return NSSize(width: Self.blockWidth * scale, height: CGFloat(items) * Self.lineHeight * scale + Self.padding)
    }

    /// A dragged position on this display wins; otherwise the chosen corner.
    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        if let saved = positions()[Self.key(screen)] {
            panel.setFrameOrigin(NSPoint(x: saved[0], y: saved[1]))
            return
        }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let left = frame.minX + Self.margin
        let right = frame.maxX - size.width - Self.margin
        let bottom = frame.minY + Self.margin
        let top = frame.maxY - size.height - Self.margin
        let origin = switch settings.corner {
        case .topLeft: NSPoint(x: left, y: top)
        case .topRight: NSPoint(x: right, y: top)
        case .bottomLeft: NSPoint(x: left, y: bottom)
        case .bottomRight: NSPoint(x: right, y: bottom)
        }
        panel.setFrameOrigin(origin)
    }

    private func rememberPosition() {
        guard !settings.clickThrough, let panel, let screen = panel.screen else { return }
        var all = positions()
        all[Self.key(screen)] = [panel.frame.origin.x, panel.frame.origin.y]
        UserDefaults.standard.set(all, forKey: Self.positionsKey)
    }

    private func forgetDraggedPosition() {
        UserDefaults.standard.removeObject(forKey: Self.positionsKey)
    }

    private func positions() -> [String: [Double]] {
        UserDefaults.standard.dictionary(forKey: Self.positionsKey) as? [String: [Double]] ?? [:]
    }

    /// Displays are told apart by their number, which survives rearranging.
    private static func key(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number.map { "\($0.uint32Value)" } ?? screen.localizedName
    }
}

/// The chosen readings, large enough to glance at during a game.
private struct HUDView: View {
    let model: DashboardModel
    let controller: HUDController

    var body: some View {
        let settings = controller.settings
        let items = HUDLayout.items(settings.density, frameRateAvailable: false, hasHint: !model.bottleneckHints.isEmpty)
        let scale = CGFloat(settings.textScale)
        Group {
            if settings.density == .line {
                Text(items.map { "\(HUDText.label($0)) \(HUDText.value($0, model))" }.joined(separator: " | "))
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items, id: \.self) { item in
                        if item == .hint {
                            Text(model.bottleneckHints.first?.title ?? "").foregroundStyle(.orange)
                        } else {
                            HStack {
                                Text(HUDText.label(item)).opacity(0.7)
                                Spacer()
                                Text(HUDText.value(item, model))
                            }
                        }
                    }
                }
            }
        }
        .font(.system(size: 12 * scale, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .shadow(color: settings.scrim ? .clear : .black, radius: 2)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(settings.scrim ? Color.black.opacity(0.6) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// Labels and values for each HUD item; missing readings show a dash.
@MainActor
private enum HUDText {
    static func label(_ item: HUDItem) -> String {
        switch item {
        case .frameRate: String(localized: "FPS")
        case .cpu: String(localized: "CPU")
        case .topTier, .tiers: String(localized: "Cores")
        case .gpu: String(localized: "GPU")
        case .gpuClock: String(localized: "GPU clock")
        case .power: String(localized: "Power")
        case .temperature: String(localized: "Temp")
        case .thermalPressure: String(localized: "Thermal")
        case .memoryPressure: String(localized: "Memory")
        case .swap: String(localized: "Swap")
        case .network: String(localized: "Network")
        case .batteryTime: String(localized: "Battery")
        case .fans: String(localized: "Fans")
        case .hint: ""
        }
    }

    static func value(_ item: HUDItem, _ model: DashboardModel) -> String {
        let frame = model.displayedFrame
        switch item {
        case .frameRate:
            return "–"
        case .cpu:
            return MetricText.percent(frame?.cpuPercentOfMachine.numericValue)
        case .topTier:
            return model.displayedSiliconFrame?.topTier.map(SiliconText.tier) ?? "–"
        case .tiers:
            return SiliconText.tiers(model.displayedSiliconFrame)
        case .gpu:
            return MetricText.percent(model.displayedGPUFrame?.devices.compactMap(\.utilizationPercent.numericValue).max())
        case .gpuClock:
            return MetricText.frequency(model.displayedSiliconFrame?.gpuFrequencyMHz.numericValue)
        case .power:
            let power = model.displayedSystemPower
            return MetricText.watts(power?.numericValue) + (power?.availability == .estimated ? " " + String(localized: "est.") : "")
        case .temperature:
            return ThermalText.celsius(model.displayedSensorFrame?.hottest?.celsius.numericValue)
        case .thermalPressure:
            return frame.flatMap { CapturedThermalPressure(reading: $0.thermalPressure) }.map { "\($0)" } ?? "–"
        case .memoryPressure:
            return frame?.memory.pressureLevel.map { "\($0)" } ?? "–"
        case .swap:
            return MetricText.bytes(frame?.memory.swapUsedBytes.numericValue)
        case .network:
            let network = model.networkReadings.last
            return network.map { NetworkText.rates($0.received, $0.sent) } ?? "–"
        case .batteryTime:
            let minutes = model.displayedPowerFrame?.batteryMinutesRemaining.numericValue
            return minutes.map { Duration.seconds($0 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) } ?? "–"
        case .fans:
            let fans = model.displayedSensorFrame?.fans ?? []
            return fans.isEmpty ? "–" : fans.map { ThermalText.rpm($0.rpm.numericValue) }.joined(separator: " ")
        case .hint:
            return model.bottleneckHints.first?.title ?? ""
        }
    }
}
