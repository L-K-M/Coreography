import Foundation

enum CounterRateTrackerError: Error, Equatable, Sendable {
    /// The maximum gap between samples must be a positive duration.
    case nonPositiveMaxGap
}

/// Turns cumulative counter readings into per-second rates.
///
/// Rates are deltas over the *real* elapsed time between the two stamps,
/// never a nominal sampling interval. The first sample, a counter reset,
/// a clock-session change, an elapsed interval beyond `maxGap`, and a
/// non-positive elapsed interval all produce explicit non-numeric
/// readings; every gap re-baselines the tracker so the next good pair
/// yields a rate again.
struct CounterRateTracker: Sendable {
    /// Longest interval between two samples still treated as continuous.
    let maxGap: Duration
    private let source: MetricSource?
    private var lastCounter: UInt64?
    private var lastStamp: SampleStamp?

    init(maxGap: Duration, source: MetricSource? = nil) throws {
        guard maxGap > .zero else {
            throw CounterRateTrackerError.nonPositiveMaxGap
        }
        self.maxGap = maxGap
        self.source = source
    }

    /// Forget the baseline; the next `record` reports `.collecting`.
    mutating func reset() {
        lastCounter = nil
        lastStamp = nil
    }

    /// Consume one counter reading stamped on the monotonic clock.
    ///
    /// - Returns: `.measured` delta/elapsed-seconds on a clean pair,
    ///   `.collecting` before the first usable pair, `.gap` otherwise.
    mutating func record(_ counter: UInt64, at stamp: SampleStamp) -> MetricReading {
        guard let previousCounter = lastCounter, let previousStamp = lastStamp else {
            lastCounter = counter
            lastStamp = stamp
            return .collecting(source: source)
        }

        func rebase() {
            lastCounter = counter
            lastStamp = stamp
        }

        guard stamp.clockID == previousStamp.clockID else {
            rebase()
            return .gap(reason: "clock session changed", source: source)
        }
        guard stamp.monotonicNanoseconds > previousStamp.monotonicNanoseconds else {
            rebase()
            return .gap(
                reason: "non-positive elapsed time between samples",
                source: source
            )
        }

        let elapsedNanoseconds =
            stamp.monotonicNanoseconds - previousStamp.monotonicNanoseconds
        guard Duration.nanoseconds(elapsedNanoseconds) <= maxGap else {
            rebase()
            return .gap(
                reason: "missed interval: \(elapsedNanoseconds) ns exceeds "
                    + "max gap \(maxGap)",
                source: source
            )
        }
        guard counter >= previousCounter else {
            rebase()
            return .gap(
                reason: "counter reset: \(previousCounter) -> \(counter)",
                source: source
            )
        }

        rebase()
        let rate = Double(counter - previousCounter)
            / (Double(elapsedNanoseconds) / 1_000_000_000)
        guard let reading = try? MetricReading.measured(rate, source: source) else {
            return .gap(reason: "non-finite rate", source: source)
        }
        return reading
    }
}
