import Foundation
import CoreographyDrivers

public enum ProcessSigner: Equatable, Sendable {
    case apple
    /// Signed by someone else; the team identifies the developer when present.
    case developer(team: String?)
    case unsigned
    /// Missing program, unreadable signature, or off macOS.
    case unknown
}

public struct ProcessSigning: Equatable, Sendable {
    public let signer: ProcessSigner
    public let identifier: String?
}

/// What the inspector reads about one process on demand.
public struct ProcessDetail: Sendable {
    public let process: ProcessIdentity
    public let arguments: [String]?
    /// Why arguments are missing, when they are.
    public let argumentsProblem: String?
    public let signing: ProcessSigning?
    /// Threads when read; nil with a reason otherwise.
    public var threads: Int? = nil
    public var threadsProblem: String? = nil
}

/// Facts about this Mac for the inspector when nothing is selected.
public struct SystemFacts: Sendable {
    public let model: String?
    public let chip: String?
    public let osBuild: String?
    public let bootTime: Date?
    public let loadAverages: [Double]?

    public static func read() -> SystemFacts {
        let raw = SystemFactsDriver.read()
        return SystemFacts(
            model: raw.model, chip: raw.chip, osBuild: raw.osBuild, bootTime: raw.bootTime, loadAverages: raw.loadAverages
        )
    }
}

/// Reads a selected process's arguments and signature, only on selection.
public actor ProcessInspector {
    private let driver: any ProcessDetailReading

    public init() { self.init(driver: ProcessDetailDriver()) }

    init(driver: any ProcessDetailReading) { self.driver = driver }

    public func detail(of process: ProcessReading) async -> ProcessDetail {
        let read = await driver.arguments(
            pid: process.id.pid, startSeconds: process.id.startSeconds, startMicroseconds: process.id.startMicroseconds
        )
        let arguments: [String]?
        let problem: String?
        switch read {
        case .success(let values):
            (arguments, problem) = (values, nil)
        case .failure(let error):
            (arguments, problem) = (nil, Self.describe(error))
        }

        var signing: ProcessSigning?
        if let path = process.executablePath {
            let raw = await driver.signing(path: path)
            signing = ProcessSigning(signer: Self.signer(raw), identifier: raw.identifier)
        }
        var detail = ProcessDetail(process: process.id, arguments: arguments, argumentsProblem: problem, signing: signing)
        switch await driver.threads(
            pid: process.id.pid, startSeconds: process.id.startSeconds, startMicroseconds: process.id.startMicroseconds
        ) {
        case .success(let count): detail.threads = count
        case .failure(let error): detail.threadsProblem = Self.describe(error, subject: "Threads")
        }
        return detail
    }

    private static func signer(_ raw: CodeSigning) -> ProcessSigner {
        switch raw.signature {
        case .apple: .apple
        case .otherSigner: .developer(team: raw.teamID)
        case .unsigned: .unsigned
        case .unknown: .unknown
        }
    }

    /// `subject` is plural: "Arguments", "Threads".
    private static func describe(_ error: ProcessDetailError, subject: String = "Arguments") -> String {
        switch error {
        case .unsupportedPlatform: "\(subject) need macOS"
        case .exited: "The process has exited"
        case .notPermitted: "Another user's process; its \(subject.lowercased()) need the helper"
        case .malformed: "The kernel returned an unreadable argument block"
        case .systemCall(let code): "\(subject) could not be read (\(code))"
        }
    }
}
