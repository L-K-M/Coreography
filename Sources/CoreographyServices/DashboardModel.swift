import Foundation
import Observation
import CoreographyKit

public enum DashboardMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case networkReceived
    case networkSent
    case diskRead
    case diskWritten

    public var id: Self { self }
}

/// Where an Ask Coreography question stands.
public enum AskState: Sendable {
    case idle
    case asking
    case answered(AskAnswer)
    case failed(String)
}

public enum DashboardDisplayMode: Equatable, Sendable {
    case live
    case held
}

public struct DashboardPoint: Identifiable, Sendable {
    public let id: UUID
    public let time: Date
    public let value: Double
    public let segment: Int
}

/// Memory lane layers, bottom to top; app, wired and compressed sum to used.
public enum MemoryCategory: String, CaseIterable, Identifiable, Sendable {
    case app
    case wired
    case compressed
    case cached

    public var id: Self { self }
}

/// One stacked layer at one sample: the layer spans `lower...upper` bytes.
public struct MemoryStackPoint: Identifiable, Sendable {
    public let id: String
    public let time: Date
    public let category: MemoryCategory
    public let lower: Double
    public let upper: Double
    public let segment: Int

    public var value: Double { upper - lower }
}

/// Pressure between two consecutive samples, labelled with the later reading.
public struct MemoryPressureSpan: Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let level: MemoryPressureLevel
}

/// Thermal pressure between two consecutive samples, labelled with the later reading.
public struct ThermalPressureSpan: Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let level: ThermalPressureLevel
}

/// Time on external power between two consecutive samples.
public struct ExternalPowerSpan: Identifiable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
}

public struct GPUTableReading: Identifiable, Sendable {
    public let id: String
    public let time: Date
    public let name: String
    public let device: CapturedGPUDevice
}

/// One GPU's utilization history; missing samples split segments.
public struct GPUSeries: Identifiable, Sendable {
    public let id: GPUDeviceID
    public let name: String
    public let points: [DashboardPoint]
}

@MainActor
@Observable
public final class DashboardModel {
    public private(set) var frames: [CapturedSnapshot] = []
    public private(set) var displayMode: DashboardDisplayMode = .live
    public private(set) var collectionError: String?
    public private(set) var processSnapshot: CapturedProcesses?
    public private(set) var networkFrames: [CapturedNetwork] = []
    public var networkScope: NetworkScope = .primary
    public private(set) var diskFrames: [CapturedDisks] = []
    public var storageScope: StorageScope = .automatic
    public private(set) var gpuFrames: [CapturedGPU] = []
    public private(set) var powerFrames: [CapturedPower] = []
    public private(set) var sensorFrames: [CapturedSensors] = []
    public var processFilter = ""
    public var processSort: ProcessSort = .cpu
    public var processGrouping: ProcessGrouping = .app
    /// The shared hover time across all lanes; nil follows the live edge.
    public var cursorTime: Date?
    public var timeRange: TimeRange = .minute {
        didSet { refreshStoredHistory() }
    }
    /// A dragged time range; cleared only explicitly (plan: Esc or clear).
    public var selection: ClosedRange<Date>?
    /// The range while a drag is in progress; reports wait for the drag to end.
    public var draftSelection: ClosedRange<Date>?
    public private(set) var markers: [TimelineMarker] = []
    /// One app scoping every view (plan P8); cleared only by its clear button.
    public var scopedApp: String?
    public private(set) var actionMessage: String?
    public private(set) var askState: AskState = .idle
    /// Why history is not being recorded, when it is not.
    public private(set) var historyProblem: String?
    public var recordsHistory: Bool { historyRecorder != nil }
    /// Why the stored part of a long range is missing, when it is.
    public private(set) var storedHistoryProblem: String?
    /// Rules currently raised, by id; lanes tint while their rule is active.
    public private(set) var activeAlerts: [AlertLane: String] = [:]
    public private(set) var hasProviderKey = false
    public private(set) var contributorHistory: [ContributorSnapshot] = []

    @ObservationIgnored private let monitor: SystemMonitor?
    @ObservationIgnored private let controller: ProcessController
    @ObservationIgnored private let askService: AskService
    @ObservationIgnored private let notifier: AlertDelivery?
    @ObservationIgnored private let historyRecorder: HistoryRecorder?
    @ObservationIgnored private let sleepProvider: SleepHistoryProvider?
    /// The on-disk part of a range longer than live history; nil otherwise.
    private var storedHistory: StoredHistory?
    @ObservationIgnored private var storedLoad: Task<Void, Never>?
    @ObservationIgnored private var storedLoadedAt: Date?
    @ObservationIgnored private var sleepState: SleepHistoryState = .notImported
    @ObservationIgnored private var sleepImport: Task<Void, Never>?
    @ObservationIgnored private var alertEngine = AlertEngine(rules: AlertRules.shipped)
    @ObservationIgnored private var alertCooldown = AlertCooldown()
    @ObservationIgnored private var askTask: Task<Void, Never>?
    @ObservationIgnored private let processMonitor: ProcessMonitor?
    @ObservationIgnored private let networkMonitor: NetworkMonitor?
    @ObservationIgnored private let diskMonitor: DiskMonitor?
    @ObservationIgnored private let gpuMonitor: GPUMonitor?
    @ObservationIgnored private let powerMonitor: PowerMonitor?
    @ObservationIgnored private let sensorMonitor: SensorMonitor?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let processInterval: Duration
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var liveFrames: [CapturedSnapshot] = []
    @ObservationIgnored private var liveProcesses: CapturedProcesses?
    @ObservationIgnored private var liveContributorHistory: [ContributorSnapshot] = []
    @ObservationIgnored private var liveLedger = AppLedger(capacity: contributorCapacity)
    @ObservationIgnored private var liveLifecycle = ProcessLifecycle()
    private var lifecycle = ProcessLifecycle()
    private var ledger = AppLedger(capacity: contributorCapacity)
    @ObservationIgnored private var liveNetworkFrames: [CapturedNetwork] = []
    @ObservationIgnored private var liveDiskFrames: [CapturedDisks] = []
    @ObservationIgnored private var liveGPUFrames: [CapturedGPU] = []
    @ObservationIgnored private var livePowerFrames: [CapturedPower] = []
    @ObservationIgnored private var liveSensorFrames: [CapturedSensors] = []

    /// - Parameter notifier: system notifications for actionable alerts; nil
    ///   (as in command-line hosts) keeps alerts to tints and markers.
    ///   History is recorded only when the app supplies a recorder.
    public init(notifier: AlertDelivery? = nil, history: (recorder: HistoryRecorder?, error: String?) = (nil, nil)) {
        controller = ProcessController()
        askService = AskService()
        self.notifier = notifier
        historyRecorder = history.recorder
        historyProblem = history.error
        sleepProvider = SleepHistoryProvider()
        interval = .seconds(1)
        processInterval = .seconds(2)
        do {
            let system = try SystemMonitor()
            let processes = try ProcessMonitor()
            let network = try NetworkMonitor()
            let disk = try DiskMonitor()
            let gpu = try GPUMonitor()
            let power = try PowerMonitor()
            let sensors = try SensorMonitor()
            monitor = system
            processMonitor = processes
            networkMonitor = network
            diskMonitor = disk
            gpuMonitor = gpu
            powerMonitor = power
            sensorMonitor = sensors
        } catch {
            monitor = nil
            processMonitor = nil
            networkMonitor = nil
            diskMonitor = nil
            gpuMonitor = nil
            powerMonitor = nil
            sensorMonitor = nil
            collectionError = "Cannot initialize monitoring: \(error)"
        }
    }

    init(
        monitor: SystemMonitor, interval: Duration,
        processMonitor: ProcessMonitor? = nil, processInterval: Duration = .seconds(2),
        networkMonitor: NetworkMonitor? = nil, diskMonitor: DiskMonitor? = nil,
        gpuMonitor: GPUMonitor? = nil, powerMonitor: PowerMonitor? = nil,
        sensorMonitor: SensorMonitor? = nil, controller: ProcessController = ProcessController(),
        askService: AskService = AskService(), notifier: AlertDelivery? = nil,
        historyRecorder: HistoryRecorder? = nil, sleepProvider: SleepHistoryProvider? = nil
    ) {
        self.controller = controller
        self.askService = askService
        self.notifier = notifier
        self.historyRecorder = historyRecorder
        self.sleepProvider = sleepProvider
        self.monitor = monitor
        self.interval = interval
        self.processMonitor = processMonitor
        self.processInterval = processInterval
        self.networkMonitor = networkMonitor
        self.diskMonitor = diskMonitor
        self.gpuMonitor = gpuMonitor
        self.powerMonitor = powerMonitor
        self.sensorMonitor = sensorMonitor
    }

    deinit {
        worker?.cancel()
        askTask?.cancel()
        sleepImport?.cancel()
        storedLoad?.cancel()
    }

    public var latest: CapturedSnapshot? { frames.last }

    // A cursor reads the nearest sample within these windows, or nothing.
    private static let cursorTolerance: TimeInterval = 1.5
    private static let contributorTolerance: TimeInterval = 2.5
    private static let wakeSettleDelay: Duration = .seconds(10)
    /// The recorder flushes every 30 s; rereading the store more often finds nothing new.
    private static let storedReloadInterval: TimeInterval = 60
    /// One hour of two-second process samples, matching live history.
    private static let contributorCapacity = 1800

    /// Host frame at the cursor, or the latest frame without one.
    public var displayedFrame: CapturedSnapshot? { atCursor(frames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedGPUFrame: CapturedGPU? { atCursor(gpuFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedPowerFrame: CapturedPower? { atCursor(powerFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedSensorFrame: CapturedSensors? {
        atCursor(sensorFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime }
    }

    /// System draw from one qualified source (plan): an SMC rail where the
    /// Mac publishes one, otherwise battery discharge while unplugged.
    public var displayedSystemPower: DashboardReading? {
        if let rail = displayedSensorFrame?.systemPowerWatts, rail.numericValue != nil { return rail }
        return displayedPowerFrame?.systemPowerWatts ?? displayedSensorFrame?.systemPowerWatts
    }
    public var displayedContributors: ContributorSnapshot? {
        atCursor(contributorHistory, tolerance: Self.contributorTolerance) { $0.time }
    }

    private func atCursor<Frame>(
        _ frames: [Frame], tolerance: TimeInterval, time: (Frame) -> Date
    ) -> Frame? {
        guard let cursorTime else { return frames.last }
        let nearest = frames.min {
            abs(time($0).timeIntervalSince(cursorTime)) < abs(time($1).timeIntervalSince(cursorTime))
        }
        guard let nearest, abs(time(nearest).timeIntervalSince(cursorTime)) <= tolerance else { return nil }
        return nearest
    }

    public var displayedEndTime: Date? {
        [
            latest?.stamp.wallTime, networkFrames.last?.stamp.wallTime,
            diskFrames.last?.stamp.wallTime, gpuFrames.last?.stamp.wallTime,
            powerFrames.last?.stamp.wallTime, sensorFrames.last?.stamp.wallTime
        ].compactMap { $0 }.max()
    }

    public var networkReadings: [NetworkTableReading] {
        networkFrames.suffix(10).map { frame in
            let interface = networkInterface(in: frame)
            return NetworkTableReading(
                id: frame.id, time: interface?.stamp.wallTime ?? frame.stamp.wallTime,
                interfaceName: interface?.id.name,
                received: networkReading(for: .networkReceived, in: frame),
                sent: networkReading(for: .networkSent, in: frame)
            )
        }
    }

    public var diskReadings: [DiskTableReading] {
        diskFrames.suffix(10).map { frame in
            let device = storageDevice(in: frame)
            return DiskTableReading(
                id: frame.id, time: device?.stamp.wallTime ?? frame.stamp.wallTime, deviceName: device?.name,
                status: device == nil ? storageSelectionMessage(in: frame) : nil,
                read: device?.readBytesPerSecond, written: device?.writtenBytesPerSecond
            )
        }
    }

    public var gpuReadings: [GPUTableReading] {
        gpuFrames.suffix(10).flatMap { frame in
            frame.devices.map {
                GPUTableReading(
                    id: "\(frame.id)-\($0.id.registryEntryID)", time: frame.stamp.wallTime,
                    name: $0.name, device: $0
                )
            }
        }
    }

    public var storageSelectionMessage: String {
        guard let frame = diskFrames.last else { return "Collecting storage devices…" }
        return storageSelectionMessage(in: frame)
    }

    private func storageSelectionMessage(in frame: CapturedDisks) -> String {
        if let reason = frame.enumeration.reason { return reason }
        if let device = storageDevice(in: frame) {
            return device.readBytesPerSecond.reason ?? "IOKit · storage-driver byte counters"
        }
        if frame.devices.isEmpty { return "No selectable storage device was observed" }
        if case .automatic = storageScope { return "Choose a storage device" }
        return "Selected storage device is not observed"
    }

    /// Totals for the selected range, from displayed (possibly held) data.
    public var rangeReport: RangeReport? {
        guard let selection else { return nil }
        return RangeReport.make(
            range: selection, ledger: ledger, frames: frames, gpuFrames: gpuFrames, sensorFrames: sensorFrames
        )
    }

    /// The selected range as an export document of displayed (possibly held) data.
    public var rangeExport: RangeExport.Document? {
        guard let selection else { return nil }
        let frames = DashboardFrames(
            host: frames, network: networkFrames, disks: diskFrames,
            gpu: gpuFrames, power: powerFrames, sensors: sensorFrames
        )
        let apps = ledger.totals(in: selection).apps.sorted { $0.cpuSeconds > $1.cpuSeconds }
        return RangeExport.document(range: selection, model: frames, apps: apps)
    }

    /// Hand the newest live readings to the recorder, which batches writes.
    private func recordHistory() {
        guard let historyRecorder else { return }
        let samples = HistorySamples.latest(
            host: liveFrames.last, network: liveNetworkFrames.last, disks: liveDiskFrames.last,
            gpu: liveGPUFrames.last, power: livePowerFrames.last, sensors: liveSensorFrames.last
        )
        let now = Date()
        Task { [weak self] in
            await historyRecorder.record(samples, at: now)
            let problem = await historyRecorder.lastError
            self?.historyProblem = problem
        }
    }

    /// Load the stored part of a long range, or drop it for a short one. A
    /// held display keeps the prefix it has; a failed read retries at the
    /// reload interval rather than every sample.
    private func refreshStoredHistory(now: Date = Date()) {
        guard timeRange.reachesStoredHistory, let historyRecorder else {
            storedLoad?.cancel()
            storedLoad = nil
            storedLoadedAt = nil
            storedHistory = nil
            storedHistoryProblem = timeRange.reachesStoredHistory
                ? (historyProblem ?? "History is not being recorded.") : nil
            return
        }
        guard storedLoad == nil else { return }
        if let storedLoadedAt {
            if displayMode == .held && storedHistory != nil { return }
            if now.timeIntervalSince(storedLoadedAt) < Self.storedReloadInterval { return }
        }

        storedLoadedAt = now
        let start = now.addingTimeInterval(-timeRange.seconds)
        storedLoad = Task { [weak self] in
            let result: Result<StoredHistory, any Error>
            do {
                result = .success(try await StoredHistory.load(from: historyRecorder, start: start, end: now))
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            self.storedLoad = nil
            switch result {
            case .success(let loaded):
                self.storedHistory = loaded
                self.storedHistoryProblem = nil
            case .failure(HistoryStoreError.storage(let reason)):
                self.storedHistoryProblem = "Stored history could not be read: \(reason)"
            case .failure(let error):
                self.storedHistoryProblem = "Stored history could not be read: \(error)"
            }
        }
    }

    /// Stored points older than live history, then the live points renumbered
    /// so no line bridges the seam. Without a stored prefix, live is unchanged.
    private func prefixed(_ live: [DashboardPoint], stored: [DashboardPoint]?, liveStart: Date?) -> [DashboardPoint] {
        guard let stored, !stored.isEmpty else { return live }
        let older = stored.filter { $0.time < liveStart ?? .distantFuture }
        let offset = (older.last?.segment ?? -1) + 1
        return older + live.map { DashboardPoint(id: $0.id, time: $0.time, value: $0.value, segment: $0.segment + offset) }
    }

    /// One-click deletion of everything recorded on disk.
    public func deleteHistory() async -> String? {
        guard let historyRecorder else { return "History is not being recorded." }
        do {
            try await historyRecorder.deleteAll()
            return nil
        } catch HistoryStoreError.storage(let reason) {
            return reason
        } catch {
            return "\(error)"
        }
    }

    /// Rules read live data, so a held display never delays an alert.
    private func evaluateAlerts() {
        let host = liveFrames.last
        let power = livePowerFrames.last
        let inputs = AlertInputs(
            memoryPressure: host?.memory.pressureLevel,
            thermalPressure: host.flatMap { ThermalPressureLevel(reading: $0.thermalPressure) },
            batteryPercent: power?.batteryChargePercent.numericValue,
            onBattery: power?.powerSource.map { $0 == .battery }
        )
        let now = host?.stamp.wallTime ?? Date()
        for event in alertEngine.evaluate(inputs, at: now) {
            guard let rule = alertEngine.rules.first(where: { $0.id == event.ruleID }) else { continue }
            switch event.kind {
            case .raised:
                activeAlerts[rule.lane] = rule.title
                markers.append(TimelineMarker(id: UUID(), time: event.time, label: rule.title))
                guard rule.notifies, let notifier, alertCooldown.admit(rule.id, at: event.time) else { continue }
                Task { await notifier.deliver(ruleID: rule.id, title: rule.title, body: "Open Coreography to see what is using it.") }
            case .cleared:
                activeAlerts[rule.lane] = nil
            }
        }
    }

    /// Freeze the displayed data for one diagnostic question.
    public func diagnosticSnapshot() -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            takenAt: displayedEndTime ?? Date(), host: frames, network: networkFrames, gpu: gpuFrames,
            power: powerFrames, sensors: sensorFrames, processes: processSnapshot, ledger: ledger,
            sleep: sleepState
        )
    }

    /// Import sleep history once at start and again after each wake, when
    /// new records exist; never on the sampling path, never twice at once.
    private func importSleepHistory(after delay: Duration) {
        guard let sleepProvider, sleepImport == nil else { return }
        sleepImport = Task { [weak self] in
            try? await Task.sleep(for: delay)
            let state: SleepHistoryState
            do {
                state = .imported(try await sleepProvider.load())
            } catch SleepHistoryError.unavailable(let reason) {
                state = .failed(reason)
            } catch {
                state = .failed("\(error)")
            }
            guard let self else { return }
            self.sleepState = state
            self.sleepImport = nil
        }
    }

    public func refreshProviderKey() async {
        hasProviderKey = await askService.hasKey()
    }

    /// Store a provider key in the Keychain; returns a message when it fails.
    public func saveProviderKey(_ key: String) async -> String? {
        let failure: String?
        do {
            try await askService.saveKey(key)
            failure = nil
        } catch let error as AskError {
            failure = error.message
        } catch {
            failure = "\(error)"
        }
        await refreshProviderKey()
        return failure
    }

    public func removeProviderKey() async -> String? {
        let failure: String?
        do {
            try await askService.removeKey()
            failure = nil
        } catch let error as AskError {
            failure = error.message
        } catch {
            failure = "\(error)"
        }
        await refreshProviderKey()
        return failure
    }

    /// Ask about the displayed data; the question is anchored to one snapshot.
    public func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        askTask?.cancel()
        askState = .asking
        let snapshot = diagnosticSnapshot()
        let service = askService
        askTask = Task { [weak self] in
            let state: AskState
            do {
                state = .answered(try await service.ask(trimmed, snapshot: snapshot))
            } catch is CancellationError {
                return
            } catch let error as AskError {
                state = .failed(error.message)
            } catch {
                state = .failed("The question failed: \(error.localizedDescription)")
            }
            guard !Task.isCancelled else { return }
            self?.askState = state
        }
    }

    /// Stop waiting for an answer; monitoring is unaffected either way.
    public func cancelAsk() {
        askTask?.cancel()
        askTask = nil
        askState = .idle
    }

    /// What quitting this process would do, for confirmation before sending.
    public func actionRequest(for process: ObservedProcess, mode: QuitMode) -> ProcessActionRequest {
        ProcessActions.request(for: process, mode: mode, in: processSnapshot)
    }

    /// Send a confirmed request; the identity is re-checked at the last moment.
    public func perform(_ request: ProcessActionRequest) {
        switch controller.terminate(request.target, mode: request.mode) {
        case .requested:
            let verb = request.mode == .forced ? "Force quit" : "Quit"
            markers.append(TimelineMarker(id: UUID(), time: Date(), label: "\(verb) \(request.name)"))
            actionMessage = "\(verb) requested for \(request.name) (PID \(request.target.pid))"
        case .failed(let reason):
            actionMessage = "\(request.name): \(reason)"
        }
    }

    /// Coreography's own process cost, from the latest process sample.
    public var selfCost: SelfCost? {
        SelfCost.measure(in: processSnapshot, logicalCPUCount: latest?.inventory.logicalCPUCount)
    }

    public var visibleProcessRows: [ProcessRow] {
        let time = processSnapshot?.stamp.wallTime ?? Date()
        let lifecycle = lifecycle
        let rows = ProcessGroups.rows(
            in: processSnapshot, matching: processFilter, sortedBy: processSort, grouping: processGrouping,
            isNew: { lifecycle.isNew($0, at: time) }
        )
        guard let scopedApp else { return rows }
        return rows.filter { $0.appName == scopedApp }
    }

    /// Filter terms that were not applied, named for the person who typed them.
    public var processFilterIssues: [String] { ProcessFilter.parse(processFilter).issues }

    /// Processes gone within the last 30 s, newest first, matching filter and scope.
    public var exitedProcesses: [ExitedProcess] {
        let query = processFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        return lifecycle.exited
            .filter { scopedApp == nil || $0.appName == scopedApp }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.identity.pid).contains(query) }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    /// True for a process first seen within the last 10 s (not at launch).
    public func isNewProcess(_ identity: ProcessIdentity) -> Bool {
        lifecycle.isNew(identity, at: processSnapshot?.stamp.wallTime ?? Date())
    }

    /// The scoped app's CPU share and disk rate from the ledger, for lane overlays.
    public func scopedSeries() -> (cpu: [DashboardPoint], disk: [DashboardPoint])? {
        guard let scopedApp else { return nil }
        return ledger.series(for: scopedApp)
    }

    public func start() {
        guard worker == nil, let monitor else { return }
        let run = UUID()
        generation = run
        collectionError = nil
        let processMonitor = processMonitor
        let processInterval = processInterval
        let networkMonitor = networkMonitor
        let diskMonitor = diskMonitor
        let gpuMonitor = gpuMonitor
        let powerMonitor = powerMonitor
        let sensorMonitor = sensorMonitor

        importSleepHistory(after: .zero)
        worker = Task { [weak self] in
            defer {
                if let self, self.generation == run { self.worker = nil }
            }
            await monitor.reset()
            await processMonitor?.reset()
            await networkMonitor?.reset()
            await diskMonitor?.reset()
            await gpuMonitor?.reset()
            await powerMonitor?.reset()
            await sensorMonitor?.reset()
            var nextProcessSample = ContinuousClock.now
            while !Task.isCancelled {
                do {
                    _ = try await monitor.sample()
                    let history = await monitor.history()
                    var network: [CapturedNetwork]?
                    if let networkMonitor {
                        _ = try await networkMonitor.sample()
                        network = await networkMonitor.history()
                    }
                    var disks: [CapturedDisks]?
                    if let diskMonitor {
                        _ = try await diskMonitor.sample()
                        disks = await diskMonitor.history()
                    }
                    var gpus: [CapturedGPU]?
                    if let gpuMonitor {
                        _ = try await gpuMonitor.sample()
                        gpus = await gpuMonitor.history()
                    }
                    var power: [CapturedPower]?
                    if let powerMonitor {
                        _ = try await powerMonitor.sample()
                        power = await powerMonitor.history()
                    }
                    var sensors: [CapturedSensors]?
                    if let sensorMonitor {
                        _ = try await sensorMonitor.sample()
                        sensors = await sensorMonitor.history()
                    }
                    var processes: CapturedProcesses?
                    if let processMonitor, ContinuousClock.now >= nextProcessSample {
                        processes = try await processMonitor.sample()
                        nextProcessSample = ContinuousClock.now.advanced(by: processInterval)
                    }
                    guard let self, self.generation == run, !Task.isCancelled else { return }
                    self.liveFrames = history
                    // An interrupted sample usually follows a wake; powerd may still be writing its record.
                    if history.last?.continuity == .interrupted { self.importSleepHistory(after: Self.wakeSettleDelay) }
                    if let processes {
                        self.liveProcesses = processes
                        self.liveContributorHistory.append(Contributors.snapshot(from: processes))
                        self.liveContributorHistory = Array(self.liveContributorHistory.suffix(Self.contributorCapacity))
                        let interval = self.liveLedger.record(processes, logicalCPUCount: history.last?.inventory.logicalCPUCount)
                        if let interval, let recorder = self.historyRecorder { Task { await recorder.recordLedger(interval) } }
                        self.liveLifecycle.record(processes)
                    }
                    if let network { self.liveNetworkFrames = network }
                    if let disks { self.liveDiskFrames = disks }
                    if let gpus { self.liveGPUFrames = gpus }
                    if let power { self.livePowerFrames = power }
                    if let sensors { self.liveSensorFrames = sensors }
                    self.evaluateAlerts()
                    self.recordHistory()
                    if self.timeRange.reachesStoredHistory, self.recordsHistory { self.refreshStoredHistory() }
                    if self.displayMode == .live {
                        self.frames = history
                        if let processes {
                            self.processSnapshot = processes
                            self.contributorHistory = self.liveContributorHistory
                            self.ledger = self.liveLedger
                            self.lifecycle = self.liveLifecycle
                        }
                        if let network { self.networkFrames = network }
                        if let disks { self.diskFrames = disks }
                        if let gpus { self.gpuFrames = gpus }
                        if let power { self.powerFrames = power }
                        if let sensors { self.sensorFrames = sensors }
                    }
                    try await Task.sleep(for: self.interval)
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, self.generation == run else { return }
                    self.collectionError = "Collection failed: \(error)"
                    return
                }
            }
        }
    }

    public func stop() {
        generation = UUID()
        worker?.cancel()
        worker = nil
        if let historyRecorder { Task { await historyRecorder.flush() } }
    }

    public func toggleDisplayHold() {
        if displayMode == .live {
            displayMode = .held
            return
        }
        displayMode = .live
        frames = liveFrames
        processSnapshot = liveProcesses
        contributorHistory = liveContributorHistory
        ledger = liveLedger
        lifecycle = liveLifecycle
        networkFrames = liveNetworkFrames
        diskFrames = liveDiskFrames
        gpuFrames = liveGPUFrames
        powerFrames = livePowerFrames
        sensorFrames = liveSensorFrames
    }

    public func reading(for metric: DashboardMetric) -> DashboardReading? {
        switch metric {
        case .cpu: return displayedFrame?.cpuPercentOfMachine
        case .memory: return displayedFrame?.memoryUsedBytes
        case .networkReceived, .networkSent:
            guard let frame = atCursor(networkFrames, tolerance: Self.cursorTolerance, time: { $0.stamp.wallTime })
            else { return nil }
            return networkReading(for: metric, in: frame)
        case .diskRead, .diskWritten:
            guard let frame = atCursor(diskFrames, tolerance: Self.cursorTolerance, time: { $0.stamp.wallTime })
            else { return nil }
            if let device = storageDevice(in: frame) {
                return metric == .diskRead ? device.readBytesPerSecond : device.writtenBytesPerSecond
            }
            return frame.enumeration.numericValue == nil ? frame.enumeration : nil
        }
    }

    /// Live points, behind stored ones for a long range. Stored rates follow
    /// the recorder's choices, so they appear only for the primary interface
    /// and the automatic storage device.
    public func points(for metric: DashboardMetric) -> [DashboardPoint] {
        let live = livePoints(for: metric)
        switch metric {
        case .cpu:
            return prefixed(live, stored: storedHistory?.lines[.cpu], liveStart: frames.first?.stamp.wallTime)
        case .memory:
            return prefixed(live, stored: storedHistory?.lines[.memoryUsed], liveStart: frames.first?.stamp.wallTime)
        case .networkReceived, .networkSent:
            guard networkScope == .primary else { return live }
            let stored: HistoryMetric = metric == .networkReceived ? .networkReceived : .networkSent
            return prefixed(live, stored: storedHistory?.lines[stored], liveStart: networkFrames.first?.stamp.wallTime)
        case .diskRead, .diskWritten:
            guard case .automatic = storageScope else { return live }
            let stored: HistoryMetric = metric == .diskRead ? .diskRead : .diskWritten
            return prefixed(live, stored: storedHistory?.lines[stored], liveStart: diskFrames.first?.stamp.wallTime)
        }
    }

    private func livePoints(for metric: DashboardMetric) -> [DashboardPoint] {
        if metric == .networkReceived || metric == .networkSent { return networkPoints(for: metric) }
        if metric == .diskRead || metric == .diskWritten { return diskPoints(for: metric) }
        var result: [DashboardPoint] = []
        var segment = 0
        for frame in frames {
            if frame.continuity == .interrupted { segment += 1 }
            let reading = metric == .cpu ? frame.cpuPercentOfMachine : frame.memoryUsedBytes
            guard let value = reading.numericValue else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(
                id: frame.id, time: frame.stamp.wallTime, value: value, segment: segment
            ))
        }
        return result
    }

    public func memoryStack() -> [MemoryStackPoint] {
        let live = liveMemoryStack()
        guard let stored = storedHistory?.memoryStack, !stored.isEmpty else { return live }
        let older = stored.filter { $0.time < frames.first?.stamp.wallTime ?? .distantFuture }
        let offset = (older.last?.segment ?? -1) + 1
        return older + live.map {
            MemoryStackPoint(
                id: $0.id, time: $0.time, category: $0.category, lower: $0.lower, upper: $0.upper,
                segment: $0.segment + offset
            )
        }
    }

    /// Stack only frames with every layer known; any missing layer is a gap.
    private func liveMemoryStack() -> [MemoryStackPoint] {
        var result: [MemoryStackPoint] = []
        var segment = 0
        for frame in frames {
            if frame.continuity == .interrupted { segment += 1 }
            let detail = frame.memory
            let layers: [(MemoryCategory, MetricReading)] = [
                (.app, detail.appBytes), (.wired, detail.wiredBytes),
                (.compressed, detail.compressedBytes), (.cached, detail.cachedBytes)
            ]
            let values = layers.compactMap { $0.1.numericValue }
            guard values.count == layers.count else {
                segment += 1
                continue
            }

            var lower = 0.0
            for ((category, _), value) in zip(layers, values) {
                result.append(MemoryStackPoint(
                    id: "\(frame.id)-\(category.rawValue)", time: frame.stamp.wallTime,
                    category: category, lower: lower, upper: lower + value, segment: segment
                ))
                lower += value
            }
        }
        return result
    }

    /// Stored bands end where live history starts.
    public func memoryPressureSpans() -> [MemoryPressureSpan] {
        let liveStart = frames.first?.stamp.wallTime ?? .distantFuture
        let older = (storedHistory?.memoryPressure ?? []).filter { $0.start < liveStart }.map {
            MemoryPressureSpan(id: $0.id, start: $0.start, end: min($0.end, liveStart), level: $0.level)
        }
        return older + levelSpans { $0.memory.pressureLevel }.map {
            MemoryPressureSpan(id: $0.id, start: $0.start, end: $0.end, level: $0.level)
        }
    }

    public func thermalPressureSpans() -> [ThermalPressureSpan] {
        let liveStart = frames.first?.stamp.wallTime ?? .distantFuture
        let older = (storedHistory?.thermalPressure ?? []).filter { $0.start < liveStart }.map {
            ThermalPressureSpan(id: $0.id, start: $0.start, end: min($0.end, liveStart), level: $0.level)
        }
        return older + levelSpans { ThermalPressureLevel(reading: $0.thermalPressure) }.map {
            ThermalPressureSpan(id: $0.id, start: $0.start, end: $0.end, level: $0.level)
        }
    }

    /// Span consecutive known levels; interruptions and missing levels break the band.
    private func levelSpans<Level: Equatable>(
        _ level: (CapturedSnapshot) -> Level?
    ) -> [(id: UUID, start: Date, end: Date, level: Level)] {
        var result: [(id: UUID, start: Date, end: Date, level: Level)] = []
        var previousTime: Date?
        for frame in frames {
            if frame.continuity == .interrupted { previousTime = nil }
            guard let current = level(frame) else {
                previousTime = nil
                continue
            }
            if let previousTime {
                // Contiguous spans at one level merge, so an hour stays a few rectangles.
                if let last = result.last, last.end == previousTime, last.level == current {
                    result[result.count - 1].end = frame.stamp.wallTime
                } else {
                    result.append((id: frame.id, start: previousTime, end: frame.stamp.wallTime, level: current))
                }
            }
            previousTime = frame.stamp.wallTime
        }
        return result
    }

    /// Stored readings carry no sensor key, so their part cannot mark a change of sensor.
    public func hottestTemperaturePoints() -> [DashboardPoint] {
        prefixed(liveHottestPoints(), stored: storedHistory?.lines[.hottestCelsius], liveStart: sensorFrames.first?.stamp.wallTime)
    }

    /// Hottest-sensor history; a new hottest key starts a new segment, so a
    /// change of sensor never reads as a temperature trend.
    private func liveHottestPoints() -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        var previousKey: String?
        for frame in sensorFrames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let hottest = frame.hottest, let value = hottest.celsius.numericValue else {
                segment += 1
                previousKey = nil
                continue
            }
            if let previousKey, previousKey != hottest.key { segment += 1 }
            previousKey = hottest.key
            result.append(DashboardPoint(id: frame.id, time: frame.stamp.wallTime, value: value, segment: segment))
        }
        return result
    }

    public func batteryChargePoints() -> [DashboardPoint] {
        prefixed(liveBatteryPoints(), stored: storedHistory?.lines[.batteryCharge], liveStart: powerFrames.first?.stamp.wallTime)
    }

    /// Battery charge history; a missing reading or interruption splits the line.
    private func liveBatteryPoints() -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        for frame in powerFrames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let value = frame.batteryChargePercent.numericValue else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(id: frame.id, time: frame.stamp.wallTime, value: value, segment: segment))
        }
        return result
    }

    /// Spans ending at samples taken on external power; unknown sources break the band.
    public func externalPowerSpans() -> [ExternalPowerSpan] {
        var result: [ExternalPowerSpan] = []
        var previousTime: Date?
        for frame in powerFrames {
            if frame.continuity == .interrupted { previousTime = nil }
            guard let source = frame.powerSource else {
                previousTime = nil
                continue
            }
            if source == .externalPower, let previousTime {
                if let last = result.last, last.end == previousTime {
                    result[result.count - 1] = ExternalPowerSpan(id: last.id, start: last.start, end: frame.stamp.wallTime)
                } else {
                    result.append(ExternalPowerSpan(id: frame.id, start: previousTime, end: frame.stamp.wallTime))
                }
            }
            previousTime = frame.stamp.wallTime
        }
        return result
    }

    /// Stored utilization is the first GPU's, so it extends a lone series only.
    public func gpuSeries() -> [GPUSeries] {
        let live = liveGPUSeries()
        guard live.count == 1, let only = live.first else { return live }
        let points = prefixed(only.points, stored: storedHistory?.lines[.gpuBusy], liveStart: gpuFrames.first?.stamp.wallTime)
        return [GPUSeries(id: only.id, name: only.name, points: points)]
    }

    /// One series per observed GPU, in first-seen order.
    private func liveGPUSeries() -> [GPUSeries] {
        var order: [GPUDeviceID] = []
        var names: [GPUDeviceID: String] = [:]
        var points: [GPUDeviceID: [DashboardPoint]] = [:]
        var segments: [GPUDeviceID: Int] = [:]
        var interruptions = 0
        for frame in gpuFrames {
            if frame.continuity == .interrupted { interruptions += 1 }
            let present = Set(frame.devices.map(\.id))
            // A device absent from a frame must not be bridged across it.
            for id in order where !present.contains(id) { segments[id, default: 0] += 1 }
            for device in frame.devices {
                if names[device.id] == nil { order.append(device.id) }
                names[device.id] = device.name
                guard let value = device.utilizationPercent.numericValue else {
                    segments[device.id, default: 0] += 1
                    continue
                }
                points[device.id, default: []].append(DashboardPoint(
                    id: frame.id, time: frame.stamp.wallTime, value: value,
                    segment: interruptions + segments[device.id, default: 0]
                ))
            }
        }
        return order.map { GPUSeries(id: $0, name: names[$0] ?? "GPU", points: points[$0] ?? []) }
    }

    private func networkInterface(in frame: CapturedNetwork) -> CapturedInterface? {
        let identity: CapturedInterfaceID?
        switch networkScope {
        case .primary: identity = frame.primaryInterface
        case .interface(let selected): identity = selected
        }
        return frame.interfaces.first { $0.id == identity }
    }

    private func networkReading(for metric: DashboardMetric, in frame: CapturedNetwork) -> DashboardReading {
        if let interface = networkInterface(in: frame) {
            return metric == .networkReceived
                ? interface.receivedBytesPerSecond : interface.sentBytesPerSecond
        }
        if frame.enumeration.numericValue == nil { return frame.enumeration }
        if networkScope == .primary, let issue = frame.primaryIssue { return issue }
        return .gap(reason: "Selected interface is not observed; choose an available interface")
    }

    private func networkPoints(for metric: DashboardMetric) -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        var previousInterface: CapturedInterfaceID?
        for frame in networkFrames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let interface = networkInterface(in: frame) else {
                segment += 1
                continue
            }
            if let previousInterface, previousInterface != interface.id { segment += 1 }
            previousInterface = interface.id
            let reading = metric == .networkReceived
                ? interface.receivedBytesPerSecond : interface.sentBytesPerSecond
            guard let value = reading.numericValue else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(
                id: frame.id, time: interface.stamp.wallTime, value: value, segment: segment
            ))
        }
        return result
    }

    private func storageDevice(in frame: CapturedDisks) -> CapturedStorageDevice? {
        switch storageScope {
        case .automatic:
            guard frame.devices.count == 1, frame.issues.isEmpty, !frame.enumerationTruncated else { return nil }
            return frame.devices.first
        case .device(let selected): return frame.devices.first { $0.id == selected }
        }
    }

    private func diskPoints(for metric: DashboardMetric) -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        var previousDevice: CapturedStorageID?
        for frame in diskFrames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let device = storageDevice(in: frame) else {
                segment += 1
                continue
            }
            if let previousDevice, previousDevice != device.id { segment += 1 }
            previousDevice = device.id
            let reading = metric == .diskRead ? device.readBytesPerSecond : device.writtenBytesPerSecond
            guard let value = reading.numericValue else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(
                id: frame.id, time: device.stamp.wallTime, value: value, segment: segment
            ))
        }
        return result
    }
}
