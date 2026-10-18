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
           coreo diagnose --json [--seconds N]
           coreo mcp --stdio
           coreo history --json METRIC [--minutes N]
           coreo sleep --json [--hours N]
           coreo apps --json [--minutes N]
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
    diagnose samples for N seconds (3-60, default 5) and reports a summary with
    fact-only signals, top apps by CPU and disk, and data-source availability.
    history prints what the app recorded for METRIC (cpu, memoryUsed, memoryPressure,
    thermalPressure, gpuBusy, systemPower, ...) over the last N minutes (default 60).
    apps totals CPU-seconds and disk bytes per app from what the app recorded
    over the last N minutes (default 60), up to 50 apps.
    sleep imports the power-management log and reports sleep periods and
    sleep, wake and dark-wake records over the last N hours (1-168, default 24).
    mcp serves the read-only diagnostic tools to an MCP client over stdio,
    sampling in this process; add it to the client's MCP server list.
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
            case ["connections", "--once", "--json"], ["connections", "--json", "--once"]:
                guard DiagnosticService.nativeSamplingSupport == .supported else {
                    throw CommandError.unsupportedPlatform
                }
                let service = try DiagnosticService()
                try emit(await service.captureConnectionsOnce())
            case ["mcp", "--stdio"]:
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
            case let arguments where arguments.first == "apps":
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
