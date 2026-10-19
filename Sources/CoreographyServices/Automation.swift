import Foundation
import CoreographyKit

/// What a `coreography://` link asks for (plan: automation). Any app or
/// web page can open a link, so links only navigate, filter and start or
/// stop a recording. Nothing signals, quits, exports or reads data back.
///
/// ```text
/// coreography://show
/// coreography://filter?q=cpu:%3E10
/// coreography://find?port=443
/// coreography://find?file=~/Downloads
/// coreography://process?pid=412
/// coreography://range?seconds=3600
/// coreography://record/start?name=Build
/// coreography://record/stop
/// coreography://hud/toggle
/// ```
public enum AutomationCommand: Equatable, Sendable {
    case show
    case filter(String)
    case selectProcess(pid: Int32)
    case range(TimeRange)
    case startRecording(name: String)
    case stopRecording
    case toggleHUD
}

public enum AutomationLinkError: Error, Equatable, Sendable {
    case wrongScheme
    case unknownCommand(String)
    case invalidArgument(String)

    public var message: String {
        switch self {
        case .wrongScheme: "Not a coreography:// link"
        case .unknownCommand(let command): "Unknown coreography:// command \"\(command)\""
        case .invalidArgument(let detail): detail
        }
    }
}

public enum AutomationLink {
    public static let scheme = "coreography"
    /// Filters and session names are short; a longer text is not one.
    static let maximumTextLength = 256

    public static func command(from url: URL) -> Result<AutomationCommand, AutomationLinkError> {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .failure(.wrongScheme) }
        let path = ([components.host ?? ""] + components.path.split(separator: "/").map(String.init))
            .filter { !$0.isEmpty }.map { $0.lowercased() }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { first, _ in first }

        do {
            switch path {
            case [], ["show"]:
                return .success(.show)
            case ["filter"]:
                return .success(.filter(try text(query["q"] ?? "", name: "q")))
            case ["find"]:
                return .success(.filter(try lookupFilter(query)))
            case ["process"]:
                guard let pid = query["pid"].flatMap({ Int32($0) }), pid >= 0 else {
                    throw AutomationLinkError.invalidArgument("process needs pid=<number>")
                }
                return .success(.selectProcess(pid: pid))
            case ["range"]:
                guard let range = query["seconds"].flatMap({ Int($0) }).flatMap(TimeRange.init(rawValue:)) else {
                    let allowed = TimeRange.allCases.map { String($0.rawValue) }.joined(separator: ", ")
                    throw AutomationLinkError.invalidArgument("range needs seconds= one of \(allowed)")
                }
                return .success(.range(range))
            case ["record", "start"]:
                return .success(.startRecording(name: try text(query["name"] ?? "", name: "name")))
            case ["record", "stop"]:
                return .success(.stopRecording)
            case ["hud", "toggle"]:
                return .success(.toggleHUD)
            default:
                return .failure(.unknownCommand(path.joined(separator: "/")))
            }
        } catch let error as AutomationLinkError {
            return .failure(error)
        } catch {
            return .failure(.invalidArgument("\(error)"))
        }
    }

    /// `port=443` or `file=~/Downloads` become the filter's reverse lookups.
    /// The filter splits terms on whitespace, so a path with a space cannot be one term.
    private static func lookupFilter(_ query: [String: String]) throws -> String {
        if let port = query["port"] {
            guard let number = UInt16(port), number > 0 else { throw AutomationLinkError.invalidArgument("port must be 1-65535") }
            return "port:\(number)"
        }
        if let file = query["file"] {
            let path = try text(file, name: "file")
            guard !path.isEmpty else { throw AutomationLinkError.invalidArgument("file must not be empty") }
            guard !path.contains(where: \.isWhitespace) else {
                throw AutomationLinkError.invalidArgument("file cannot contain spaces; use part of the name")
            }
            return "file:\(path)"
        }
        throw AutomationLinkError.invalidArgument("find needs port= or file=")
    }

    /// Short, printable text only.
    private static func text(_ value: String, name: String) throws -> String {
        guard value.count <= maximumTextLength else {
            throw AutomationLinkError.invalidArgument("\(name) is longer than \(maximumTextLength) characters")
        }
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AutomationLinkError.invalidArgument("\(name) contains control characters")
        }
        return value.trimmingCharacters(in: .whitespaces)
    }
}

/// A process holding a port or file, for Shortcuts.
public struct Holder: Codable, Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let app: String

    /// Example: "Safari Web Content (Safari, PID 412)".
    public var line: String { "\(name) (\(app), PID \(pid))" }
}

/// Who holds a port or file now, and what the answer could not cover.
public struct HolderLookup: Codable, Equatable, Sendable {
    public let holders: [Holder]
    /// Why the answer may be incomplete or empty for want of data.
    public let limitations: [String]
}

enum HolderLookups {
    static func port(_ port: UInt16, in processes: CapturedProcesses, connections: CapturedConnections) -> HolderLookup {
        let facts = SocketFacts(connections)
        let matching = processes.processes.filter { facts.ports[$0.id]?.contains(port) ?? false }
        return HolderLookup(
            holders: holders(matching, in: processes),
            limitations: limitations(
                unavailable: connections.unavailableReason, restricted: connections.restrictedProcesses,
                truncated: connections.truncatedProcesses, failed: connections.failedProcesses
            )
        )
    }

    /// The filter's `file:` rule: any open path containing the text, ignoring case.
    static func file(_ text: String, in processes: CapturedProcesses, files: CapturedOpenFiles) -> HolderLookup {
        let matching = processes.processes.filter { process in
            files.files[process.id]?.contains { $0.localizedCaseInsensitiveContains(text) } ?? false
        }
        return HolderLookup(
            holders: holders(matching, in: processes),
            limitations: limitations(
                unavailable: files.unavailableReason, restricted: files.restrictedProcesses,
                truncated: files.truncatedProcesses, failed: files.failedProcesses
            )
        )
    }

    private static func holders(_ matching: [ObservedProcess], in processes: CapturedProcesses) -> [Holder] {
        let apps = ProcessGroups.appNames(processes)
        return matching
            .map { Holder(pid: $0.id.pid, name: $0.name, app: apps[$0.id] ?? $0.name) }
            .sorted { ($0.app, $0.name, $0.pid) < ($1.app, $1.name, $1.pid) }
    }

    private static func limitations(unavailable: String?, restricted: Int, truncated: Int, failed: Int) -> [String] {
        if let unavailable { return [unavailable] }
        var notes: [String] = []
        if restricted > 0 { notes.append("\(restricted) processes of other users need the helper") }
        if truncated > 0 { notes.append("\(truncated) processes held more than one read keeps") }
        if failed > 0 { notes.append("\(failed) processes could not be read") }
        return notes
    }
}

/// Plain-text answers for Shortcuts and Spotlight.
public enum AutomationText {
    /// Example: "CPU 23% · Memory 12.4 GB used, pressure normal · GPU 8% · 14.2 W · Time Machine idle".
    public static func summary(_ summary: SystemSummary) -> String {
        var parts: [String] = []
        if let cpu = summary.cpuPercentOfMachine?.reading.numericValue { parts.append("CPU \(Int(cpu.rounded()))%") }
        if let memory = summary.memoryUsedBytes?.reading.numericValue {
            let pressure = summary.memoryPressure.map { ", pressure \($0)" } ?? ""
            parts.append("Memory \(Int64(memory).formatted(.byteCount(style: .memory))) used\(pressure)")
        }
        if let gpu = summary.gpuBusyPercent?.reading.numericValue { parts.append("GPU \(Int(gpu.rounded()))%") }
        if let watts = summary.systemPowerWatts?.reading.numericValue { parts.append("\(watts.formatted(.number.precision(.fractionLength(1)))) W") }
        if let thermal = summary.thermalPressure, thermal != "nominal" { parts.append("thermal \(thermal)") }
        if let maintenance = summary.maintenance, maintenance.timeMachine == .backingUp { parts.append("Time Machine backing up") }
        guard !parts.isEmpty else { return "No readings yet." }
        return parts.joined(separator: " · ")
    }

    /// Example: ["Safari: 182.4 CPU-seconds", "Xcode: 96.0 CPU-seconds"].
    public static func topApps(_ page: TopAppsPage) -> [String] {
        page.rows.map { row in
            let value = row.unit == "bytes"
                ? Int64(row.value).formatted(.byteCount(style: .file))
                : "\(row.value.formatted(.number.precision(.fractionLength(1)))) \(row.unit)"
            return "\(row.app): \(row.isLowerBound ? "at least " : "")\(value)"
        }
    }
}
