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
           coreo --version

    doctor reports source availability. snapshot waits for a CPU baseline.
    processes waits for a two-second baseline and reports collection coverage.
    network reports full-width per-interface byte rates and primary-interface coverage.
    disks reports per-storage-driver rates and collection coverage.
    gpu reports each GPU's driver-published utilization and memory in use.
    power reports battery, adapter and (on battery) system draw.
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
            default:
                throw CommandError.invalidArguments
            }
        } catch {
            let message = "coreo: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
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
