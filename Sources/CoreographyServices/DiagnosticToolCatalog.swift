import Foundation
import CoreFoundation

/// The six diagnostic tools as callable entries, shared by every client
/// (MCP and Ask): one schema, one dispatch, one encoding.
enum DiagnosticToolCatalog {
    enum Failure: Error, Equatable {
        case unknownTool(String)
    }

    struct Definition {
        let name: String
        let description: String
        let properties: [String: Any]
        let required: [String]

        var inputSchema: [String: Any] {
            ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
    }

    static var definitions: [Definition] {
        let snapshotID = string("Reuse a previous result's snapshot")
        let range: [String: Any] = ["type": "integer", "minimum": 1, "maximum": DiagnosticTools.maximumRangeSeconds]
        return [
            Definition(
                name: "get_system_summary",
                description: "CPU, memory pressure, swap, network, GPU, power and thermal readings with units, evidence and fact-only signals, plus Time Machine progress and whether Spotlight indexes the startup disk (not whether it is indexing now), with read time.",
                properties: ["snapshot_id": snapshotID], required: []
            ),
            Definition(
                name: "get_top_processes",
                description: "Apps ranked by CPU-seconds, disk bytes or network bytes (in and out) over a range, paged, with coverage. CPU and disk cover own-user processes only.",
                properties: [
                    "metric": ["type": "string", "enum": DiagnosticTools.ActivityMetric.allCases.map(\.rawValue)], "range_seconds": range,
                    "limit": ["type": "integer", "minimum": 1, "maximum": DiagnosticTools.maximumRows],
                    "cursor": string("nextCursor from a previous page"), "snapshot_id": snapshotID
                ], required: []
            ),
            Definition(
                name: "get_metric_history",
                description: "A bounded series for one metric; separate segments mean a gap in sampling.",
                properties: [
                    "metric": ["type": "string", "enum": DiagnosticTools.HistoryMetric.allCases.map(\.rawValue)],
                    "range_seconds": range,
                    "max_points": ["type": "integer", "minimum": 2, "maximum": DiagnosticTools.maximumPoints],
                    "snapshot_id": snapshotID
                ], required: ["metric"]
            ),
            Definition(
                name: "get_process_details",
                description: "Identity (PID and start time), app, resource readings and a curated role note for a recognised system process. A role does not establish its current job. No paths or arguments.",
                properties: ["pid": ["type": "integer"], "snapshot_id": snapshotID], required: ["pid"]
            ),
            Definition(
                name: "get_sleep_history",
                description: "Logged sleep, wake and dark-wake records with reasons and battery charge, sleep periods with battery change, and current sleep-preventing assertion types with read time, omissions and unavailable reasons. Assertion names are withheld. Reasons are evidence, not proven causes; partialCoverage names missing log coverage.",
                properties: [
                    "hours": ["type": "integer", "minimum": 1, "maximum": DiagnosticTools.maximumSleepHours],
                    "snapshot_id": snapshotID
                ], required: []
            ),
            Definition(
                name: "get_data_sources",
                description: "Which readings are measured, estimated, restricted or unavailable on this Mac, with provenance.",
                properties: ["snapshot_id": snapshotID], required: []
            )
        ]
    }

    /// Run one tool against a snapshot and return its JSON text.
    static func run(_ name: String, arguments: [String: Any], snapshot: DiagnosticSnapshot) throws -> String {
        let output: any Encodable
        switch name {
        case "get_system_summary":
            output = DiagnosticTools.summary(snapshot)
        case "get_top_processes":
            output = try DiagnosticTools.topApps(
                snapshot, metric: try enumArgument(arguments, "metric") ?? .cpu, range: try range(arguments, snapshot),
                limit: try intArgument(arguments, "limit") ?? 10, cursor: arguments["cursor"] as? String
            )
        case "get_metric_history":
            guard let metric: DiagnosticTools.HistoryMetric = try enumArgument(arguments, "metric") else {
                throw DiagnosticError.invalidArgument("metric is required")
            }
            output = try DiagnosticTools.history(
                snapshot, metric: metric, range: try range(arguments, snapshot),
                maximumPoints: try intArgument(arguments, "max_points") ?? DiagnosticTools.maximumPoints
            )
        case "get_process_details":
            guard let pid = try intArgument(arguments, "pid").flatMap({ Int32(exactly: $0) }),
                  let details = DiagnosticTools.processDetails(snapshot, pid: pid) else {
                throw DiagnosticError.invalidArgument("No observed process with that pid")
            }
            output = details
        case "get_sleep_history":
            output = try DiagnosticTools.sleepHistory(
                snapshot, hours: try intArgument(arguments, "hours") ?? DiagnosticTools.defaultSleepHours
            )
        case "get_data_sources":
            output = DiagnosticTools.dataSources(snapshot)
        default:
            throw Failure.unknownTool(name)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(output), as: UTF8.self)
    }

    static func describe(_ error: DiagnosticError) -> String {
        switch error {
        case .invalidArgument(let message): message
        case .rangeTooLarge(let maximum): "Range too large; at most \(maximum) seconds of live history"
        case .invalidCursor: "Invalid or expired cursor; restart the query without one"
        case .unavailable(let reason): reason
        }
    }

    private static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func range(_ arguments: [String: Any], _ snapshot: DiagnosticSnapshot) throws -> ClosedRange<Date>? {
        guard let seconds = try intArgument(arguments, "range_seconds") else { return nil }
        guard seconds > 0 else { throw DiagnosticError.invalidArgument("range_seconds must be positive") }
        return snapshot.takenAt.addingTimeInterval(-Double(seconds))...snapshot.takenAt
    }

    /// Integral JSON numbers only; strings and booleans are rejected.
    private static func intArgument(_ arguments: [String: Any], _ key: String) throws -> Int? {
        guard let raw = arguments[key] else { return nil }
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID(),
              let integer = Int(exactly: number.doubleValue) else {
            throw DiagnosticError.invalidArgument("\(key) must be an integer")
        }
        return integer
    }

    private static func enumArgument<Value: RawRepresentable>(
        _ arguments: [String: Any], _ key: String
    ) throws -> Value? where Value.RawValue == String {
        guard let raw = arguments[key] else { return nil }
        guard let text = raw as? String, let parsed = Value(rawValue: text) else {
            throw DiagnosticError.invalidArgument("Unsupported \(key)")
        }
        return parsed
    }
}
