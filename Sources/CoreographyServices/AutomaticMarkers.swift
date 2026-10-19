import Foundation
import CoreographyKit

/// Markers derived from the data itself (plan: sleep and wake, power
/// source changes, thermal and memory pressure transitions, app starts and
/// exits). Rebuilt from
/// displayed frames, so a held display keeps its markers.
///
/// ```text
/// pressure:  normal normal warning warning normal
/// markers:                 ^ warning      ^ normal
/// ```
enum AutomaticMarkers {
    static func derive(
        host: [CapturedSnapshot], power: [CapturedPower], sleepEvents: [PowerEvent],
        appEvents: [AppLifecycleEvent] = [], since start: Date?
    ) -> [TimelineMarker] {
        var markers: [TimelineMarker] = []
        markers += transitions(host, time: \.stamp.wallTime, level: \.memory.pressureLevel) { "Memory pressure \(name($0))" }
        markers += transitions(host, time: \.stamp.wallTime, level: { ThermalPressureLevel(reading: $0.thermalPressure) }) {
            "Thermal pressure \(name($0))"
        }
        markers += transitions(power, time: \.stamp.wallTime, level: \.powerSource) {
            $0 == .battery ? "On battery" : "On power adapter"
        }
        let earliest = start ?? host.first?.stamp.wallTime ?? .distantFuture
        markers += sleepEvents.filter { $0.time >= earliest }.map { event in
            system(at: event.time, label: sleepLabel(event))
        }
        markers += appEvents.filter { $0.time >= earliest }.map { event in
            system(at: event.time, label: event.change == .started ? "\(event.app) started" : "\(event.app) exited")
        }
        // Rebuilt every sample: a repeated record is one marker, and ties keep one order.
        var seen: Set<UUID> = []
        return markers.filter { seen.insert($0.id).inserted }.sorted { ($0.time, $0.label) < ($1.time, $1.label) }
    }

    /// A marker where a known level differs from the previous known one;
    /// unknown samples neither start nor end a level.
    private static func transitions<Frame, Level: Equatable>(
        _ frames: [Frame], time: (Frame) -> Date, level: (Frame) -> Level?, label: (Level) -> String
    ) -> [TimelineMarker] {
        var markers: [TimelineMarker] = []
        var previous: Level?
        for frame in frames {
            guard let current = level(frame) else { continue }
            if let previous, previous != current { markers.append(system(at: time(frame), label: label(current))) }
            previous = current
        }
        return markers
    }

    private static func sleepLabel(_ event: PowerEvent) -> String {
        switch event.kind {
        case .sleep: "Sleep"
        case .darkWake: "Dark wake"
        case .wake: event.reason.map { "Wake: \($0)" } ?? "Wake"
        }
    }

    private static func name(_ level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: "normal"
        case .warning: "warning"
        case .critical: "critical"
        }
    }

    private static func name(_ level: ThermalPressureLevel) -> String {
        switch level {
        case .nominal: "nominal"
        case .moderate: "moderate"
        case .heavy: "heavy"
        case .trapping: "trapping"
        case .sleeping: "sleeping"
        }
    }

    /// Rebuilt every sample, so the id follows the event: the chart keeps
    /// its marks instead of replacing them each second. It holds within one
    /// launch only (Hasher reseeds per process), which suits derived markers.
    private static func system(at time: Date, label: String) -> TimelineMarker {
        var hasher = Hasher()
        hasher.combine(time)
        hasher.combine(label)
        let hash = UInt64(bitPattern: Int64(hasher.finalize()))
        let seconds = time.timeIntervalSince1970.bitPattern
        let id = withUnsafeBytes(of: (hash.bigEndian, seconds.bigEndian)) { UUID(uuid: $0.load(as: uuid_t.self)) }
        return TimelineMarker(id: id, time: time, label: label, kind: .system)
    }
}
