import AppKit
import SwiftUI
import CoreographyServices

/// The startup volume's used space as a rope of folders. Clicking it opens
/// the space lens, where the rope comes apart into its strands.
///
/// ```text
/// rest:   [Library|Apps|Home|..|////rest////|      free      ]
/// lens:    Library    ━━━━━━━━━━━━━━━━  48 GB
///          Applications ━━━━━━━━━       31 GB
///          macOS and the rest ////      22 GB
/// ```
struct SpaceRope: View {
    static let height: CGFloat = 8
    /// Red is for bad states only; this matches the startup-disk alert's 10 % free.
    static let nearlyFull = 0.9
    let volume: CapturedVolume
    let space: SpaceSurveyor
    /// The volume's kind, path and purgeable note, as the plain bars say it.
    let detail: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var lensShown = false
    @State private var hovered = false
    @State private var feedback = InteractionFeedback()

    var body: some View {
        let braid = space.braid(for: volume)
        let palette = SpacePalette(braid: braid, measured: !space.sizes.isEmpty, full: volume.usedFraction > Self.nearlyFull,
                                   dark: colorScheme == .dark)
        Button { lensShown.toggle() } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(volume.name) · \(MetricText.bytes(Double(volume.availableBytes))) free")
                    .font(.caption)
                    .lineLimit(1)
                SpaceRopeShape(braid: braid, palette: palette, lifted: hovered || lensShown)
                    .frame(height: Self.height)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovered = inside }
        }
        .help(String(localized: "\(detail). Click to see what takes up the space."))
        .accessibilityLabel(SpaceText.volumeSummary(volume))
        .accessibilityHint(String(localized: "Shows what takes up the space"))
        .popover(isPresented: $lensShown, arrowEdge: .trailing) {
            SpaceLens(volume: volume, space: space, feedback: feedback)
        }
    }
}

/// The rope itself: one stretch per strand, seams between them, the
/// unexplained rest hatched and free space as the bare track.
struct SpaceRopeShape: View {
    private static let hatchSpacing: CGFloat = 4
    let braid: SpaceBraid
    let palette: SpacePalette
    /// Hover and an open lens raise the rope's fibres with a highlight.
    let lifted: Bool

    var body: some View {
        Canvas { context, size in
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            context.fill(track, with: .color(.secondary.opacity(0.14)))
            context.clip(to: track)

            for (index, span) in braid.spans.enumerated() where !span.isEmpty {
                let rect = CGRect(x: span.lowerBound * size.width, y: 0, width: (span.upperBound - span.lowerBound) * size.width,
                                  height: size.height)
                let stretch = Path(rect)
                context.fill(stretch, with: .color(palette.rest[index]))
                if palette.hatched[index] { hatch(stretch, in: &context) }
                if lifted {
                    let shine = Path(CGRect(x: rect.minX, y: 0, width: rect.width, height: size.height * 0.35))
                    context.fill(shine, with: .color(.white.opacity(0.22)))
                }
                guard index > 0 else { continue }
                var seam = Path()
                seam.move(to: CGPoint(x: rect.minX, y: 0))
                seam.addLine(to: CGPoint(x: rect.minX, y: size.height))
                context.stroke(seam, with: .color(.white.opacity(0.55)), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }

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
        hatched.stroke(lines, with: .color(.secondary.opacity(0.3)), lineWidth: 0.75)
    }
}

/// Rope colours at rest (shades of one hue by size) and each area's own
/// colour, revealed as the lens opens.
struct SpacePalette {
    let rest: [Color]
    let identity: [Color]
    let hatched: [Bool]

    private static let restOpacities: [Double] = [0.66, 0.56, 0.48, 0.41, 0.35, 0.3, 0.26]
    private static let identitySaturation = 0.5
    /// Each area's starting hue (0 to 1 round the wheel), nudged apart in strand order.
    private static let seedHues: [CapturedSpaceArea: Double] = [
        .applications: 0.6, .library: 0.72, .otherHome: 0.5, .documents: 0.14, .downloads: 0.33, .desktop: 0.45,
        .pictures: 0.1, .movies: 0.82, .music: 0.88, .appData: 0.25, .cloud: 0.55
    ]

    /// Before anything is measured the rope is one plain stretch, as the
    /// volume bar always was; a nearly full volume is red.
    init(braid: SpaceBraid, measured: Bool, full: Bool, dark: Bool) {
        let base: Color = full ? .red : .blue
        let areas = braid.strands.map { strand -> Double in
            guard case .area(let area) = strand.kind else { return 0.6 }
            return Self.seedHues[area] ?? 0.6
        }
        let hues = BraidLens.separatedHues(areas)
        let brightness = dark ? 0.86 : 0.72
        var rest: [Color] = []
        var identity: [Color] = []
        var hatched: [Bool] = []
        for (index, strand) in braid.strands.enumerated() {
            switch strand.kind {
            case .area:
                rest.append(base.opacity(Self.restOpacities[min(index, Self.restOpacities.count - 1)]))
                identity.append(Color(hue: hues[index], saturation: Self.identitySaturation, brightness: brightness))
                hatched.append(false)
            case .rest where measured:
                rest.append(Color.secondary.opacity(0.16))
                identity.append(Color.secondary.opacity(0.3))
                hatched.append(true)
            case .rest:
                rest.append(base.opacity(Self.restOpacities[0]))
                identity.append(base.opacity(Self.restOpacities[0]))
                hatched.append(false)
            }
        }
        self.rest = rest
        self.identity = identity
        self.hatched = hatched
    }
}

/// The opened rope: each strand drops from its place in the rope into a
/// row that names it, sizes it and shows it in Finder.
private struct SpaceLens: View {
    private static let width: CGFloat = 330
    private static let rowHeight: CGFloat = 38
    private static let inset: CGFloat = 14
    private static let barHeight: CGFloat = 3
    private static let unbraidSeconds = 0.32
    private static let stagger = 0.03

    let volume: CapturedVolume
    let space: SpaceSurveyor
    let feedback: InteractionFeedback
    @Environment(\.colorScheme) private var colorScheme
    @State private var unbraided = false
    /// Kept by strand, not position: rows re-sort as areas finish measuring.
    @State private var focused: SpaceStrand.Kind?
    @FocusState private var keyboardFocus: Bool
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var barWidth: CGFloat { Self.width - 2 * Self.inset }

    var body: some View {
        let braid = space.braid(for: volume)
        let palette = SpacePalette(braid: braid, measured: !space.sizes.isEmpty, full: false, dark: colorScheme == .dark)
        let spans = braid.spans
        VStack(alignment: .leading, spacing: 0) {
            header(braid)
            SpaceRopeShape(braid: braid, palette: palette, lifted: true)
                .frame(height: SpaceRope.height + 2)
                .padding(.horizontal, Self.inset)
                .padding(.bottom, 8)

            ForEach(Array(braid.strands.enumerated()), id: \.element.id) { index, strand in
                row(strand, index: index, span: spans[index], palette: palette)
            }

            if !braid.unmeasured.isEmpty { unmeasuredRow(braid.unmeasured) }
            footer(braid)
        }
        .frame(width: Self.width, alignment: .leading)
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocus)
        .onKeyPress(.downArrow) { step(1, in: braid.strands) }
        .onKeyPress(.upArrow) { step(-1, in: braid.strands) }
        .onKeyPress(.return) {
            guard let strand = braid.strands.first(where: { $0.kind == focused }), case .area = strand.kind else { return .ignored }
            reveal(strand)
            return .handled
        }
        .onAppear {
            keyboardFocus = true
            space.refreshIfStale()
            feedback.play(.open)
            withAnimation(reduceMotion ? nil : Animation.easeOut(duration: Self.unbraidSeconds)) { unbraided = true }
        }
        .onDisappear { feedback.play(.fold) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "What takes up space on \(volume.name)"))
    }

    private func header(_ braid: SpaceBraid) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(volume.name).font(.caption).foregroundStyle(.secondary)
            Text(SpaceText.used(volume))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
            HStack(spacing: 6) {
                if space.isMeasuring { ProgressView().controlSize(.mini) }
                Text(SpaceText.status(measuring: braid.measuring, measuredAt: space.measuredAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func row(_ strand: SpaceStrand, index: Int, span: Range<Double>, palette: SpacePalette) -> some View {
        // Before unbraiding, the bar sits where its stretch sits in the rope above.
        let ropeOffset = CGFloat(span.lowerBound) * barWidth
        let ropeWidth = CGFloat(span.upperBound - span.lowerBound) * barWidth
        let rowWidth = CGFloat(min(max(strand.share ?? 0, 0), 1)) * barWidth
        let rise = CGFloat(index + 1) * Self.rowHeight
        let content = HStack(spacing: 8) {
            SpaceIcon(strand: strand)
            VStack(alignment: .leading, spacing: 1) {
                Text(SpaceText.name(strand.kind))
                    .font(.system(size: 13, weight: strand.kind == focused ? .semibold : .regular))
                    .lineLimit(1)
                if let detail = SpaceText.detail(strand) {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(SpaceText.size(strand))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, Self.inset)
        .frame(height: Self.rowHeight)
        .opacity(unbraided ? 1 : 0)
        .background(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Self.barHeight / 2)
                .fill(unbraided ? palette.identity[index] : palette.rest[index])
                .frame(width: max(unbraided ? rowWidth : ropeWidth, Self.barHeight), height: Self.barHeight)
                .offset(x: Self.inset + (unbraided ? 0 : ropeOffset), y: unbraided ? -4 : -rise)
        }
        .background(strand.kind == focused ? Color.primary.opacity(0.07) : .clear)
        .animation(reduceMotion ? nil : Animation.easeOut(duration: Self.unbraidSeconds).delay(Double(index) * Self.stagger), value: unbraided)
        .contentShape(Rectangle())
        .onHover { inside in focused = inside ? strand.kind : (focused == strand.kind ? nil : focused) }

        switch strand.kind {
        case .area:
            Button { reveal(strand) } label: { content }
                .buttonStyle(.plain)
                .help(String(localized: "Show \(SpaceText.name(strand.kind)) in Finder"))
                .accessibilityLabel(SpaceText.spoken(strand))
                .accessibilityHint(String(localized: "Shows it in Finder"))
        case .rest:
            content
                .help(SpaceText.restHelp)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SpaceText.spoken(strand))
        }
    }

    private func unmeasuredRow(_ areas: [CapturedSpaceArea]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .frame(width: SpaceIcon.side, height: SpaceIcon.side)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(areas.map { SpaceText.name(.area($0)) }.formatted(.list(type: .and)))
                    .font(.system(size: 12))
                    .lineLimit(2)
                Text(String(localized: "Not measured. macOS may ask before each."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(String(localized: "Measure")) { space.measure(.askingMacOS) }
                .controlSize(.small)
                .help(String(localized: "Measure these too; macOS may ask for access before each"))
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func footer(_ braid: SpaceBraid) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !braid.refused.isEmpty {
                Text(SpaceText.refused(braid.refused))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !braid.reconciles {
                Text(SpaceText.overrun)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Text(String(localized: "Click a folder to show it in Finder"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(String(localized: "Measure Again")) { space.measure() }
                    .controlSize(.small)
                    .disabled(space.isMeasuring)
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 10)
    }

    private func step(_ delta: Int, in strands: [SpaceStrand]) -> KeyPress.Result {
        guard !strands.isEmpty else { return .ignored }
        let current = strands.firstIndex { $0.kind == focused }
        let next = current.map { $0 + delta } ?? (delta > 0 ? 0 : strands.count - 1)
        focused = strands[min(max(next, 0), strands.count - 1)].kind
        return .handled
    }

    private func reveal(_ strand: SpaceStrand) {
        guard case .area(let area) = strand.kind, let path = strand.size?.path else { return }
        feedback.play(.scope(app: area.rawValue))
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// Finder's own icon for the area's folder; a drive for the rest.
private struct SpaceIcon: View {
    static let side: CGFloat = 20
    let strand: SpaceStrand

    var body: some View {
        Group {
            if let path = strand.size?.path {
                Image(nsImage: AppIcons.icon(path)).resizable()
            } else {
                Image(systemName: "internaldrive").foregroundStyle(.secondary)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }
}

enum SpaceText {
    private static let shownItems = 2
    static let restHelp = String(localized: "Used space no folder above explains: macOS itself, other users, swap, local snapshots and folders not measured.")
    static let overrun = String(localized: "The folders add up to more than the used space: APFS clones and shared files count once per copy.")

    static func refused(_ areas: [CapturedSpaceArea]) -> String {
        let names = areas.map { name(.area($0)) }.formatted(.list(type: .and))
        return String(localized: "macOS did not allow reading \(names). Privacy & Security in System Settings can allow it.")
    }

    static func name(_ kind: SpaceStrand.Kind) -> String {
        switch kind {
        case .rest: String(localized: "macOS and the rest")
        case .area(let area):
            switch area {
            case .applications: String(localized: "Applications")
            case .desktop: String(localized: "Desktop")
            case .documents: String(localized: "Documents")
            case .downloads: String(localized: "Downloads")
            case .movies: String(localized: "Movies")
            case .music: String(localized: "Music")
            case .pictures: String(localized: "Pictures")
            case .library: String(localized: "Library")
            case .appData: String(localized: "App data")
            case .cloud: String(localized: "Cloud drives")
            case .otherHome: String(localized: "Rest of home")
            }
        }
    }

    /// The biggest items inside, then why the size is only "at least".
    static func detail(_ strand: SpaceStrand) -> String? {
        guard let size = strand.size else {
            return strand.isUpperBound ? String(localized: "at most; not everything was measured") : nil
        }
        var parts = size.largest.prefix(shownItems).map { "\($0.name) \(MetricText.bytes(Double($0.bytes)))" }
        switch size.completeness {
        case .complete: break
        case .unreadable: parts.append(String(localized: "some items macOS keeps private"))
        case .timedOut: parts.append(String(localized: "still counting when time ran out"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func size(_ strand: SpaceStrand) -> String {
        guard let bytes = strand.bytes else { return "–" }
        let text = MetricText.bytes(Double(bytes))
        if strand.isLowerBound { return String(localized: "≥ \(text)") }
        if strand.isUpperBound { return String(localized: "≤ \(text)") }
        return text
    }

    static func used(_ volume: CapturedVolume) -> String {
        let used = MetricText.bytes(Double(volume.totalBytes - volume.availableBytes))
        let total = MetricText.bytes(Double(volume.totalBytes))
        return String(localized: "\(used) used of \(total)")
    }

    static func status(measuring: CapturedSpaceArea?, measuredAt: Date?) -> String {
        if let measuring { return String(localized: "Measuring \(name(.area(measuring)))…") }
        guard let measuredAt else { return String(localized: "Not measured yet") }
        return String(localized: "Measured \(measuredAt.formatted(.relative(presentation: .named)))")
    }

    static func volumeSummary(_ volume: CapturedVolume) -> String {
        String(localized: "\(volume.name), \(MetricText.bytes(Double(volume.availableBytes))) free, \(used(volume))")
    }

    static func spoken(_ strand: SpaceStrand) -> String {
        let share = strand.share.map { MetricText.percent($0 * MetricText.percentScale) } ?? String(localized: "unknown")
        return String(localized: "\(name(strand.kind)), \(size(strand)), \(share) of used space")
    }
}
