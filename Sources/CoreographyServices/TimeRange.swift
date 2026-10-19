import Foundation

/// Visible window lengths (plan: 1 min, 10 min and 1 h within live
/// history; 6 h from the on-disk Recent tier).
public enum TimeRange: Int, CaseIterable, Identifiable, Sendable {
    case minute = 60
    case tenMinutes = 600
    case hour = 3600
    case sixHours = 21_600

    public var id: Self { self }
    public var seconds: TimeInterval { TimeInterval(rawValue) }
    /// Longer than the live hour held in memory, so stored history fills the rest.
    public var reachesStoredHistory: Bool { seconds > TimeRange.hour.seconds }
}

/// Reduce a series for drawing without hiding spikes.
///
/// Each segment's points fall into equal time buckets; every bucket keeps
/// its minimum and maximum in time order. Nothing is averaged, so a
/// one-sample spike survives any zoom level.
///
/// ```text
/// bucket:   |  .  '  .  |  .  .  '  |
/// kept:     |  .  '     |  .     '  |   (min and max per bucket)
/// ```
public enum Decimation {
    /// About one bucket per two points of a full-width plot.
    public static let defaultBuckets = 360

    public static func extremes<Element>(
        _ elements: [Element], start: Date, end: Date, buckets: Int = defaultBuckets,
        time: (Element) -> Date, value: (Element) -> Double, segment: (Element) -> Int
    ) -> [Element] {
        let span = end.timeIntervalSince(start)
        guard buckets > 0, span > 0, elements.count > buckets * 2 else { return elements }

        var result: [Element] = []
        var index = 0
        while index < elements.count {
            // One bucket within one segment.
            let first = elements[index]
            let key = (segment(first), bucket(time(first), start: start, span: span, buckets: buckets))
            var low = index
            var high = index
            var next = index + 1
            while next < elements.count,
                  segment(elements[next]) == key.0,
                  bucket(time(elements[next]), start: start, span: span, buckets: buckets) == key.1 {
                if value(elements[next]) < value(elements[low]) { low = next }
                if value(elements[next]) > value(elements[high]) { high = next }
                next += 1
            }
            for kept in Set([low, high]).sorted() { result.append(elements[kept]) }
            index = next
        }
        return result
    }

    public static func points(_ points: [DashboardPoint], start: Date, end: Date) -> [DashboardPoint] {
        extremes(points, start: start, end: end, time: \.time, value: \.value, segment: \.segment)
    }

    /// Stacked layers decimate together: keep the frames where the stack's
    /// total is a bucket extreme, so every layer stays aligned.
    public static func stack(_ points: [MemoryStackPoint], start: Date, end: Date) -> [MemoryStackPoint] {
        guard let top = MemoryCategory.allCases.last else { return points }
        let tops = points.filter { $0.category == top }
        let kept = Set(extremes(tops, start: start, end: end, time: \.time, value: \.upper, segment: \.segment).map(\.time))
        return points.filter { kept.contains($0.time) }
    }

    private static func bucket(_ time: Date, start: Date, span: TimeInterval, buckets: Int) -> Int {
        Int((time.timeIntervalSince(start) / span * Double(buckets)).rounded(.down))
    }
}
