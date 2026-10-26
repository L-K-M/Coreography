import Foundation

/// What a press in the CPU plot turns into once it has moved far enough
/// to tell (plan: dragging selects a range; pulling opens the braid).
public enum PlotDragIntent: Equatable, Sendable {
    /// Not far enough yet: nothing happens, so a stray click changes nothing.
    case undecided
    case range
    case comparison
    case pull
}

/// The lens that opens the CPU braid around one moment: how far the
/// strands part for a given pull, where the opening tapers off, and how a
/// fold settles. Pure geometry in points and seconds, so the view only
/// draws what this decides.
///
/// ```text
///          lens: half-width w around the pointer
///        ├──────────w──────────┼──────────w──────────┤
///  ══════╗                  ┌─────┐                  ╔══════  strand 2
///  ══════╬═══╗          ┌───┘ g·s └───┐          ╔═══╬══════  strand 1
///  ══════╩═══╩══════════════════════════════════════╩═══╩══════  strand 0
///        falloff 0 ──── smoothstep ──── 1 at the pointer
/// ```
/// Strands only translate upward by whole gaps: every band keeps its
/// measured thickness, and the bottom strand stays on the baseline.
public enum BraidLens {
    /// Horizontal travel that commits a press to range selection.
    public static let rangeIntent = 8.0
    /// Vertical travel that commits a press to pulling the braid open.
    public static let pullIntent = 12.0
    /// How much steeper than horizontal a pull must be; anything shallower
    /// stays the familiar range selection.
    public static let pullSteepness = 1.4
    /// Pull travel at which the strands are usefully apart.
    public static let fullTravel = 48.0
    /// Travel past full where the extra tension stops growing.
    public static let tensionTravel = 96.0
    /// Extra spread the tension adds at most, beyond fully open.
    public static let maximumTension = 0.25
    /// Gap between neighbouring strands when fully open.
    public static let gap = 8.0
    /// Half-width of the opening when it starts.
    public static let minimumHalfWidth = 28.0
    /// Half-width of the opening when fully open, as a share of the plot.
    public static let openHalfWidthShare = 0.22
    /// A pull released before this spread was not meant: it folds back.
    public static let latchThreshold = 0.25
    /// The pointer must cross this far into a neighbouring strand before
    /// focus moves, so a hand resting on a seam does not flicker.
    public static let focusHysteresis = 6.0
    /// Folding back closes the gaps over this long, without overshoot.
    public static let foldSeconds = 0.24
    /// Opening by click or key, or settling a released pull, takes this long.
    public static let openSeconds = 0.18
    /// The seams ring after a fold: a decoration, never data.
    public static let ringSeconds = 0.3
    private static let ringAmplitude = 1.5
    private static let ringHertz = 14.0
    private static let ringDecaySeconds = 0.09

    /// Decide once, then keep: a drag never changes its mind midway.
    /// Command-drag with a range already selected is always a comparison,
    /// and only a clearly vertical drag pulls.
    public static func intent(dx: Double, dy: Double, comparing: Bool) -> PlotDragIntent {
        let horizontal = abs(dx)
        let vertical = abs(dy)
        if comparing { return max(horizontal, vertical) >= rangeIntent ? .comparison : .undecided }
        let steep = vertical > pullSteepness * horizontal
        if steep, vertical >= pullIntent { return .pull }
        if !steep, horizontal >= rangeIntent { return .range }
        return .undecided
    }

    /// Spread for a pull's vertical travel in either direction: linear to
    /// fully open at 48 pt, then a little extra tension up to 96 pt.
    /// Example: 24 pt is 0.5; 48 pt is 1; 96 pt and beyond about 1.22.
    public static func spread(travel: Double) -> Double {
        let distance = abs(travel)
        guard distance > fullTravel else { return distance / fullTravel }
        let extra = min(distance, tensionTravel) - fullTravel
        let span = tensionTravel - fullTravel
        return 1 + maximumTension * (1 - exp(-2 * extra / span))
    }

    /// Half-width of the opening for a spread, growing to fully open.
    public static func halfWidth(spread: Double, plotWidth: Double) -> Double {
        let open = max(minimumHalfWidth, plotWidth * openHalfWidthShare)
        let progress = min(max(spread, 0), 1)
        return minimumHalfWidth + (open - minimumHalfWidth) * progress
    }

    /// How open the braid is at `x`: 1 at the lens centre, easing to 0 at
    /// its edges, 0 outside.
    public static func falloff(x: Double, center: Double, halfWidth: Double) -> Double {
        guard halfWidth > 0 else { return 0 }
        let t = 1 - min(abs(x - center) / halfWidth, 1)
        return t * t * (3 - 2 * t)
    }

    /// Upward offset of strand `index` (0 at the bottom) at `x`.
    public static func offset(index: Int, x: Double, center: Double, spread: Double, plotWidth: Double) -> Double {
        let width = halfWidth(spread: spread, plotWidth: plotWidth)
        return Double(index) * gap * max(spread, 0) * falloff(x: x, center: center, halfWidth: width)
    }

    /// Spread `elapsed` seconds into a move from `start` to `target`: an
    /// ease-out that never passes the target, so no measured boundary
    /// overshoots. The ring after a fold is where the twang lives.
    public static func settle(from start: Double, to target: Double, elapsed: Double, duration: Double) -> Double {
        guard duration > 0 else { return target }
        let t = min(max(elapsed / duration, 0), 1)
        let eased = 1 - (1 - t) * (1 - t) * (1 - t)
        return start + (target - start) * eased
    }

    /// The decorative displacement of a seam's highlight after a fold, in
    /// points; zero once the ring has died away.
    public static func ring(elapsed: Double) -> Double {
        guard elapsed >= 0, elapsed < ringSeconds else { return 0 }
        return ringAmplitude * exp(-elapsed / ringDecaySeconds) * sin(2 * .pi * ringHertz * elapsed)
    }

    /// Which strand a point in the plot falls on, given each strand's lower
    /// and upper edge there (bottom first, y growing upward). Keeps the
    /// current focus until the point is `focusHysteresis` into another.
    public static func focus(y: Double, bands: [(lower: Double, upper: Double)], current: Int?) -> Int? {
        if let current, bands.indices.contains(current) {
            let band = bands[current]
            if y >= band.lower - focusHysteresis, y <= band.upper + focusHysteresis { return current }
        }
        // Thin strands still get a usable target: the nearest band within the hysteresis.
        let distances = bands.enumerated().map { index, band -> (index: Int, distance: Double) in
            if y >= band.lower, y <= band.upper { return (index, 0) }
            return (index, min(abs(y - band.lower), abs(y - band.upper)))
        }
        guard let nearest = distances.min(by: { $0.distance < $1.distance }),
              nearest.distance <= focusHysteresis else { return nil }
        return nearest.index
    }

    /// Strand hues (0 to 1 round the wheel) from each app's icon, nudged
    /// apart so neighbours stay distinguishable: many culprits have blue
    /// icons. Red stays for bad states, so hues near it move off it. Earlier
    /// strands keep their hue; later ones step 30 degrees either way. Ten
    /// hues fit outside the red zone; the braid names six apps at most.
    /// Example: Xcode 0.58 and Safari 0.57 become 0.58 and about 0.65.
    public static func separatedHues(_ hues: [Double], minimum: Double = minimumHueGap) -> [Double] {
        var assigned: [Double] = []
        for hue in hues {
            let base = awayFromRed(wrapped(hue))
            let candidates = [0.0] + (1...hueSteps).flatMap { [Double($0) * hueStep, -Double($0) * hueStep] }
            let chosen = candidates.lazy.map { awayFromRed(wrapped(base + $0)) }.first { candidate in
                assigned.allSatisfy { circularDistance($0, candidate) >= minimum }
            }
            assigned.append(chosen ?? base)
        }
        return assigned
    }

    /// Thirty degrees: blues and teals still read as different strands.
    public static let minimumHueGap = 1.0 / 12
    private static let hueStep = 1.0 / 12
    private static let hueSteps = 6
    /// Thirty degrees either side of pure red: crimson reads as alarm too.
    private static let redZone = 1.0 / 12

    private static func wrapped(_ hue: Double) -> Double {
        let remainder = hue.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }

    private static func awayFromRed(_ hue: Double) -> Double {
        if hue < redZone { return redZone }
        if hue > 1 - redZone { return 1 - redZone }
        return hue
    }

    private static func circularDistance(_ a: Double, _ b: Double) -> Double {
        let distance = abs(a - b)
        return min(distance, 1 - distance)
    }
}
