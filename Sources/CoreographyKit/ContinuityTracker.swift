import Foundation

/// Classifies each sample against the previous one, so every monitor treats
/// sleep, clock changes and missed intervals the same way.
///
/// - `interrupted`: time went missing (sleep, a long stall); rates across it
///   are gaps and lines must not bridge it.
/// - `discontinuous`: wall time ran backwards or the clock session changed;
///   retained history no longer shares a timeline and must be cleared.
struct ContinuityTracker: Sendable {
    enum Outcome: Equatable, Sendable {
        case continuous
        case interrupted
        case discontinuous
    }

    private static let attosecondsPerSecond = 1_000_000_000_000_000_000.0
    let maximumGap: Duration
    private var previous: SampleStamp?

    init(maximumGap: Duration) { self.maximumGap = maximumGap }

    mutating func reset() { previous = nil }

    mutating func record(_ stamp: SampleStamp) -> Outcome {
        defer { previous = stamp }
        guard let previous else { return .continuous }

        let wallElapsed = stamp.wallTime.timeIntervalSince(previous.wallTime)
        if wallElapsed < 0 || stamp.clockID != previous.clockID { return .discontinuous }
        guard stamp.monotonicNanoseconds > previous.monotonicNanoseconds else { return .interrupted }

        let components = maximumGap.components
        let gapSeconds = Double(components.seconds) + Double(components.attoseconds) / Self.attosecondsPerSecond
        let monotonicElapsed = Duration.nanoseconds(stamp.monotonicNanoseconds - previous.monotonicNanoseconds)
        return wallElapsed > gapSeconds || monotonicElapsed > maximumGap ? .interrupted : .continuous
    }
}
