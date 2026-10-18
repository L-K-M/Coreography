import Foundation
import Dispatch

/// One process's cumulative TCP and UDP bytes since Coreography began
/// watching, closed connections included.
public struct RawProcessTraffic: Equatable, Sendable {
    /// The kernel's unique process ID: never reused, unlike a PID.
    public let uniqueID: UInt64
    public let pid: Int32
    public let name: String
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    public init(uniqueID: UInt64, pid: Int32, name: String, receivedBytes: UInt64, sentBytes: UInt64) {
        self.uniqueID = uniqueID
        self.pid = pid
        self.name = name
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }
}

public enum TrafficDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case unavailable(String)
}

public struct RawTrafficSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let traffic: Result<[RawProcessTraffic], TrafficDriverError>
    /// Bytes of connections that closed before naming their process, or the kernel's.
    public let unattributedReceivedBytes: UInt64
    public let unattributedSentBytes: UInt64

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date, traffic: Result<[RawProcessTraffic], TrafficDriverError>,
        unattributedReceivedBytes: UInt64 = 0, unattributedSentBytes: UInt64 = 0
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.traffic = traffic
        self.unattributedReceivedBytes = unattributedReceivedBytes
        self.unattributedSentBytes = unattributedSentBytes
    }
}

public protocol ProcessTrafficSampleReading: Sendable {
    func read() async -> RawTrafficSnapshot
}

/// Per-connection counters folded into per-process totals that only grow.
///
/// ```text
/// source added ──> identity (description) ──> counts ──┐
///                                                      ├─> live totals
/// source removed ──> last counts move to retired ──────┘   per unique ID
/// ```
/// A connection's bytes survive its close, so a process's total never
/// drops when one connection ends and another starts. Retired totals of a
/// process with no open connection leave after they have been reported
/// once, so the table holds processes, not every connection ever seen.
struct TrafficLedger: Sendable {
    struct Identity: Equatable, Sendable {
        let uniqueID: UInt64
        let pid: Int32
        let name: String
    }

    private struct Source: Sendable {
        var identity: Identity?
        var received: UInt64 = 0
        var sent: UInt64 = 0
    }

    private var sources: [Int: Source] = [:]
    private var retired: [UInt64: (identity: Identity, received: UInt64, sent: UInt64)] = [:]
    private var reported: Set<UInt64> = []
    private(set) var unattributedReceived: UInt64 = 0
    private(set) var unattributedSent: UInt64 = 0

    /// A description or counts update; identity arrives with descriptions.
    mutating func update(source: Int, identity: Identity?, received: UInt64?, sent: UInt64?) {
        var entry = sources[source] ?? Source()
        if let identity { entry.identity = identity }
        if let received { entry.received = max(entry.received, received) }
        if let sent { entry.sent = max(entry.sent, sent) }
        sources[source] = entry
    }

    /// A closed connection; bytes of one that never named its process stay unattributed.
    mutating func remove(source: Int) {
        guard let entry = sources.removeValue(forKey: source) else { return }
        guard let identity = entry.identity, identity.pid > 0 else {
            unattributedReceived &+= entry.received
            unattributedSent &+= entry.sent
            return
        }
        let previous = retired[identity.uniqueID]
        retired[identity.uniqueID] = (identity, (previous?.received ?? 0) &+ entry.received, (previous?.sent ?? 0) &+ entry.sent)
    }

    /// Totals per process, then the retired totals of processes with no
    /// open connection are dropped once reported.
    mutating func totals() -> [RawProcessTraffic] {
        let live = Set(sources.values.compactMap { $0.identity.flatMap { $0.pid > 0 ? $0.uniqueID : nil } })
        for key in reported where !live.contains(key) { retired[key] = nil }

        var byProcess: [UInt64: RawProcessTraffic] = [:]
        for (key, value) in retired {
            byProcess[key] = RawProcessTraffic(
                uniqueID: key, pid: value.identity.pid, name: value.identity.name,
                receivedBytes: value.received, sentBytes: value.sent
            )
        }
        for entry in sources.values {
            guard let identity = entry.identity, identity.pid > 0 else { continue }
            let previous = byProcess[identity.uniqueID]
            byProcess[identity.uniqueID] = RawProcessTraffic(
                uniqueID: identity.uniqueID, pid: identity.pid, name: identity.name,
                receivedBytes: (previous?.receivedBytes ?? 0) &+ entry.received,
                sentBytes: (previous?.sentBytes ?? 0) &+ entry.sent
            )
        }
        reported = Set(retired.keys).subtracting(live)
        return byProcess.values.sorted { $0.uniqueID < $1.uniqueID }
    }

    var sourceCount: Int { sources.count }
}

/// Reads per-process TCP and UDP bytes through the private
/// NetworkStatistics framework (owner-approved; what nettop uses), loaded
/// at run time. One manager lives as long as the driver: creating one
/// floods it with every open socket, which takes up to a second.
public actor ProcessTrafficDriver: ProcessTrafficSampleReading {
    /// NetworkStatistics answers a query in tens of milliseconds; a silent one has failed.
    static let queryTimeout: TimeInterval = 2
    private let clockID = UUID()
    #if os(macOS)
    private var session: NetworkStatisticsSession?
    private var setupError: TrafficDriverError?
    #endif

    public init() {}

    public func read() async -> RawTrafficSnapshot {
        #if os(macOS)
        let result: Result<(traffic: [RawProcessTraffic], received: UInt64, sent: UInt64), TrafficDriverError>
        if let session = session ?? makeSession() {
            result = await session.query(timeout: Self.queryTimeout)
        } else {
            result = .failure(setupError ?? .unavailable("NetworkStatistics is not available"))
        }
        let snapshot = { (traffic: Result<[RawProcessTraffic], TrafficDriverError>, received: UInt64, sent: UInt64) in
            RawTrafficSnapshot(
                clockID: self.clockID, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds, wallTime: Date(),
                traffic: traffic, unattributedReceivedBytes: received, unattributedSentBytes: sent
            )
        }
        switch result {
        case .success(let read): return snapshot(.success(read.traffic), read.received, read.sent)
        case .failure(let error): return snapshot(.failure(error), 0, 0)
        }
        #else
        return RawTrafficSnapshot(
            clockID: clockID, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds, wallTime: Date(),
            traffic: .failure(.unsupportedPlatform)
        )
        #endif
    }

    #if os(macOS)
    private func makeSession() -> NetworkStatisticsSession? {
        if setupError != nil { return nil }
        switch NetworkStatisticsSession.make() {
        case .success(let made):
            session = made
            return made
        case .failure(let error):
            setupError = error
            return nil
        }
    }
    #endif
}

#if os(macOS)
/// The NetworkStatistics manager and the ledger its callbacks feed. Every
/// callback, and every ledger access, runs on `queue` (the framework
/// delivers callbacks on the queue it was created with).
final class NetworkStatisticsSession: @unchecked Sendable {
    fileprivate typealias ManagerCreate = @convention(c) (
        UnsafeRawPointer?, UnsafeMutableRawPointer, @convention(block) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    ) -> UnsafeMutableRawPointer?
    fileprivate typealias ManagerAction = @convention(c) (UnsafeMutableRawPointer) -> Void
    fileprivate typealias ManagerQuery = @convention(c) (UnsafeMutableRawPointer, @convention(block) () -> Void) -> Void
    fileprivate typealias SourceDictionary = @convention(c) (UnsafeMutableRawPointer, @convention(block) (CFDictionary?) -> Void) -> Void
    fileprivate typealias SourceRemoved = @convention(c) (UnsafeMutableRawPointer, @convention(block) () -> Void) -> Void

    private static let path = "/System/Library/PrivateFrameworks/NetworkStatistics.framework/NetworkStatistics"
    // Dictionary keys as the framework publishes them on macOS 26.
    private static let pidKey = "processID"
    private static let uniqueIDKey = "uniqueProcessID"
    private static let nameKey = "processName"
    private static let receivedKey = "rxBytes"
    private static let sentKey = "txBytes"

    private struct Functions {
        let create: ManagerCreate
        let addAllTCP: ManagerAction
        let addAllUDP: ManagerAction
        let destroy: ManagerAction
        let queryCounts: ManagerQuery
        let queryDescriptions: ManagerQuery
        let setDescription: SourceDictionary
        let setCounts: SourceDictionary
        let setRemoved: SourceRemoved
    }

    private let queue = DispatchQueue(label: "CoreographyDrivers.network-statistics")
    private let functions: Functions
    private var manager: UnsafeMutableRawPointer?
    private var ledger = TrafficLedger()

    private init(functions: Functions) { self.functions = functions }

    deinit { if let manager { functions.destroy(manager) } }

    static func make() -> Result<NetworkStatisticsSession, TrafficDriverError> {
        guard let functions = resolve() else {
            return .failure(.unavailable("NetworkStatistics or one of its functions is missing"))
        }
        let session = NetworkStatisticsSession(functions: functions)
        let created: UnsafeMutableRawPointer? = session.queue.sync {
            let queue = Unmanaged.passUnretained(session.queue).toOpaque()
            return functions.create(nil, queue) { [weak session] source, _ in
                guard let session, let source else { return }
                session.watch(source)
            }
        }
        guard let created else { return .failure(.unavailable("NStatManagerCreate failed")) }
        session.queue.sync {
            session.manager = created
            functions.addAllTCP(created)
            functions.addAllUDP(created)
        }
        return .success(session)
    }

    /// Ask for fresh descriptions and counts; the ledger answers once both arrive.
    func query(timeout: TimeInterval) async -> Result<(traffic: [RawProcessTraffic], received: UInt64, sent: UInt64), TrafficDriverError> {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let manager else { return continuation.resume(returning: .failure(.unavailable("No NetworkStatistics manager"))) }
                let state = QueryState()
                let finish: @Sendable () -> Void = { [self] in
                    state.pending -= 1
                    guard state.pending == 0, !state.finished else { return }
                    state.finished = true
                    let traffic = ledger.totals()
                    continuation.resume(returning: .success((traffic, ledger.unattributedReceived, ledger.unattributedSent)))
                }
                functions.queryDescriptions(manager) { finish() }
                functions.queryCounts(manager) { finish() }
                queue.asyncAfter(deadline: .now() + timeout) {
                    guard !state.finished else { return }
                    state.finished = true
                    continuation.resume(returning: .failure(.unavailable("NetworkStatistics did not answer within \(Int(timeout)) s")))
                }
            }
        }
    }

    /// Runs on `queue` for every socket the manager reports.
    private func watch(_ source: UnsafeMutableRawPointer) {
        let key = Int(bitPattern: source)
        functions.setDescription(source) { [weak self] dictionary in self?.record(key, dictionary, describes: true) }
        functions.setCounts(source) { [weak self] dictionary in self?.record(key, dictionary, describes: false) }
        functions.setRemoved(source) { [weak self] in self?.ledger.remove(source: key) }
    }

    private func record(_ source: Int, _ dictionary: CFDictionary?, describes: Bool) {
        guard let dictionary else { return }
        let values = dictionary as NSDictionary
        func number(_ key: String) -> NSNumber? { values[key] as? NSNumber }
        var identity: TrafficLedger.Identity?
        if describes, let pid = number(Self.pidKey)?.int32Value {
            identity = TrafficLedger.Identity(
                uniqueID: number(Self.uniqueIDKey)?.uint64Value ?? UInt64(UInt32(bitPattern: pid)),
                pid: pid, name: values[Self.nameKey] as? String ?? "PID \(pid)"
            )
        }
        ledger.update(
            source: source, identity: identity,
            received: number(Self.receivedKey)?.uint64Value, sent: number(Self.sentKey)?.uint64Value
        )
    }

    private static func resolve() -> Functions? {
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(library, name).map { unsafeBitCast($0, to: type) }
        }
        guard let create = symbol("NStatManagerCreate", as: ManagerCreate.self),
              let addAllTCP = symbol("NStatManagerAddAllTCP", as: ManagerAction.self),
              let addAllUDP = symbol("NStatManagerAddAllUDP", as: ManagerAction.self),
              let destroy = symbol("NStatManagerDestroy", as: ManagerAction.self),
              let queryCounts = symbol("NStatManagerQueryAllSources", as: ManagerQuery.self),
              let queryDescriptions = symbol("NStatManagerQueryAllSourcesDescriptions", as: ManagerQuery.self),
              let setDescription = symbol("NStatSourceSetDescriptionBlock", as: SourceDictionary.self),
              let setCounts = symbol("NStatSourceSetCountsBlock", as: SourceDictionary.self),
              let setRemoved = symbol("NStatSourceSetRemovedBlock", as: SourceRemoved.self) else { return nil }
        return Functions(
            create: create, addAllTCP: addAllTCP, addAllUDP: addAllUDP, destroy: destroy, queryCounts: queryCounts,
            queryDescriptions: queryDescriptions, setDescription: setDescription, setCounts: setCounts, setRemoved: setRemoved
        )
    }
}

/// One query's progress; touched only on the session's queue.
private final class QueryState: @unchecked Sendable {
    var pending = 2
    var finished = false
}
#endif
