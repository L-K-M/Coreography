import SwiftUI
import AppKit
import CoreographyServices

/// Where the CPU braid's lens stands. The plot's gestures, its keys and the
/// reading card all drive this one inspection.
///
/// ```text
///  closed ─pull──▶ pulling ─release past 0.25─▶ open ─Esc / click away─▶ folding ─0.24 s─▶ closed
///    │                └─release short of it───────────────────────────▶ folding
///    └─click or U──▶ open
/// ```
/// While it is open the display holds, so the moment being read cannot
/// slide away; collection continues underneath, as with Space.
@MainActor
@Observable
final class BraidInspection {
    enum Phase: Equatable { case closed, pulling, open, folding }

    struct Motion: Equatable {
        let from: Double
        let to: Double
        let start: Date
        let duration: Double
        /// The seams ring after a fold: decoration, never data.
        let rings: Bool

        var seconds: Double { duration + (rings ? BraidLens.ringSeconds : 0) }
    }

    private(set) var phase: Phase = .closed
    /// The inspected moment; nil while closed.
    private(set) var time: Date?
    /// The hand's spread while pulling; animations start from wherever it is.
    private(set) var pullSpread = 0.0
    private(set) var motion: Motion?
    /// When an app was caught: a glint runs along its strand from the lens.
    private(set) var glint: Date?
    /// The glint's run, from the lens to both ends of the plot.
    static let glintSeconds = 0.45
    /// The strand under the pointer or chosen with the arrow keys, by index.
    var focused: Int?
    /// At rest, the strand under the pointer; set only when it changes, so
    /// moving within one strand redraws nothing.
    private(set) var hovered: Int?

    /// The model's hold generation after this inspection held the display;
    /// nil when the person's own hold was already in place.
    @ObservationIgnored private var ownHold: Int?
    @ObservationIgnored private var motionToken = UUID()
    @ObservationIgnored private let feedback = InteractionFeedback()
    @ObservationIgnored private var lastHaptic: ContinuousClock.Instant?
    /// Where a pull started from: a pull on an open lens starts open.
    @ObservationIgnored private var pullBase = 0.0
    /// The opening cue sounds once per pull, however the hand wobbles.
    @ObservationIgnored private var openCuePlayed = false
    private static let hapticSpacing = Duration.milliseconds(100)

    var isOpen: Bool { phase != .closed }
    /// Read from AppKit when motion starts, so it is current at that moment.
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Something is moving, so the braid redraws every frame until it stops.
    var isAnimating: Bool { motion != nil || glint != nil }
    func setHovered(_ index: Int?) {
        if hovered != index { hovered = index }
    }

    func spread(at date: Date) -> Double {
        if let motion {
            return BraidLens.settle(
                from: motion.from, to: motion.to, elapsed: date.timeIntervalSince(motion.start), duration: motion.duration
            )
        }
        switch phase {
        case .pulling: return pullSpread
        case .open: return 1
        case .closed, .folding: return 0
        }
    }

    func ring(at date: Date) -> Double {
        guard let motion, motion.rings else { return 0 }
        return BraidLens.ring(elapsed: date.timeIntervalSince(motion.start) - motion.duration)
    }

    func beginPull(at time: Date, model: DashboardModel) {
        hold(model)
        pullBase = spread(at: Date())
        openCuePlayed = pullBase >= 1
        phase = .pulling
        self.time = time
        pullSpread = pullBase
        motion = nil
        hovered = nil
        pin(time, model: model)
    }

    /// The lens moves in whole intervals, with a detent at each: the card
    /// reads one interval, and the window redraws once per step, not per event.
    func updatePull(travel: Double, time: Date?, model: DashboardModel) {
        guard phase == .pulling else { return }
        pullSpread = max(pullBase, BraidLens.spread(travel: travel))
        if pullSpread >= 1 { playOpenCue() }
        guard let time, time != self.time else { return }
        self.time = time
        pin(time, model: model)
        tick()
    }

    /// Released far enough, the lens stays open for reading; short of it, it folds.
    func endPull(model: DashboardModel) {
        guard phase == .pulling else { return }
        guard pullSpread >= BraidLens.latchThreshold else { return fold(model: model) }
        phase = .open
        playOpenCue()
        animate(from: pullSpread, to: 1, duration: reduceMotion ? 0 : BraidLens.openSeconds, rings: false)
    }

    private func playOpenCue() {
        guard !openCuePlayed else { return }
        openCuePlayed = true
        feedback.play(.open)
    }

    func open(at time: Date, model: DashboardModel) {
        hold(model)
        let from = spread(at: Date())
        phase = .open
        self.time = time
        pin(time, model: model)
        focused = nil
        hovered = nil
        animate(from: from, to: 1, duration: reduceMotion ? 0 : BraidLens.openSeconds, rings: false)
        feedback.play(.open)
    }

    /// Keyboard stepping while open: the lens moves to another interval.
    func move(to time: Date, model: DashboardModel) {
        guard phase == .open else { return }
        self.time = time
        pin(time, model: model)
    }

    func fold(model: DashboardModel) {
        guard phase == .pulling || phase == .open else { return }
        let from = spread(at: Date())
        phase = .folding
        focused = nil
        animate(from: from, to: 0, duration: reduceMotion ? 0 : BraidLens.foldSeconds, rings: !reduceMotion) { [weak self] in
            guard let self, self.phase == .folding else { return }
            self.phase = .closed
            self.time = nil
            model.cursorPinned = false
            model.cursorTime = nil
            self.release(model)
        }
        feedback.play(.fold)
    }

    /// Catching an app scopes the window to it; Command-Z puts the previous scope back.
    func scope(to app: String, model: DashboardModel) {
        guard model.scopedApp != app else { return }
        Self.setScope(app, of: model, inspection: self, undoManager: NSApp.keyWindow?.undoManager)
        feedback.play(.scope(app: app))
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        guard !reduceMotion else { return }
        let caught = Date()
        glint = caught
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.glintSeconds))
            guard let self, self.glint == caught else { return }
            self.glint = nil
        }
    }

    /// Sets the scope so that Command-Z puts the previous one back and
    /// Command-Shift-Z sets it again.
    /// The scoped app keeps its own strand, which can reorder the rest, so
    /// focus and hover indexes mean nothing afterwards, on undo as well.
    private static func setScope(
        _ app: String?, of model: DashboardModel, inspection: BraidInspection?, undoManager: UndoManager?
    ) {
        let previous = model.scopedApp
        model.scopedApp = app
        inspection?.focused = nil
        inspection?.setHovered(nil)
        undoManager?.registerUndo(withTarget: model) { [weak inspection] target in
            MainActor.assumeIsolated { setScope(previous, of: target, inspection: inspection, undoManager: undoManager) }
        }
        if let app { undoManager?.setActionName(String(localized: "Scope to \(app)")) }
    }

    /// Focus moves with one tick of the trackpad.
    func setFocus(_ index: Int?) {
        guard index != focused else { return }
        focused = index
        if index != nil { tick() }
    }

    /// One alignment tick, at most every 100 ms however fast the hand moves.
    private func tick() {
        let now = ContinuousClock.now
        if let lastHaptic, now - lastHaptic < Self.hapticSpacing { return }
        lastHaptic = now
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func pin(_ time: Date, model: DashboardModel) {
        model.cursorPinned = true
        model.cursorTime = time
    }

    private func animate(from: Double, to: Double, duration: Double, rings: Bool, completion: (@MainActor () -> Void)? = nil) {
        let token = UUID()
        motionToken = token
        let motion = Motion(from: from, to: to, start: Date(), duration: duration, rings: rings)
        self.motion = duration > 0 || rings ? motion : nil
        // The timeline pauses once the motion is over, so nothing redraws at rest.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(motion.seconds))
            guard let self, self.motionToken == token else { return }
            self.motion = nil
            completion?()
        }
    }

    /// A live display holds for the inspection; one already held stays the person's.
    private func hold(_ model: DashboardModel) {
        guard model.displayMode == .live else { return }
        model.toggleDisplayHold()
        ownHold = model.holdGeneration
    }

    /// Back to live only while this inspection's own hold is the one in
    /// place: a hold the person made or changed since stays theirs.
    private func release(_ model: DashboardModel) {
        defer { ownHold = nil }
        guard let ownHold, model.holdGeneration == ownHold, model.displayMode == .held, model.panOffset == 0,
              model.openRecording == nil else { return }
        model.toggleDisplayHold()
    }

    /// The lane went away mid-inspection: close at once, no animation.
    func reset(model: DashboardModel) {
        guard phase != .closed else { return }
        motionToken = UUID()
        motion = nil
        phase = .closed
        time = nil
        focused = nil
        model.cursorPinned = false
        model.cursorTime = nil
        release(model)
    }
}

/// The CPU plot's mapping between time, share and points; y grows downward.
struct BraidPlot {
    let rect: CGRect
    let window: ClosedRange<Date>
    let maximum: Double

    func x(_ time: Date) -> CGFloat {
        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        guard span > 0 else { return rect.minX }
        return rect.minX + CGFloat(time.timeIntervalSince(window.lowerBound) / span) * rect.width
    }

    func time(atX x: CGFloat) -> Date {
        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        let share = rect.width > 0 ? Double((x - rect.minX) / rect.width) : 0
        return window.lowerBound.addingTimeInterval(min(max(share, 0), 1) * span)
    }

    func y(_ value: Double) -> CGFloat { rect.maxY - height(value) }

    func height(_ value: Double) -> CGFloat {
        maximum > 0 ? CGFloat(value / maximum) * rect.height : 0
    }
}

/// Each strand's measured band per interval, laid out once per braid and
/// plot size; only the lens offsets change while the hand moves.
struct BraidGeometry {
    struct Step {
        let start: CGFloat
        let end: CGFloat
        let lower: Double
        let upper: Double
    }

    let plot: BraidPlot
    let braid: CPUBraid
    /// Per strand, per segment: the interval steps it occupies.
    let runs: [[[Step]]]
    /// Extra room above the plot for lifted strands.
    static let headroom: CGFloat = 72
    /// Resampling inside the lens, so the opening tapers smoothly.
    private static let sampleSpacing: CGFloat = 3

    init(plot: BraidPlot, braid: CPUBraid) {
        self.plot = plot
        self.braid = braid
        var runs = Array(repeating: [[Step]](), count: braid.strands.count)
        var segment: [Int?] = Array(repeating: nil, count: braid.strands.count)
        var previousEnd: [Date?] = Array(repeating: nil, count: braid.strands.count)
        for column in braid.columns {
            var lower = 0.0
            for index in braid.strands.indices {
                guard let share = column.shares[index] else {
                    // Unknown here: this strand breaks, the ones below carry on.
                    previousEnd[index] = nil
                    continue
                }
                // An interval the window cuts is drawn only inside it.
                let start = plot.x(max(column.start, plot.window.lowerBound))
                let end = plot.x(min(column.end, plot.window.upperBound))
                let step = Step(start: start, end: end, lower: lower, upper: lower + share)
                if segment[index] == column.segment, previousEnd[index] == column.start {
                    runs[index][runs[index].count - 1].append(step)
                } else {
                    runs[index].append([step])
                }
                segment[index] = column.segment
                previousEnd[index] = column.end
                lower += share
            }
        }
        self.runs = runs
    }

    /// One strand's outline per run, lifted by the lens.
    func paths(strand index: Int, lens: LensState) -> [Path] {
        runs[index].map { steps in
            var upper: [CGPoint] = []
            var lower: [CGPoint] = []
            for step in steps {
                for x in samples(step.start, step.end, lens: lens) {
                    let lift = lens.offset(index: index, x: x, width: plot.rect.width)
                    upper.append(CGPoint(x: x, y: plot.y(step.upper) - lift))
                    lower.append(CGPoint(x: x, y: plot.y(step.lower) - lift))
                }
            }
            // One subpath round the band: addLines starts a new subpath each call.
            var path = Path()
            path.addLines(upper + lower.reversed())
            path.closeSubpath()
            return path
        }
    }

    /// The strand's top edge, for seams and highlights.
    func topEdges(strand index: Int, lens: LensState, ring: CGFloat = 0) -> [Path] {
        runs[index].map { steps in
            var points: [CGPoint] = []
            for step in steps {
                for x in samples(step.start, step.end, lens: lens) {
                    let open = lens.falloff(x: x, width: plot.rect.width)
                    let lift = lens.offset(index: index, x: x, width: plot.rect.width)
                    points.append(CGPoint(x: x, y: plot.y(step.upper) - lift - ring * open))
                }
            }
            var path = Path()
            path.addLines(points)
            return path
        }
    }

    /// Each strand's band at `x` in plot points, bottom first, y upward
    /// from the baseline, for focus and leader lines.
    func bands(atX x: CGFloat, lens: LensState) -> [(lower: Double, upper: Double)]? {
        guard let column = braid.column(at: plot.time(atX: x)) else { return nil }
        var lower = 0.0
        return braid.strands.indices.map { index in
            let share = column.shares[index] ?? 0
            let lift = Double(lens.offset(index: index, x: x, width: plot.rect.width))
            let band = (lower: Double(plot.height(lower)) + lift, upper: Double(plot.height(lower + share)) + lift)
            lower += share
            return band
        }
    }

    /// A step's two ends, plus points every 3 pt where it crosses the lens.
    private func samples(_ start: CGFloat, _ end: CGFloat, lens: LensState) -> [CGFloat] {
        guard lens.spread > 0 else { return [start, end] }
        let half = lens.halfWidth(width: plot.rect.width)
        let low = max(start, lens.center - half)
        let high = min(end, lens.center + half)
        guard high > low else { return [start, end] }
        var xs = [start]
        var x = low
        while x < high {
            if x > start { xs.append(x) }
            x += Self.sampleSpacing
        }
        xs.append(end)
        return xs
    }
}

/// The lens at one frame: where it is and how far open.
struct LensState {
    let center: CGFloat
    let spread: Double

    static let closed = LensState(center: 0, spread: 0)

    func halfWidth(width: CGFloat) -> CGFloat {
        CGFloat(BraidLens.halfWidth(spread: spread, plotWidth: Double(width)))
    }

    func falloff(x: CGFloat, width: CGFloat) -> CGFloat {
        guard spread > 0 else { return 0 }
        return CGFloat(BraidLens.falloff(x: Double(x), center: Double(center), halfWidth: Double(halfWidth(width: width))))
    }

    func offset(index: Int, x: CGFloat, width: CGFloat) -> CGFloat {
        guard spread > 0 else { return 0 }
        return CGFloat(BraidLens.offset(
            index: index, x: Double(x), center: Double(center), spread: spread, plotWidth: Double(width)
        ))
    }
}

/// Strand colours. At rest the braid is the CPU lane's blue, darkest at
/// the bottom; pulled open, each app's strand blooms into a muted version
/// of its icon's hue, so the window shows where every app worked.
struct BraidPalette {
    let rest: [Color]
    let identity: [Color]

    private static let restOpacities: [Double] = [0.62, 0.53, 0.45, 0.38, 0.32, 0.27]
    private static let otherOpacity = 0.2
    private static let identitySaturation = 0.5

    @MainActor
    init(braid: CPUBraid, bundles: [String: String?], dark: Bool) {
        let strands = braid.strands
        let iconHues = strands.map { strand -> Double in
            guard let app = strand.appName else { return BraidPalette.neutralHue }
            if let bundle = bundles[app] ?? nil, let hue = IconHues.hue(bundle) { return hue }
            return BraidPalette.hue(forName: app)
        }
        let hues = BraidLens.separatedHues(iconHues)
        let brightness = dark ? 0.86 : 0.74
        var rest: [Color] = []
        var identity: [Color] = []
        var named = 0
        for (index, strand) in strands.enumerated() {
            switch strand.kind {
            case .app:
                let opacity = Self.restOpacities[min(named, Self.restOpacities.count - 1)]
                named += 1
                rest.append(Color.blue.opacity(opacity))
                identity.append(Color(hue: hues[index], saturation: Self.identitySaturation, brightness: brightness))
            case .otherApps:
                rest.append(Color.blue.opacity(Self.otherOpacity))
                identity.append(Color.gray.opacity(0.45))
            case .unattributed:
                rest.append(Color.secondary.opacity(0.1))
                identity.append(Color.secondary.opacity(0.16))
            }
        }
        self.rest = rest
        self.identity = identity
    }

    /// The fill at a spread: rest blue blooming to identity as it opens.
    func fill(_ index: Int, spread: Double) -> Color {
        rest[index].mix(with: identity[index], by: min(max(spread, 0), 1))
    }

    private static let neutralHue = 0.6

    /// No bundle, no icon: a stable hue from the name (FNV-1a, not the per-launch hash).
    private static func hue(forName name: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Double(hash % 360) / 360
    }
}

/// The dominant hue of an app's icon, read once per bundle from a 16 pt
/// rendering, weighting each pixel by how colourful and opaque it is.
@MainActor
enum IconHues {
    private static var cache: [String: Double?] = [:]
    private static let side = 16
    /// Below this, an icon is grey enough that its hue means nothing.
    private static let minimumColour = 0.08

    static func hue(_ bundlePath: String) -> Double? {
        if let cached = cache[bundlePath] { return cached }
        let hue = measure(AppIcons.icon(bundlePath))
        cache[bundlePath] = hue
        return hue
    }

    private static func measure(_ image: NSImage) -> Double? {
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        // Hue is an angle: average it as a vector so reds either side of 0 agree.
        var x = 0.0
        var y = 0.0
        var weight = 0.0
        for index in 0..<(side * side) {
            let alpha = Double(pixels[index * 4 + 3]) / 255
            guard alpha > 0 else { continue }
            let red = Double(pixels[index * 4]) / 255 / alpha
            let green = Double(pixels[index * 4 + 1]) / 255 / alpha
            let blue = Double(pixels[index * 4 + 2]) / 255 / alpha
            let high = max(red, green, blue)
            let low = min(red, green, blue)
            let chroma = high - low
            guard chroma > 0 else { continue }
            var hue: Double
            if high == red { hue = (green - blue) / chroma } else if high == green { hue = (blue - red) / chroma + 2 } else {
                hue = (red - green) / chroma + 4
            }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            let pixelWeight = chroma * alpha
            x += cos(hue * 2 * .pi) * pixelWeight
            y += sin(hue * 2 * .pi) * pixelWeight
            weight += pixelWeight
        }
        guard weight / Double(side * side) > minimumColour else { return nil }
        let angle = atan2(y, x) / (2 * .pi)
        return angle < 0 ? angle + 1 : angle
    }
}

/// The braid under the CPU lane's marks: strands, seams and the host line.
/// It animates only while the lens moves; at rest it redraws with the data.
/// Equatable, so a cursor move elsewhere does not repaint it; the
/// inspection it observes still does.
struct BraidLayer: View, Equatable {
    let geometry: BraidGeometry
    let palette: BraidPalette
    let host: [DashboardPoint]
    let inspection: BraidInspection
    let scopedIndex: Int?

    var body: some View {
        TimelineView(.animation(paused: !inspection.isAnimating)) { timeline in
            let spread = inspection.spread(at: timeline.date)
            let ring = inspection.ring(at: timeline.date)
            let glint = inspection.glint.map { timeline.date.timeIntervalSince($0) / BraidInspection.glintSeconds }
            let center = inspection.time.map { geometry.plot.x($0) } ?? 0
            let lens = LensState(center: center, spread: inspection.isOpen || inspection.motion != nil ? spread : 0)
            let hovered = inspection.isOpen ? inspection.focused : inspection.hovered
            // Chart coordinates, with room above the chart for lifted strands.
            Canvas { context, _ in
                context.translateBy(x: 0, y: BraidGeometry.headroom)
                draw(in: &context, lens: lens, ring: CGFloat(ring), hovered: hovered)
                if let glint, glint < 1, let scopedIndex {
                    drawGlint(in: &context, strand: scopedIndex, progress: glint, lens: lens)
                }
            }
            .padding(.top, -BraidGeometry.headroom)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    nonisolated static func == (lhs: BraidLayer, rhs: BraidLayer) -> Bool {
        MainActor.assumeIsolated {
            lhs.geometry.braid.id == rhs.geometry.braid.id && lhs.geometry.plot.rect == rhs.geometry.plot.rect
                && lhs.geometry.plot.window == rhs.geometry.plot.window && lhs.palette.identity == rhs.palette.identity
                && lhs.palette.rest == rhs.palette.rest && lhs.scopedIndex == rhs.scopedIndex
                && lhs.host.count == rhs.host.count && lhs.host.first?.id == rhs.host.first?.id
                && lhs.host.last?.id == rhs.host.last?.id && lhs.inspection === rhs.inspection
        }
    }

    private func draw(in context: inout GraphicsContext, lens: LensState, ring: CGFloat, hovered: Int?) {
        let rect = geometry.plot.rect
        let lensRect = CGRect(
            x: lens.center - lens.halfWidth(width: rect.width), y: rect.minY - BraidGeometry.headroom,
            width: lens.halfWidth(width: rect.width) * 2, height: rect.height + BraidGeometry.headroom
        )

        for index in geometry.braid.strands.indices {
            let paths = geometry.paths(strand: index, lens: lens)
            let fill = index == scopedIndex ? Color.accentColor.opacity(0.85) : palette.fill(index, spread: lens.spread)

            // Lifted strands cast a soft shadow, only where the lens lifts them.
            if lens.spread > 0, index > 0 {
                var shadowed = context
                shadowed.clip(to: Path(lensRect))
                shadowed.addFilter(.shadow(color: .black.opacity(0.22 * min(lens.spread, 1)), radius: 2.5, y: 1.5))
                for path in paths { shadowed.fill(path, with: .color(fill)) }
            }
            for path in paths { context.fill(path, with: .color(fill)) }

            if geometry.braid.strands[index].kind == .unattributed {
                for path in paths { hatch(path, in: &context) }
            }

            // Seams in the lane's background colour read as fibres; the lifted top catches the light.
            let edges = geometry.topEdges(strand: index, lens: lens, ring: index.isMultiple(of: 2) ? ring : -ring)
            for edge in edges {
                context.stroke(edge, with: .color(Color(nsColor: .controlBackgroundColor)), lineWidth: 0.75)
                if index == hovered || index == scopedIndex {
                    context.stroke(edge, with: .color(.white.opacity(0.7)), lineWidth: 1.25)
                } else if lens.spread > 0 || ring != 0 {
                    var lit = context
                    lit.clip(to: Path(lensRect))
                    lit.stroke(edge, with: .color(.white.opacity(0.35 * min(lens.spread, 1) + Double(abs(ring)) * 0.2)), lineWidth: 1)
                }
            }
        }

        drawHost(in: &context, lens: lens, lensRect: lensRect)
    }

    /// The caught app's thread lights up from the lens outward, so its whole
    /// history in the window shows at a glance.
    private func drawGlint(in context: inout GraphicsContext, strand: Int, progress: Double, lens: LensState) {
        let rect = geometry.plot.rect
        let origin = inspection.time.map { geometry.plot.x($0) } ?? rect.midX
        let reach = CGFloat(progress) * max(origin - rect.minX, rect.maxX - origin)
        let fade = 1 - progress
        for x in [origin - reach, origin + reach] {
            var lit = context
            lit.clip(to: Path(CGRect(x: x - 36, y: rect.minY - BraidGeometry.headroom, width: 72, height: rect.height + BraidGeometry.headroom)))
            for edge in geometry.topEdges(strand: strand, lens: lens) {
                lit.stroke(edge, with: .color(.white.opacity(0.9 * fade)), lineWidth: 2.5)
            }
        }
    }

    /// The host's own line stays on the page; inside an open lens it fades,
    /// so the lifted strands read in front of it.
    private func drawHost(in context: inout GraphicsContext, lens: LensState, lensRect: CGRect) {
        var segments: [Int: [CGPoint]] = [:]
        for point in host {
            segments[point.segment, default: []].append(CGPoint(x: geometry.plot.x(point.time), y: geometry.plot.y(point.value)))
        }
        var line = Path()
        for points in segments.values where !points.isEmpty {
            line.move(to: points[0])
            line.addLines(points)
        }
        let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        guard lens.spread > 0 else {
            context.stroke(line, with: .color(.blue), style: style)
            return
        }
        var outside = context
        // The outer rectangle must hold the whole lens, or the even-odd hole
        // leaks where the lens reaches past the plot's edge.
        var mask = Path(geometry.plot.rect.insetBy(dx: -geometry.plot.rect.width, dy: -BraidGeometry.headroom))
        mask.addRect(lensRect)
        outside.clip(to: mask, style: FillStyle(eoFill: true))
        outside.stroke(line, with: .color(.blue), style: style)
        var inside = context
        inside.clip(to: Path(lensRect))
        inside.stroke(line, with: .color(.blue.opacity(1 - 0.65 * min(lens.spread, 1))), style: style)
    }

    private static let hatchSpacing: CGFloat = 5

    /// "Unattributed" is hatched, never a colour an app could own.
    private func hatch(_ path: Path, in context: inout GraphicsContext) {
        var hatched = context
        hatched.clip(to: path)
        let bounds = path.boundingRect
        var lines = Path()
        var x = bounds.minX - bounds.height
        while x < bounds.maxX {
            lines.move(to: CGPoint(x: x, y: bounds.maxY))
            lines.addLine(to: CGPoint(x: x + bounds.height, y: bounds.minY))
            x += Self.hatchSpacing
        }
        hatched.stroke(lines, with: .color(.secondary.opacity(0.22)), lineWidth: 0.75)
    }
}

/// What the open lens says: the interval, the host's share, each strand.
/// Rows follow the stack from the top, so leader lines never cross.
struct BraidCard: View {
    static let width: CGFloat = 248
    static let headerHeight: CGFloat = 46
    static let rowHeight: CGFloat = 26

    let braid: CPUBraid
    let column: BraidColumn
    let palette: BraidPalette
    let bundles: [String: String?]
    /// The apps folded into "other apps", read only when shown.
    let others: () -> [Contributor]
    let focused: Int?
    let scopedApp: String?
    /// A replay has no live process list to say who has exited.
    let showsExits: Bool
    let scope: (String) -> Void
    let focus: (Int?) -> Void
    @State private var othersShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(BraidText.interval(column))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(BraidText.host(column))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(height: Self.headerHeight, alignment: .leading)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine)
            .accessibilitySortPriority(Double(braid.strands.count + 1))

            ForEach(Array(braid.strands.indices.reversed()), id: \.self) { index in
                row(index)
            }

            if othersShown, case let members = others(), !members.isEmpty {
                Text(BraidText.members(members))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                if !column.reconciles {
                    Text(BraidText.disagreement(column))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(BraidText.hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: Self.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        // The whole card takes the click, so nothing under it folds or catches.
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "CPU at the inspected moment"))
    }

    @ViewBuilder private func row(_ index: Int) -> some View {
        let strand = braid.strands[index]
        let share = column.shares[index]
        let content = HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.identity[index])
                .frame(width: 4, height: 18)
            BraidIcon(strand: strand, bundle: strand.appName.flatMap { bundles[$0] ?? nil })
            VStack(alignment: .leading, spacing: 0) {
                Text(BraidText.name(strand))
                    .font(.system(size: 13, weight: index == focused ? .semibold : .regular))
                    .lineLimit(1)
                if let note = BraidText.note(strand, running: showsExits ? bundles : nil) {
                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(share.map { MetricText.percent($0) } ?? String(localized: "unknown"))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: Self.rowHeight)
        // Each row is shaded by its share, as the process table shades its cells.
        .background(alignment: .leading) {
            GeometryReader { row in
                palette.identity[index].opacity(0.16)
                    .frame(width: row.size.width * CGFloat(min(max((share ?? 0) / MetricText.percentScale, 0), 1)))
            }
        }
        .background(index == focused ? Color.primary.opacity(0.07) : .clear)
        .contentShape(Rectangle())
        .onHover { inside in focus(inside ? index : nil) }

        switch strand.kind {
        case .app(let name):
            Button { scope(name) } label: { content }
                .buttonStyle(.plain)
                .help(name == scopedApp ? String(localized: "\(name) is the scope") : String(localized: "Scope the window to \(name)"))
                .accessibilityLabel(BraidText.spoken(strand, share: share))
                .accessibilityHint(String(localized: "Scopes the window to this app"))
                .accessibilitySortPriority(Double(braid.strands.count - index))
        case .otherApps:
            Button { othersShown.toggle() } label: { content }
                .buttonStyle(.plain)
                .help(String(localized: "Show the apps folded in here"))
                .accessibilityLabel(BraidText.spoken(strand, share: share))
                .accessibilitySortPriority(Double(braid.strands.count - index))
        case .unattributed:
            content
                .help(BraidText.unattributedHelp)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(BraidText.spoken(strand, share: share))
                .accessibilitySortPriority(Double(braid.strands.count - index))
        }
    }
}

/// An app's icon, a monogram without a bundle, or a glyph for the folded strands.
private struct BraidIcon: View {
    private static let side: CGFloat = 20
    let strand: BraidStrand
    let bundle: String?

    var body: some View {
        Group {
            switch strand.kind {
            case .app(let name):
                if let bundle {
                    Image(nsImage: AppIcons.icon(bundle)).resizable()
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: Self.side, height: Self.side)
                        .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                }
            case .otherApps:
                Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
            case .unattributed:
                Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }
}

/// Leader lines from the card's rows to their strands, and the grip where
/// the hand holds the braid.
struct BraidLeaders: View {
    /// The card can reach below the lane; its leaders must reach it there.
    static let roomBelow: CGFloat = 320
    let geometry: BraidGeometry
    let palette: BraidPalette
    let inspection: BraidInspection
    /// The card's top-left corner and which side of the lens it sits on.
    let cardOrigin: CGPoint
    let cardOnRight: Bool

    var body: some View {
        TimelineView(.animation(paused: inspection.motion == nil)) { timeline in
            let spread = inspection.spread(at: timeline.date)
            // Chart coordinates, with room above for lifted strands and below for the card.
            Canvas { context, _ in
                context.translateBy(x: 0, y: BraidGeometry.headroom)
                guard let time = inspection.time else { return }
                let center = geometry.plot.x(time)
                let lens = LensState(center: center, spread: spread)
                guard let bands = geometry.bands(atX: center, lens: lens) else { return }
                let opacity = min(max((spread - 0.15) / 0.35, 0), 1)
                let baseline = geometry.plot.rect.maxY
                let rowX = cardOnRight ? cardOrigin.x : cardOrigin.x + BraidCard.width

                for (index, band) in bands.enumerated() {
                    let row = bands.count - 1 - index
                    let rowY = cardOrigin.y + BraidCard.headerHeight + (CGFloat(row) + 0.5) * BraidCard.rowHeight
                    let strandY = baseline - CGFloat((band.lower + band.upper) / 2)
                    var path = Path()
                    path.move(to: CGPoint(x: center, y: strandY))
                    path.addLine(to: CGPoint(x: rowX, y: rowY))
                    let width: CGFloat = index == inspection.focused ? 1.25 : 0.75
                    context.stroke(path, with: .color(palette.identity[index].opacity(opacity)), lineWidth: width)
                    context.fill(
                        Path(ellipseIn: CGRect(x: center - 2, y: strandY - 2, width: 4, height: 4)),
                        with: .color(palette.identity[index].opacity(opacity))
                    )
                }

                // The grip: where the hand holds the braid, on its top strand.
                if let top = bands.last {
                    let grip = CGRect(x: center - 4.5, y: baseline - CGFloat(top.upper) - 4.5, width: 9, height: 9)
                    var shadowed = context
                    shadowed.addFilter(.shadow(color: .black.opacity(0.3), radius: 2, y: 1))
                    shadowed.fill(Path(ellipseIn: grip), with: .color(.white))
                    context.stroke(Path(ellipseIn: grip), with: .color(.black.opacity(0.25)), lineWidth: 0.5)
                }
            }
            .padding(.top, -BraidGeometry.headroom)
            .padding(.bottom, -BraidLeaders.roomBelow)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum BraidText {
    static let hint = String(localized: "Click an app to scope · Esc closes")
    static let unattributedHelp = String(localized: "Host CPU minus every observed app: other users' processes, the kernel and processes too short to sample. An estimate of what the apps leave unexplained.")

    static func interval(_ column: BraidColumn) -> String {
        let start = column.start.formatted(date: .omitted, time: .standard)
        let end = column.end.formatted(date: .omitted, time: .standard)
        let seconds = column.end.timeIntervalSince(column.start).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(start)–\(end) · \(seconds) s average")
    }

    static func host(_ column: BraidColumn) -> String {
        guard let host = column.hostMean else { return String(localized: "CPU: host reading missing") }
        return String(localized: "CPU \(MetricText.percent(host)) of the machine")
    }

    static func disagreement(_ column: BraidColumn) -> String {
        let apps = column.appsShare
        return String(localized: "Apps add up to \(MetricText.percent(apps)), more than the host's \(MetricText.percent(column.hostMean)): their samples disagree.")
    }

    static func name(_ strand: BraidStrand) -> String {
        switch strand.kind {
        case .app(let name): name
        case .otherApps(let count): String(localized: "Other apps (\(count))")
        case .unattributed: String(localized: "Unattributed")
        }
    }

    /// Exited apps keep their recorded strand and say so.
    static func note(_ strand: BraidStrand, running: [String: String?]?) -> String? {
        switch strand.kind {
        case .app(let name): running.map { $0[name] == nil } == true ? String(localized: "exited · recorded") : nil
        case .otherApps: nil
        case .unattributed: String(localized: "host minus observed apps")
        }
    }

    /// The apps folded into "other apps", eight at most and how many more.
    static func members(_ members: [Contributor]) -> String {
        let shown = members.prefix(Self.shownMembers).map { member in
            "\(member.name) \(MetricText.percent(member.value))" + (member.isEstimate ? " " + String(localized: "est.") : "")
        }
        let rest = members.count - shown.count
        let more = rest > 0 ? [String(localized: "and \(rest) more")] : []
        return (shown + more).joined(separator: " · ")
    }

    private static let shownMembers = 8

    static func spoken(_ strand: BraidStrand, share: Double?) -> String {
        let value = share.map { MetricText.percent($0) } ?? String(localized: "unknown")
        return String(localized: "\(name(strand)), \(value) of the machine")
    }

    /// Read once when the lens opens: the moment and its three biggest strands.
    static func announcement(_ braid: CPUBraid, _ column: BraidColumn) -> String {
        let ranked = braid.strands.indices
            .compactMap { index in column.shares[index].map { (strand: braid.strands[index], share: $0) } }
            .sorted { $0.share > $1.share }
            .prefix(3)
            .map { spoken($0.strand, share: $0.share) }
        return interval(column) + ". " + host(column) + ". " + ranked.joined(separator: "; ")
    }
}

/// How a pulled lane answers ChartInteraction, which classifies each press
/// first so a range drag and a pull never mix. Locations are in the
/// chart's coordinates.
struct PlotPull {
    let began: (CGPoint) -> Void
    /// The location and the vertical travel since the press.
    let changed: (CGPoint, CGFloat) -> Void
    let ended: () -> Void
    let cancelled: () -> Void
    let clicked: (CGPoint) -> Void
    let hovered: (CGPoint?) -> Void
}

/// The open lens's card and leader lines, beside the moment it reads.
struct BraidOverlay: View {
    /// Space between the lens's edge and the card.
    private static let cardGap: CGFloat = 16

    let geometry: BraidGeometry
    let palette: BraidPalette
    let inspection: BraidInspection
    let model: DashboardModel
    let scope: (String) -> Void

    var body: some View {
        if let time = inspection.time, let column = geometry.braid.column(at: time) {
            let placement = place(time)
            ZStack(alignment: .topLeading) {
                BraidLeaders(
                    geometry: geometry, palette: palette, inspection: inspection,
                    cardOrigin: placement.origin, cardOnRight: placement.onRight
                )
                BraidCard(
                    braid: geometry.braid, column: column, palette: palette, bundles: model.sampledApps,
                    others: { model.braidOtherApps(at: time, excluding: Set(geometry.braid.strands.compactMap(\.appName))) },
                    focused: inspection.focused, scopedApp: model.scopedApp, showsExits: model.openRecording == nil, scope: scope,
                    focus: { inspection.setFocus($0) }
                )
                .offset(x: placement.origin.x, y: placement.origin.y)
                .opacity(inspection.phase == .folding ? 0 : 1)
                .animation(.easeOut(duration: 0.12), value: inspection.phase)
            }
        }
    }

    /// Right of the lens unless that leaves the plot, then left; rows
    /// centred on the stack where it is opened.
    private func place(_ time: Date) -> (origin: CGPoint, onRight: Bool) {
        let rect = geometry.plot.rect
        let center = geometry.plot.x(time)
        let half = LensState(center: center, spread: 1).halfWidth(width: rect.width)
        let rows = CGFloat(geometry.braid.strands.count)
        let height = BraidCard.headerHeight + rows * BraidCard.rowHeight
        let right = center + half + Self.cardGap
        let onRight = right + BraidCard.width <= rect.maxX
        let x = onRight ? right : max(rect.minX, center - half - Self.cardGap - BraidCard.width)
        let y = max(rect.minY - BraidGeometry.headroom, rect.midY - height / 2)
        return (CGPoint(x: x, y: y), onRight)
    }
}

/// What the CPU lane derives from a braid, kept until the braid, the plot
/// or the appearance changes: the chart closures rerun on every cursor move.
@MainActor
final class BraidCache {
    private var geometryKey: (braid: UUID, rect: CGRect, window: ClosedRange<Date>)?
    private var geometry: BraidGeometry?
    private var paletteKey: (braid: UUID, bundles: [String: String?], dark: Bool)?
    private var palette: BraidPalette?

    func geometry(_ braid: CPUBraid, rect: CGRect, window: ClosedRange<Date>) -> BraidGeometry {
        if let geometry, let key = geometryKey, key.braid == braid.id, key.rect == rect, key.window == window {
            return geometry
        }
        let built = BraidGeometry(plot: BraidPlot(rect: rect, window: window, maximum: MetricText.percentScale), braid: braid)
        geometry = built
        geometryKey = (braid.id, rect, window)
        return built
    }

    func palette(_ braid: CPUBraid, bundles: [String: String?], dark: Bool) -> BraidPalette {
        // Bundles too: an app's icon can resolve after its strand exists.
        if let palette, let key = paletteKey, key.braid == braid.id, key.bundles == bundles, key.dark == dark {
            return palette
        }
        let built = BraidPalette(braid: braid, bundles: bundles, dark: dark)
        palette = built
        paletteKey = (braid.id, bundles, dark)
        return built
    }
}

/// One key press, as plain values: the event itself must not leave the
/// monitor's callback.
struct BraidKeyPress: Sendable {
    enum Key: Sendable { case left, right, up, down, returnKey, escape, toggle }

    let key: Key
    let option: Bool
    let isRepeat: Bool
    let windowNumber: Int

    private static let codes: [UInt16: Key] = [123: .left, 124: .right, 125: .down, 126: .up, 36: .returnKey, 76: .returnKey, 53: .escape]
    private static let toggleCharacter = "u"

    /// Nil for anything the braid does not answer, including Command and
    /// Control combinations, which belong to menus.
    init?(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isDisjoint(with: [.command, .control]) else { return nil }
        if let key = Self.codes[event.keyCode] {
            self.key = key
        } else if event.charactersIgnoringModifiers?.lowercased() == Self.toggleCharacter, !flags.contains(.option) {
            key = .toggle
        } else {
            return nil
        }
        option = flags.contains(.option)
        isRepeat = event.isARepeat
        windowNumber = event.windowNumber
    }
}

/// The CPU braid's keys, read from the dashboard window's key events.
/// Making the chart focusable instead, or giving it an AppKit view to find
/// its window, had AppKit recalculate the window's key-view loop on every
/// update, which kept the whole window and toolbar laying out. A monitor
/// needs neither. Typing in a field always wins.
@MainActor
final class BraidKeys {
    /// SwiftUI names a scene's window after its id (see CoreographyApp).
    private static let dashboardID = "dashboard"
    private var monitor: Any?
    private var handler: ((BraidKeyPress) -> Bool)?

    func install(_ handler: @escaping (BraidKeyPress) -> Bool) {
        self.handler = handler
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let press = BraidKeyPress(event) else { return event }
            // A local monitor runs on the main thread; a global one would not.
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, let handler = self.handler, let window = NSApp.window(withWindowNumber: press.windowNumber),
                      Self.isDashboard(window), !(window.firstResponder is NSText) else { return false }
                return handler(press)
            }
            return consumed ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        handler = nil
    }

    /// Example identifiers: "dashboard", or "dashboard-AppWindow-1".
    private static func isDashboard(_ window: NSWindow) -> Bool {
        guard let identifier = window.identifier?.rawValue else { return false }
        return identifier == dashboardID || identifier.hasPrefix(dashboardID + "-")
    }
}
