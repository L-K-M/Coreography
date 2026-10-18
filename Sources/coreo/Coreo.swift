import Foundation
import CoreographyServices

@main
private struct Coreo {
    private static let usage = """
    Usage: coreo doctor
           coreo snapshot --once --json
           coreo --version

    doctor reports source availability. snapshot waits for a CPU baseline.
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
