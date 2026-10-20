import Foundation

/// What a tool call read, as something the window can show (plan: answers
/// link to the processes and time ranges used as evidence).
///
/// ```text
/// get_process_details {pid: 42}  -> process 42
/// get_top_processes  -> covered range, then its leading apps
/// get_metric_history -> the span of its points
/// ```
public enum AskEvidence: Hashable, Sendable {
    case process(pid: Int32)
    case app(String)
    case range(ClosedRange<Date>)

    /// Apps beyond the first few are rarely what an answer rests on.
    private static let appLimit = 3

    /// The process a PID named when the answer's snapshot was taken; a
    /// process that started later reuses the PID and is not the evidence.
    static func process(_ pid: Int32, in processes: CapturedProcesses?, askedAt: Date) -> ObservedProcess? {
        processes?.processes.first { $0.id.pid == pid && $0.id.startTime <= askedAt }
    }

    static func from(tool: String, input: [String: Any], result: String) -> [AskEvidence] {
        switch tool {
        case "get_process_details":
            guard let pid = (input["pid"] as? NSNumber).flatMap({ Int32(exactly: $0.int64Value) }) else { return [] }
            return [.process(pid: pid)]
        case "get_top_processes":
            guard let page = decode(TopApps.self, result) else { return [] }
            let covered = page.coveredStart.flatMap { start in
                page.coveredEnd.map { end in start <= end ? AskEvidence.range(start...end) : nil } ?? nil
            }
            return [covered].compactMap { $0 } + (page.rows ?? []).prefix(appLimit).map { .app($0.app) }
        case "get_metric_history":
            guard let times = decode(Points.self, result)?.points?.map(\.time),
                  let first = times.min(), let last = times.max() else { return [] }
            return [.range(first...last)]
        default:
            return []
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ text: String) -> Value? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: Data(text.utf8))
    }

    /// Only the fields evidence needs; the rest of a result is the model's.
    private struct TopApps: Decodable {
        struct Row: Decodable { let app: String }
        let rows: [Row]?
        let coveredStart: Date?
        let coveredEnd: Date?
    }

    private struct Points: Decodable {
        struct Point: Decodable { let time: Date }
        let points: [Point]?
    }
}
