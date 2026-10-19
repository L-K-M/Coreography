import Foundation
import CoreographyServices

@main
private struct Coreo {
    private static let usage = """
    Usage: coreo doctor
           coreo snapshot --once --json
           coreo processes --once --json
           coreo network --once --json
           coreo disks --once --json
           coreo gpu --once --json
           coreo power --once --json
           coreo sensors --once --json
           coreo silicon --once --json
           coreo connections --once --json
           coreo traffic --once --json
           coreo volumes --json
           coreo diagnose --json [--seconds N]
           coreo top [--json] [--count N] [--sort KEY]
           coreo holders --json (--port N | --file TEXT)
           coreo mcp --stdio [--standalone]
           coreo history --json METRIC [--minutes N]
           coreo stats --json [--minutes N]
           coreo export (--json | --csv) [--minutes N]
           coreo sleep --json [--hours N]
           coreo apps --json [--minutes N | --days N]
           coreo --version

    doctor reports source availability. snapshot waits for a CPU baseline.
    processes waits for a two-second baseline and reports collection coverage.
    network reports full-width per-interface byte rates and primary-interface coverage.
    disks reports per-storage-driver rates and collection coverage.
    gpu reports each GPU's driver-published utilization and memory in use.
    power reports battery, adapter and (on battery) system draw.
    sensors reports SMC system power, the hottest temperature and fans.
    silicon reports modeled CPU, GPU, ANE and DRAM power and each CPU tier's
    activity and frequency from IOReport over one second (Apple Silicon only).
    connections reports the TCP and UDP sockets of your own processes.
    traffic reports each process's TCP and UDP byte rates over two seconds.
    volumes reports each visible volume's size and space available for important use.
    diagnose samples for N seconds (3-60, default 5) and reports a summary with
    fact-only signals, top apps by CPU and disk, and data-source availability.
    top ranks apps and lone processes, grouped as the app groups them, after a
    two-second baseline: by cpu, or --sort memory, diskRead, diskWrite, network,
    gpu, power, cpuTime, started (newest first) or name; --count N shows up to
    N (1-50, default 10). Without --json it redraws every two seconds until
    interrupted.
    holders lists your processes with a TCP or UDP socket on a port, or with an
    open file whose path contains TEXT (~ is your home folder), and what the
    answer could not cover; other users' processes need the helper.
    history prints what the app recorded for METRIC (cpu, memoryUsed, memoryPressure,
    thermalPressure, gpuBusy, systemPower, ...) over the last N minutes (default 60).
    stats gives each recorded metric's minimum, median, 95th percentile, maximum
    and mean (not for pressure levels) over the last N minutes (default 60), and
    how many stored samples had no value.
    export prints every recorded sample over the last N minutes (default 60):
    JSON per metric, or CSV with one row per sample and an empty value for a gap.
    apps totals CPU-seconds and disk bytes per app from what the app recorded
    over the last N minutes (default 60), up to 50 apps; --days N gives
    per-app totals for each of the last N local days (up to 60).
    sleep imports the power-management log and reports sleep periods and
    sleep, wake and dark-wake records over the last N hours (1-168, default 24).
    mcp serves the read-only diagnostic tools to an MCP client over stdio
    through the running app, which asks you once to approve each client
    (turn on Settings > MCP access first); add it to the client's MCP server
    list. --standalone samples in this process instead, without history.
    Native host sampling requires macOS 26 or later.
    """

    static func main() async {
        do {
            switch Array(CommandLine.arguments.dropFirst()) {
            case [], ["--help"], ["-h"]:
                print(usage)
            case ["--version"]:
                print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                    as? String ?? "development")
            case ["doctor"]:
                let service = try DiagnosticService()
                try emit(await service.report())
            case ["snapshot", "--once", "--json"], ["snapshot", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureOnce())
            case ["processes", "--once", "--json"], ["processes", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureProcessesOnce())
            case ["network", "--once", "--json"], ["network", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureNetworkOnce())
            case ["disks", "--once", "--json"], ["disks", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureDisksOnce())
            case ["gpu", "--once", "--json"], ["gpu", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureGPUOnce())
            case ["power", "--once", "--json"], ["power", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.capturePowerOnce())
            case ["sensors", "--once", "--json"], ["sensors", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureSensorsOnce())
            case ["silicon", "--once", "--json"], ["silicon", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureSiliconOnce())
            case ["volumes", "--json"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.volumes())
            case ["traffic", "--once", "--json"], ["traffic", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureTrafficOnce())
            case ["connections", "--once", "--json"], ["connections", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureConnectionsOnce())
            case ["mcp", "--stdio"]:
                await bridgeMCP()
            case ["mcp", "--stdio", "--standalone"], ["mcp", "--standalone", "--stdio"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                await serveMCP()
            case let arguments where arguments.first == "history":
                let options = Array(arguments.dropFirst())
                guard options.first == "--json", options.count == 2 || options.count == 4 else {
                    throw CommandError.invalidArguments
                }
                var minutes = 60
                if options.count == 4 {
                    guard options[2] == "--minutes", let value = Int(options[3]) else { throw CommandError.invalidArguments }
                    minutes = value
                }
                let service = try DiagnosticService()
                try emit(await service.history(metric: options[1], minutes: minutes))
            case let arguments where arguments.first == "stats":
                let options = Array(arguments.dropFirst())
                guard options.first == "--json", options.count == 1 || options.count == 3 else {
                    throw CommandError.invalidArguments
                }
                var minutes = 60
                if options.count == 3 {
                    guard options[1] == "--minutes", let value = Int(options[2]) else { throw CommandError.invalidArguments }
                    minutes = value
                }
                let service = try DiagnosticService()
                try emit(await service.stats(minutes: minutes))
            case let arguments where arguments.first == "export":
                let options = Array(arguments.dropFirst())
                guard let format = options.first.flatMap(ExportFormat.init), options.count == 1 || options.count == 3 else {
                    throw CommandError.invalidArguments
                }
                var minutes = 60
                if options.count == 3 {
                    guard options[1] == "--minutes", let value = Int(options[2]) else { throw CommandError.invalidArguments }
                    minutes = value
                }
                let document = try await DiagnosticService().export(minutes: minutes)
                switch format {
                case .json: try emit(document)
                case .csv: FileHandle.standardOutput.write(Data(HistoryExport.csv(document).utf8))
                }
            case let arguments where arguments.first == "apps":
                let options = Array(arguments.dropFirst())
                guard options.first == "--json", options.count == 1 || options.count == 3 else {
                    throw CommandError.invalidArguments
                }
                let service = try DiagnosticService()
                if options.count == 3, options[1] == "--days" {
                    guard let days = Int(options[2]) else { throw CommandError.invalidArguments }
                    try emit(await service.storedAppDays(days: days))
                    return
                }
                var minutes = 60
                if options.count == 3 {
                    guard options[1] == "--minutes", let value = Int(options[2]) else { throw CommandError.invalidArguments }
                    minutes = value
                }
                try emit(await service.storedApps(minutes: minutes))
            case let arguments where arguments.first == "sleep":
                let options = Array(arguments.dropFirst())
                guard options.first == "--json", options.count == 1 || options.count == 3 else {
                    throw CommandError.invalidArguments
                }
                var hours = DiagnosticTools.defaultSleepHours
                if options.count == 3 {
                    guard options[1] == "--hours", let value = Int(options[2]) else { throw CommandError.invalidArguments }
                    hours = value
                }
                let service = try DiagnosticService()
                try emit(await service.sleepHistory(hours: hours))
            case let arguments where arguments.first == "top":
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let options = try options(Array(arguments.dropFirst()), values: ["--count", "--sort"], flags: ["--json"])
                let count = try options["--count"].map { value -> Int in
                    guard let count = Int(value) else { throw CommandError.invalidArguments }
                    return count
                } ?? defaultTopCount
                let sort = try options["--sort"].map { value -> ProcessSort in
                    guard let sort = ProcessSort(rawValue: value) else { throw CommandError.invalidArguments }
                    return sort
                } ?? .cpu
                let service = try DiagnosticService()
                if options["--json"] != nil {
                    try emit(await service.top(count: count, sortedBy: sort))
                    return
                }
                // A terminal redraws in place; a pipe gets one block per sample.
                let clear = isatty(STDOUT_FILENO) != 0 ? "\u{1B}[H\u{1B}[2J" : ""
                while true {
                    let report = try await service.top(count: count, sortedBy: sort)
                    FileHandle.standardOutput.write(Data((clear + TopText.table(report) + "\n").utf8))
                    try await Task.sleep(for: .seconds(2))
                }
            case let arguments where arguments.first == "holders":
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let options = try options(Array(arguments.dropFirst()), values: ["--port", "--file"], flags: ["--json"])
                guard options["--json"] != nil else { throw CommandError.invalidArguments }
                let service = try DiagnosticService()
                switch (options["--port"], options["--file"]) {
                case (let port?, nil):
                    guard let number = UInt16(port), number > 0 else { throw CommandError.invalidArguments }
                    try emit(await service.holders(ofPort: number))
                case (nil, let file?):
                    try emit(await service.holders(ofFile: file))
                default:
                    throw CommandError.invalidArguments
                }
            case let arguments where arguments.first == "diagnose":
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.diagnose(seconds: try diagnosisSeconds(Array(arguments.dropFirst()))))
            default:
                throw CommandError.invalidArguments
            }
        } catch {
            let message = "coreo: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }

    /// Pipe stdio to the running app's MCP session; the app approves the client.
    private static func bridgeMCP() async {
        let outcome = await MCPBridgeClient.run(
            input: { readLine(strippingNewline: true) },
            output: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) }
        )
        switch outcome {
        case .finished:
            return
        case .unavailable(let reason):
            // Earlier versions sampled in-process; say how to get that back.
            FileHandle.standardError.write(Data("coreo: \(reason); coreo mcp --stdio --standalone samples without the app\n".utf8))
            exit(EXIT_FAILURE)
        case .refused(let reason):
            FileHandle.standardError.write(Data("coreo: \(reason)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    /// Run the dashboard sampler in-process and answer JSON-RPC lines from stdin.
    /// Stdout carries only protocol messages; stdin closing ends the server.
    @MainActor
    private static func serveMCP() async {
        let model = DashboardModel()
        model.start()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let server = MCPServer(version: version) { await MainActor.run { model.diagnosticSnapshot() } }
        // readLine blocks, so it runs off the main actor that drives sampling.
        await Task.detached {
            while let line = readLine(strippingNewline: true) {
                guard !line.isEmpty, let response = await server.handle(line) else { continue }
                FileHandle.standardOutput.write(Data((response + "\n").utf8))
            }
        }.value
        model.stop()
    }

    private static let defaultTopCount = 10

    /// Each option at most once, in any order: `values` take the next
    /// argument, `flags` stand alone.
    /// Example: ["--json", "--count", "5"] -> ["--json": "", "--count": "5"].
    private static func options(_ arguments: [String], values: Set<String>, flags: Set<String>) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard result[key] == nil else { throw CommandError.invalidArguments }
            if flags.contains(key) {
                result[key] = ""
                index += 1
            } else if values.contains(key), index + 1 < arguments.count {
                result[key] = arguments[index + 1]
                index += 2
            } else {
                throw CommandError.invalidArguments
            }
        }
        return result
    }

    /// Accepts "--json" with an optional "--seconds N" in either order.
    private static func diagnosisSeconds(_ arguments: [String]) throws -> Int {
        let defaultSeconds = 5
        switch arguments {
        case ["--json"]: return defaultSeconds
        case let options where options.count == 3 && options.contains("--json"):
            guard let flag = options.firstIndex(of: "--seconds"), flag + 1 < options.count,
                  let seconds = Int(options[flag + 1]) else { throw CommandError.invalidArguments }
            return seconds
        default: throw CommandError.invalidArguments
        }
    }

    private static func emit<Value: Encodable>(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

/// `coreo export` output formats, by their flag.
private enum ExportFormat: String {
    case json = "--json"
    case csv = "--csv"
}

private enum CommandError: Error, CustomStringConvertible {
    case unsupportedPlatform
    case invalidArguments

    var description: String {
        switch self {
        case .unsupportedPlatform: return "native host sampling requires macOS"
        case .invalidArguments: return "invalid arguments; use --help"
        }
    }
}

/// `coreo top` as text: one line per app or lone process, then what it left out.
private enum TopText {
    private static let nameWidth = 32
    private static let cellWidth = 10
    private static let decimalUnits = ["B", "KB", "MB", "GB", "TB"]

    static func table(_ report: TopReport) -> String {
        let header = left("NAME", nameWidth) + ["CPU", "MEMORY", "READ", "WRITE", "NETWORK", "GPU ms/s"].map { right($0, cellWidth) }.joined()
        let rows = report.rows.map { row in
            let name = row.processes > 1 ? "\(row.name) (\(row.processes))" : row.name
            let network = row.networkReceivedBytesPerSecond.numericValue.flatMap { received in
                row.networkSentBytesPerSecond.numericValue.map { received + $0 }
            }
            let cells = [
                row.cpuPercentOfMachine.numericValue.map { String(format: "%.1f%%", $0) } ?? "–",
                bytes(row.memoryFootprintBytes.numericValue),
                rate(row.diskReadBytesPerSecond.numericValue), rate(row.diskWriteBytesPerSecond.numericValue),
                rate(network), row.gpuMillisecondsPerSecond.numericValue.map { String(format: "%.0f", $0) } ?? "–"
            ]
            return left(name, nameWidth) + cells.map { right($0, cellWidth) }.joined()
        }
        let footer = "\(report.rows.count) of \(report.total) apps and processes by \(report.sort.rawValue)"
            + (report.restrictedProcesses > 0 ? "; \(report.restrictedProcesses) need the helper, so totals are lower bounds" : "")
        return ([header] + rows + [footer]).joined(separator: "\n")
    }

    /// Decimal units, as Finder counts. Example: 1_234_000 -> "1.2 MB".
    private static func bytes(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "–" }
        var scaled = value
        var unit = 0
        while scaled >= 1000, unit < decimalUnits.count - 1 {
            scaled /= 1000
            unit += 1
        }
        return unit == 0 ? "\(Int(scaled)) B" : String(format: "%.1f", scaled) + " " + decimalUnits[unit]
    }

    private static func rate(_ value: Double?) -> String {
        value == nil ? "–" : bytes(value) + "/s"
    }

    /// Cut to `width` with an ellipsis, then padded.
    private static func left(_ text: String, _ width: Int) -> String {
        let fitted = text.count > width - 1 ? String(text.prefix(width - 2)) + "…" : text
        return fitted + String(repeating: " ", count: max(0, width - fitted.count))
    }

    private static func right(_ text: String, _ width: Int) -> String {
        String(repeating: " ", count: max(0, width - text.count)) + text
    }
}
