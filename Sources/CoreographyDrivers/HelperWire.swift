import Foundation

/// The privileged helper's whole vocabulary (plan: a deliberately tiny XPC
/// interface). A request is a typed value; nothing in it names a command,
/// a path or an argument list, so the helper has nothing to execute.
///
/// ```text
/// app ──HelperRequest (JSON)──> XPC, each side checks the other's signature ──> helper (root)
///     <──HelperReply (JSON)───
/// ```
/// A message on the wire; larger ones are refused before they are decoded.
public protocol HelperMessage: Codable, Sendable {
    static var maximumBytes: Int { get }
}

public enum HelperRequest: HelperMessage, Equatable {
    public static let maximumBytes = 64 * 1024

    /// Asks for the helper's protocol version, so an outdated helper is noticed.
    case hello
    /// Counters of processes the app may not read itself, such as other
    /// users'. Only numbers come back: no names, paths or arguments.
    case processCounters(pids: [Int32])
    /// Open file paths of exactly these processes; a reused PID reads nothing.
    case openFiles(processes: [HelperProcessIdentity])
    /// TCP and UDP sockets of exactly these processes.
    case sockets(processes: [HelperProcessIdentity])
    /// A signal to exactly this process, after the app's own attempt was
    /// refused and the person confirmed it.
    case signal(process: HelperProcessIdentity, signal: HelperSignal)
    /// A new nice value for exactly this process, -20 to 20.
    case renice(process: HelperProcessIdentity, niceValue: Int32)
    /// A spindump of exactly this process for a bounded number of seconds.
    /// The helper picks the tool, the arguments and the report path itself.
    case spindump(process: HelperProcessIdentity, seconds: Int32)
}

/// The signals the helper sends, named by intent: nothing else can be asked for.
public enum HelperSignal: String, Codable, Sendable {
    case terminate, kill, suspend, resume, hangUp, interrupt, user1, user2, info
}

/// Why the helper's action did not happen.
public enum HelperActionFailure: String, Codable, Error, Sendable {
    case exited, identityChanged, notPermitted, invalidTarget, failed
}

/// A process as the app saw it: the start time tells a reused PID apart.
public struct HelperProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64

    public init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) {
        self.pid = pid
        self.startSeconds = startSeconds
        self.startMicroseconds = startMicroseconds
    }
}

public struct HelperProcessFiles: Codable, Equatable, Sendable {
    public let process: HelperProcessIdentity
    public let files: RawProcessFiles

    public init(process: HelperProcessIdentity, files: RawProcessFiles) {
        self.process = process
        self.files = files
    }
}

public struct HelperProcessSockets: Codable, Equatable, Sendable {
    public let process: HelperProcessIdentity
    public let sockets: RawProcessSockets

    public init(process: HelperProcessIdentity, sockets: RawProcessSockets) {
        self.process = process
        self.sockets = sockets
    }
}

public enum HelperReply: HelperMessage, Equatable {
    /// Room for every process's counters, or a descriptor batch of long paths.
    public static let maximumBytes = 8 * 1024 * 1024

    case hello(protocolVersion: Int)
    /// One entry per process the helper could read; exited ones are left out.
    case processCounters([IdentifiedProcessCounters])
    /// One entry per process read; exited, reused or unreadable ones are left out.
    case openFiles([HelperProcessFiles])
    case sockets([HelperProcessSockets])
    case actionDone
    case actionFailed(HelperActionFailure)
    /// The spindump report; one too long for the limit arrives cut and marked.
    case spindumpReport(String)
    /// Why no report could be taken.
    case spindumpFailed(String)
    /// The helper read the message but will not act on it.
    case refused(String)
}

extension HelperRequest {
    /// How long the app waits for this request's answer: a spindump keeps the
    /// helper busy for its whole sampling window plus symbolication, all under
    /// the helper's own cap, so it may wait well past the usual exchange.
    public var replyTimeout: TimeInterval {
        switch self {
        case .spindump(_, let seconds): TimeInterval(seconds) + 60
        default: 10
        }
    }
}

public enum HelperWireError: Error, Equatable, Sendable {
    case tooLarge
    case malformed
}

/// Names and limits both sides of the helper connection share.
public enum HelperWire {
    public static let machServiceName = "ch.lkmc.Coreography.helper"
    /// The launchd property list in Contents/Library/LaunchDaemons.
    public static let daemonPlistName = "ch.lkmc.Coreography.helper.plist"
    public static let appIdentifier = "ch.lkmc.Coreography"
    public static let helperIdentifier = "ch.lkmc.Coreography.helper"
    public static let protocolVersion = 5
    /// More PIDs per request are refused; a Mac rarely runs this many processes.
    public static let maximumPIDs = 4096
    /// Processes per descriptor request: each may hold hundreds of paths,
    /// so a batch stays well inside the reply limit.
    public static let maximumDescriptorProcesses = 16
    /// setpriority's range.
    public static let niceRange: ClosedRange<Int32> = -20...20
    /// The seconds a spindump request may ask for, capped because the tool
    /// samples the whole system while it runs.
    public static let spindumpSeconds: ClosedRange<Int32> = 1...30

    public static func encode(_ value: some Encodable) -> Data {
        // Encoding these plain enums cannot fail; an empty message is refused as malformed.
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    public static func decode<Value: HelperMessage>(_ type: Value.Type, from data: Data) throws(HelperWireError) -> Value {
        guard data.count <= Value.maximumBytes else { throw .tooLarge }
        guard let value = try? JSONDecoder().decode(type, from: data) else { throw .malformed }
        return value
    }

    /// The code requirement one side sets on the other: an Apple-issued
    /// certificate of the same team, and the expected identifier. Nil for
    /// a build without a team, such as an ad-hoc one: its identifier alone
    /// could be claimed by anyone, so no connection is made.
    ///
    /// Example: `anchor apple generic and identifier "ch.lkmc.Coreography"
    /// and certificate leaf[subject.OU] = "AB12CD34EF"`.
    public static func peerRequirement(identifier: String, teamID: String?) -> String? {
        // Team IDs are ten upper-case letters or digits and identifiers are
        // reverse-DNS names; nothing else may reach the requirement text.
        guard let teamID, teamID.wholeMatch(of: /[A-Z0-9]{10}/) != nil,
              identifier.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9.\-]*/) != nil else { return nil }
        return #"anchor apple generic and identifier "\#(identifier)" and certificate leaf[subject.OU] = "\#(teamID)""#
    }
}

/// The helper's side of one exchange: decode, act, encode. Every failure
/// becomes a refusal the app can show; nothing is executed on its behalf.
public struct HelperRequestHandler: Sendable {
    private let readCounters: @Sendable (Int32) -> IdentifiedProcessCounters?
    private let readFiles: @Sendable (HelperProcessIdentity) async -> RawProcessFiles?
    private let readSockets: @Sendable (HelperProcessIdentity) async -> RawProcessSockets?
    private let sendSignal: @Sendable (HelperProcessIdentity, HelperSignal) -> Result<Void, ProcessControlError>
    private let setNice: @Sendable (HelperProcessIdentity, Int32) -> Result<Void, ProcessControlError>
    private let runSpindump: @Sendable (HelperProcessIdentity, Int32) async -> Result<String, ProcessSampleError>
    /// The helper never signals itself.
    private let ownPID: Int32

    public init() {
        let files = ProcessFileDriver()
        let sockets = ProcessSocketDriver()
        let control = ProcessControlDriver()
        let spindump = ProcessSpindumpDriver()
        self.init(
            readCounters: ProcessStatisticsDriver.identifiedCounters,
            readFiles: { try? await files.files(pid: $0.pid, startSeconds: $0.startSeconds, startMicroseconds: $0.startMicroseconds).get() },
            readSockets: { try? await sockets.sockets(pid: $0.pid, startSeconds: $0.startSeconds, startMicroseconds: $0.startMicroseconds).get() },
            sendSignal: { Self.send($1, to: $0, with: control) },
            setNice: { control.renice(pid: $0.pid, startSeconds: $0.startSeconds, startMicroseconds: $0.startMicroseconds, to: $1) },
            runSpindump: { await spindump.spindump(pid: $0.pid, startSeconds: $0.startSeconds, startMicroseconds: $0.startMicroseconds, seconds: Int($1)) },
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
    }

    init(
        readCounters: @escaping @Sendable (Int32) -> IdentifiedProcessCounters? = { _ in nil },
        readFiles: @escaping @Sendable (HelperProcessIdentity) async -> RawProcessFiles? = { _ in nil },
        readSockets: @escaping @Sendable (HelperProcessIdentity) async -> RawProcessSockets? = { _ in nil },
        sendSignal: @escaping @Sendable (HelperProcessIdentity, HelperSignal) -> Result<Void, ProcessControlError> = { _, _ in .failure(.unsupportedPlatform) },
        setNice: @escaping @Sendable (HelperProcessIdentity, Int32) -> Result<Void, ProcessControlError> = { _, _ in .failure(.unsupportedPlatform) },
        runSpindump: @escaping @Sendable (HelperProcessIdentity, Int32) async -> Result<String, ProcessSampleError> = { _, _ in .failure(.unsupportedPlatform) },
        ownPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.readCounters = readCounters
        self.readFiles = readFiles
        self.readSockets = readSockets
        self.sendSignal = sendSignal
        self.setNice = setNice
        self.runSpindump = runSpindump
        self.ownPID = ownPID
    }

    private static func send(
        _ signal: HelperSignal, to process: HelperProcessIdentity, with control: ProcessControlDriver
    ) -> Result<Void, ProcessControlError> {
        let (pid, seconds, micro) = (process.pid, process.startSeconds, process.startMicroseconds)
        let intent: ProcessSignal
        switch signal {
        case .terminate: return control.terminateBySignal(pid: pid, startSeconds: seconds, startMicroseconds: micro, mode: .graceful)
        case .kill: return control.terminateBySignal(pid: pid, startSeconds: seconds, startMicroseconds: micro, mode: .forced)
        case .suspend: intent = .suspend
        case .resume: intent = .resume
        case .hangUp: intent = .hangUp
        case .interrupt: intent = .interrupt
        case .user1: intent = .user1
        case .user2: intent = .user2
        case .info: intent = .info
        }
        return control.send(intent, pid: pid, startSeconds: seconds, startMicroseconds: micro)
    }

    public func reply(to message: Data) async -> Data {
        let request: HelperRequest
        do {
            request = try HelperWire.decode(HelperRequest.self, from: message)
        } catch .tooLarge {
            return HelperWire.encode(HelperReply.refused("The request is larger than \(HelperRequest.maximumBytes) bytes."))
        } catch {
            return HelperWire.encode(HelperReply.refused("The request is not one the helper understands."))
        }

        switch request {
        case .hello:
            return HelperWire.encode(HelperReply.hello(protocolVersion: HelperWire.protocolVersion))
        case .processCounters(let pids):
            guard pids.count <= HelperWire.maximumPIDs else {
                return HelperWire.encode(HelperReply.refused("At most \(HelperWire.maximumPIDs) processes per request."))
            }
            // PID 0 is the kernel and negative values name process groups, never one process.
            guard pids.allSatisfy({ $0 > 0 }) else {
                return HelperWire.encode(HelperReply.refused("A process ID must be positive."))
            }
            return HelperWire.encode(HelperReply.processCounters(Set(pids).sorted().compactMap(readCounters)))
        case .openFiles(let processes):
            if let refusal = Self.refusal(processes) { return refusal }
            var read: [HelperProcessFiles] = []
            for process in Self.unique(processes) {
                guard let files = await readFiles(process) else { continue }
                read.append(HelperProcessFiles(process: process, files: files))
            }
            return Self.fitting(read, HelperReply.openFiles)
        case .sockets(let processes):
            if let refusal = Self.refusal(processes) { return refusal }
            var read: [HelperProcessSockets] = []
            for process in Self.unique(processes) {
                guard let sockets = await readSockets(process) else { continue }
                read.append(HelperProcessSockets(process: process, sockets: sockets))
            }
            return Self.fitting(read, HelperReply.sockets)
        case .signal(let process, let signal):
            if let refusal = actionRefusal(process) { return refusal }
            return Self.encode(sendSignal(process, signal))
        case .renice(let process, let niceValue):
            if let refusal = actionRefusal(process) { return refusal }
            guard HelperWire.niceRange.contains(niceValue) else {
                return HelperWire.encode(HelperReply.refused("A nice value must be between -20 and 20."))
            }
            return Self.encode(setNice(process, niceValue))
        case .spindump(let process, let seconds):
            guard process.pid > 0 else {
                return HelperWire.encode(HelperReply.refused("A process ID must be positive."))
            }
            guard HelperWire.spindumpSeconds.contains(seconds) else {
                return HelperWire.encode(HelperReply.refused(
                    "A spindump takes \(HelperWire.spindumpSeconds.lowerBound) to \(HelperWire.spindumpSeconds.upperBound) seconds."
                ))
            }
            switch await runSpindump(process, seconds) {
            case .success(let report): return Self.capped(report)
            case .failure(let error): return HelperWire.encode(HelperReply.spindumpFailed(Self.describe(error)))
            }
        }
    }

    /// The kernel, launchd and the helper itself are never acted on: ending
    /// launchd brings the whole Mac down. Listed in the window, they can be
    /// asked for, so this is an answer about the target, not a refusal of
    /// the request, which the app would read as an outdated helper.
    private func actionRefusal(_ process: HelperProcessIdentity) -> Data? {
        guard process.pid > Self.launchdPID, process.pid != ownPID else {
            return HelperWire.encode(HelperReply.actionFailed(.invalidTarget))
        }
        return nil
    }

    private static let launchdPID: Int32 = 1

    /// A spindump report cut until the reply fits the limit: the tool reports
    /// whole-system stacks that can run many megabytes. The head is kept —
    /// the target sorts topmost — and the cut is marked.
    private static func capped(_ report: String) -> Data {
        let note = "\n\n[The report was cut to fit the helper's reply.]"
        var text = report
        var message = HelperWire.encode(HelperReply.spindumpReport(text))
        while message.count > HelperReply.maximumBytes, text.count > note.count {
            text = String(text.prefix(text.count / 2))
            message = HelperWire.encode(HelperReply.spindumpReport(text + note))
        }
        return message
    }

    private static func describe(_ error: ProcessSampleError) -> String {
        switch error {
        case .unsupportedPlatform: "spindump needs macOS."
        case .exited: "The process exited before it could be read."
        case .failed(let detail): detail
        }
    }

    private static func encode(_ result: Result<Void, ProcessControlError>) -> Data {
        let failure: HelperActionFailure
        switch result {
        case .success: return HelperWire.encode(HelperReply.actionDone)
        case .failure(.exited): failure = .exited
        case .failure(.identityChanged): failure = .identityChanged
        case .failure(.notPermitted), .failure(.needsAdministrator): failure = .notPermitted
        case .failure(.invalidTarget): failure = .invalidTarget
        case .failure(.unsupportedPlatform), .failure(.refusedByApp), .failure(.systemCall): failure = .failed
        }
        return HelperWire.encode(HelperReply.actionFailed(failure))
    }

    private static func refusal(_ processes: [HelperProcessIdentity]) -> Data? {
        guard processes.count <= HelperWire.maximumDescriptorProcesses else {
            return HelperWire.encode(HelperReply.refused("At most \(HelperWire.maximumDescriptorProcesses) processes per request."))
        }
        guard processes.allSatisfy({ $0.pid > 0 }) else {
            return HelperWire.encode(HelperReply.refused("A process ID must be positive."))
        }
        return nil
    }

    /// The reply with as many entries as fit the reply limit: 16 processes of
    /// 512 long paths each can exceed it. Those left out stay restricted.
    private static func fitting<Entry>(_ entries: [Entry], _ reply: ([Entry]) -> HelperReply) -> Data {
        var kept = entries
        var message = HelperWire.encode(reply(kept))
        while message.count > HelperReply.maximumBytes, !kept.isEmpty {
            kept.removeLast()
            message = HelperWire.encode(reply(kept))
        }
        return message
    }

    /// In first-seen order, each process once.
    private static func unique(_ processes: [HelperProcessIdentity]) -> [HelperProcessIdentity] {
        var seen: Set<HelperProcessIdentity> = []
        return processes.filter { seen.insert($0).inserted }
    }
}
