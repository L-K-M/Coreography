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
    /// Apple Silicon power, cluster activity and frequency; empty without IOReport.
    public private(set) var siliconFrames: [CapturedSilicon] = []
    public var processFilter = "" {
        didSet {
            if wantsConnections { sampleConnections() }
            if wantsOpenFiles { sampleOpenFiles() }
            // As with the by-user view: starting to name a user asks again for names not given.
            if ProcessFilter.parse(processFilter).usesAccountNames, !ProcessFilter.parse(oldValue).usesAccountNames {
                accountsAsked = []
            }
        }
    }
    /// The session being recorded (plan P19), when one is.
    public var recordingName: String? { sessionRecording?.name }
    public var recordingStart: Date? { sessionRecording?.start }
    /// Saved sessions, newest first.
    public private(set) var sessions: [RecordedSession] = []
    /// A call-stack sample the person asked for (plan: Sample), one at a time.
    public private(set) var sampleState: SampleState = .idle
    @ObservationIgnored private var sampleRun: UUID?
    /// Filters kept as chips under the field.
    public private(set) var savedFilters: [String] = []
    /// The pane under the lanes; connections are read only while shown or filtered on.
    public var detailPane: DetailPane = .processes {
        didSet {
            if wantsConnections { sampleConnections() }
            if detailPane == .sensors { publishSensorStats() }
            if detailPane == .startup, startupInventory == nil { refreshStartupItems() }
        }
    }
    /// The process table's selected row; selecting one opens the inspector.
    public var selectedProcessRow: ProcessRow.ID? {
        didSet {
            guard selectedProcessRow != oldValue else { return }
            // A process takes the inspector from a lane's page; deselecting it returns to the summary.
            if selectedProcessRow != nil {
                inspectorShown = true
                inspectedLane = nil
            }
            selectedProcessHistory = []
            selectedHistorySegment = 0
            inspectSelection()
        }
    }
    /// The inspector panel (plan: hidden by default, opens on selection).
    public var inspectorShown = false
    /// Read for the selected process only: arguments, signature and sockets.
    public private(set) var processDetail: CapturedProcessDetail?
    public private(set) var inspectedSockets: [CapturedConnection]?
    /// Startup items as last read; definitions change rarely, so they load on request.
    public private(set) var startupInventory: CapturedStartupInventory?
    public var startupVisibility: StartupVisibility = .thirdParty
    /// Exports redact app names unless asked otherwise (plan: for sharing).
    public var exportNaming: ExportNaming = .redacted
    /// The Sensors tab: each reading's current, minimum, maximum and mean since reset.
    public private(set) var sensorRows: [SensorStatRow] = []
    public private(set) var sensorStatsSince: Date?
    /// Free text over app, process, address and port in the Connections tab.
    public var connectionFilter = ""
    /// Displayed (possibly held) sockets; nil until first read.
    public private(set) var connectionSnapshot: CapturedConnections?
    /// Displayed (possibly held) open files; nil until first read.
    public private(set) var openFileSnapshot: CapturedOpenFiles?
    /// The selected process's open files, read on selection.
    public private(set) var inspectedFiles: [String]?
    /// The selected process held more files than one read keeps; the list is a start.
    public private(set) var inspectedFilesCut = false
    /// The selected process's readings since it was selected, an hour at most.
    public private(set) var selectedProcessHistory: [ProcessHistoryPoint] = []
    @ObservationIgnored private var selectedHistorySegment = 0
    @ObservationIgnored private var threadRead: Task<Void, Never>?
    /// Displayed (possibly held) power assertions; nil until first read.
    public private(set) var assertionSnapshot: CapturedAssertions?
    /// Displayed (possibly held) per-process network rates; nil until first read.
    public private(set) var trafficSnapshot: CapturedTraffic?
    /// Time Machine and Spotlight state when last read; nil until first read.
    public private(set) var maintenanceStatus: CapturedMaintenance?
    public var processSort: ProcessSort = .cpu
    public var processGrouping: ProcessGrouping = .app {
        // Choosing the by-user view again asks again for names a directory could not give.
        didSet { if processGrouping == .user, oldValue != .user { accountsAsked = [] } }
    }
    /// The shared hover time across all lanes; nil follows the live edge.
    public var cursorTime: Date?
    /// A new range reads its own stored span at once; the reload interval belongs to the old one.
    public var timeRange: TimeRange = .minute {
        didSet {
            if timeRange != oldValue { dropStoredHistory() }
            refreshStoredHistory()
            // A wider range has less room to pan back within the same history.
            if let newest = displayedEndTime { panOffset = clampedPan(panOffset, newest: newest) }
        }
    }
    /// A dragged time range; cleared only explicitly (plan: Esc or clear).
    /// A comparison needs it, so clearing it in any way drops the comparison.
    public var selection: ClosedRange<Date>? {
        didSet {
            guard selection == nil else { return }
            comparison = nil
            draftComparison = nil
        }
    }
    /// The range while a drag is in progress; reports wait for the drag to end.
    public var draftSelection: ClosedRange<Date>?
    public private(set) var markers: [TimelineMarker] = []
    /// Sleep, wake, power source, pressure changes and app starts and exits found in the displayed data.
    public private(set) var systemMarkers: [TimelineMarker] = []
    /// Everything the lanes mark: the person's actions, alerts and system events.
    public var timelineMarkers: [TimelineMarker] { ownMarkers + systemMarkers }
    /// The person's and alerts' markers, which a recording keeps; system
    /// markers are derived again from the recorded frames when it opens.
    private var ownMarkers: [TimelineMarker] { openRecording == nil ? markers : recordingMarkers }
    /// The recording shown in place of live data, when one is open.
    public private(set) var openRecording: OpenRecording?
    private var recordingMarkers: [TimelineMarker] = []
    /// The recording open in flight; a newer open or a return to live replaces it.
    @ObservationIgnored private var recordingOpening: UUID?
    /// One app scoping every view (plan P8); cleared only by its clear button.
    public var scopedApp: String?
    public private(set) var actionMessage: String?
    public private(set) var askState: AskState = .idle
    /// Why history is not being recorded, when it is not.
    public private(set) var historyProblem: String?
    public var recordsHistory: Bool { historyRecorder != nil }
    /// Why the stored part of a long range is missing, when it is.
    public private(set) var storedHistoryProblem: String?
    /// How long history is kept; saved, and applied to the store's next write.
    public var historyRetention = HistoryRetention.saved() {
        didSet {
            guard historyRetention != oldValue else { return }
            historyRetention.save()
            applyRetention()
            dropStoredHistory()
            if timeRange.reachesStoredHistory { refreshStoredHistory() }
        }
    }
    /// The measured size of stored history, refreshed on request.
    public private(set) var historyBytes: Int64?
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
    @ObservationIgnored private let maintenanceProvider: MaintenanceStatusProvider?
    @ObservationIgnored private var maintenanceRead: Task<Void, Never>?
    @ObservationIgnored private let connectionMonitor: ConnectionMonitor?
    /// Names follow displayed peers, so live changes cannot alter held rows.
    @ObservationIgnored private let serverNameResolver: ServerNameResolver?
    @ObservationIgnored private var serverNameTask: Task<Void, Never>?
    /// Resolved PTR names by peer address, for the Connections tab's
    /// domain grouping.
    public private(set) var serverNames: [String: String] = [:]
    @ObservationIgnored private var connectionSample: Task<Void, Never>?
    @ObservationIgnored private var liveConnections: CapturedConnections?
    @ObservationIgnored private let assertionReader: AssertionReader?
    @ObservationIgnored private let openFileMonitor: OpenFileMonitor?
    @ObservationIgnored private var openFileSample: Task<Void, Never>?
    @ObservationIgnored private var liveOpenFiles: CapturedOpenFiles?
    @ObservationIgnored private var liveAssertions: CapturedAssertions?
    @ObservationIgnored private let trafficMonitor: ProcessTrafficMonitor?
    @ObservationIgnored private var liveTraffic: CapturedTraffic?
    @ObservationIgnored private var filterStore = SavedFilters(defaults: .standard)
    private var sessionRecording: SessionRecording?
    @ObservationIgnored private let sessionArchive: SessionArchive?
    @ObservationIgnored private let sampler: ProcessSampler?
    @ObservationIgnored private let spindumper: ProcessSpindumper?
    /// Mutable: its tracker records one probe per process sample.
    @ObservationIgnored private var responsivenessMonitor: ResponsivenessMonitor?
    /// Watches observed pids for exits and their wait statuses (kqueue).
    @ObservationIgnored private var exitWatcher: ProcessExitWatcher?
    /// Processes whose UI has stopped answering; nil until the probe first ran.
    private var notResponding: Set<ProcessIdentity>?
    @ObservationIgnored private var sensorStats = SensorStats()
    @ObservationIgnored private let startupProvider: StartupProvider?
    @ObservationIgnored private let inspector: ProcessInspector?
    @ObservationIgnored private var inspection: Task<Void, Never>?
    @ObservationIgnored private var startupLoad: Task<Void, Never>?
    /// The on-disk part of a range longer than live history; nil otherwise.
    private var storedHistory: StoredHistory?
    /// The open recording's stored part as raw data, so saving a range of
    /// the replay carries it; the store's history is not the file's.
    @ObservationIgnored private var openStoredData: StoredHistory.RawData?
    @ObservationIgnored private var storedLoad: Task<Void, Never>?
    @ObservationIgnored private var storedLoadedAt: Date?
    @ObservationIgnored private var recordedSources = RecordedSources()
    @ObservationIgnored private var storedScopedCache: (
        app: String, window: ClosedRange<Date>, series: (cpu: [DashboardPoint], disk: [DashboardPoint], network: [DashboardPoint])
    )?
    @ObservationIgnored private var scopedReadingCache: (
        app: String, stamp: SampleStamp, readings: [ScopedMetric: ScopedAppReading]
    )?
    @ObservationIgnored private var sleepState: SleepHistoryState = .notImported
    @ObservationIgnored private var sleepImport: Task<Void, Never>?
    @ObservationIgnored private var wakeImports = WakeImportSpacing()
    @ObservationIgnored private var alertEngine = AlertEngine(rules: AlertRules.shipped)
    @ObservationIgnored private var customAlertStore = CustomAlertRules(defaults: .standard)
    @ObservationIgnored private let accounts = AccountDirectory()
    /// Names for the by-user view, looked up off the main actor: a directory
    /// service can take a moment for a UID it has not answered before.
    private var accountNames: [UInt32: String] = [:]
    @ObservationIgnored private var accountsAsked: Set<UInt32> = []
    @ObservationIgnored private var accountLookup: Task<Void, Never>?
    @ObservationIgnored private let signerDirectory = SignerDirectory()
    /// Signers by executable path, checked off the main actor: checking a
    /// program's signature reads it from disk.
    private var signers: [String: CapturedSigner] = [:]
    @ObservationIgnored private var signersAsked: Set<String> = []
    @ObservationIgnored private var signerLookup: Task<Void, Never>?
    @ObservationIgnored private var alertCooldown = AlertCooldown()
    /// Shortcut runs have their own cooldown, so a flapping rule cannot loop one.
    @ObservationIgnored private var shortcutCooldown = AlertCooldown()
    @ObservationIgnored private var shortcutStore = AlertShortcuts(defaults: .standard)
    @ObservationIgnored private let shortcutRunner: ShortcutLauncher?
    @ObservationIgnored private var runningShortcuts: Set<String> = []
    @ObservationIgnored private let volumeReader: VolumeMonitor?
    @ObservationIgnored private var volumeRead: Task<Void, Never>?
    @ObservationIgnored private var startupFreeFraction: Double?
    /// Every visible volume's capacity, read once a minute; nil before the first read.
    public private(set) var volumes: CapturedVolumes?
    @ObservationIgnored private var volumeReadAt: Date?
    @ObservationIgnored private var askTask: Task<Void, Never>?
    @ObservationIgnored private let processMonitor: ProcessMonitor?
    @ObservationIgnored private let networkMonitor: NetworkMonitor?
    @ObservationIgnored private let diskMonitor: DiskMonitor?
    @ObservationIgnored private let gpuMonitor: GPUMonitor?
    @ObservationIgnored private let powerMonitor: PowerMonitor?
    @ObservationIgnored private let sensorMonitor: SensorMonitor?
    @ObservationIgnored private let siliconMonitor: SiliconMonitor?
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let energyMode: EnergyModeMonitor?
    @ObservationIgnored private let processInterval: Duration
    private static let attributionHostFrames = 16
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
    @ObservationIgnored private var liveSiliconFrames: [CapturedSilicon] = []

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
        maintenanceProvider = MaintenanceStatusProvider()
        connectionMonitor = ConnectionMonitor()
        serverNameResolver = ServerNameResolver()
        startupProvider = StartupProvider()
        inspector = ProcessInspector()
        assertionReader = AssertionReader()
        openFileMonitor = OpenFileMonitor()
        shortcutRunner = ShortcutLauncher()
        volumeReader = VolumeMonitor()
        energyMode = EnergyModeMonitor()
        sessionArchive = SessionArchive.makeDefault()
        sampler = ProcessSampler()
        spindumper = ProcessSpindumper()
        responsivenessMonitor = ResponsivenessMonitor()
        exitWatcher = ProcessExitWatcher()
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
            let silicon = try SiliconMonitor()
            let traffic = try ProcessTrafficMonitor()
            monitor = system
            processMonitor = processes
            networkMonitor = network
            diskMonitor = disk
            gpuMonitor = gpu
            powerMonitor = power
            sensorMonitor = sensors
            siliconMonitor = silicon
            trafficMonitor = traffic
        } catch {
            monitor = nil
            processMonitor = nil
            networkMonitor = nil
            diskMonitor = nil
            gpuMonitor = nil
            powerMonitor = nil
            sensorMonitor = nil
            siliconMonitor = nil
            trafficMonitor = nil
            collectionError = "Cannot initialize monitoring: \(error)"
        }
        applyRetention()
        savedFilters = filterStore.all
        alertShortcuts = shortcutStore.all
        customAlertRules = customAlertStore.all
        alertEngine = AlertEngine(rules: AlertRules.shipped + customAlertRules.map(\.alertRule))
    }

    init(
        monitor: SystemMonitor, interval: Duration,
        processMonitor: ProcessMonitor? = nil, processInterval: Duration = .seconds(2),
        networkMonitor: NetworkMonitor? = nil, diskMonitor: DiskMonitor? = nil,
        gpuMonitor: GPUMonitor? = nil, powerMonitor: PowerMonitor? = nil,
        sensorMonitor: SensorMonitor? = nil, siliconMonitor: SiliconMonitor? = nil,
        trafficMonitor: ProcessTrafficMonitor? = nil, controller: ProcessController = ProcessController(),
        askService: AskService = AskService(), notifier: AlertDelivery? = nil,
        historyRecorder: HistoryRecorder? = nil, sleepProvider: SleepHistoryProvider? = nil,
        connectionMonitor: ConnectionMonitor? = nil, serverNameResolver: ServerNameResolver? = nil,
        startupProvider: StartupProvider? = nil,
        inspector: ProcessInspector? = nil, assertionReader: AssertionReader? = nil,
        openFileMonitor: OpenFileMonitor? = nil, sessionArchive: SessionArchive? = nil,
        sampler: ProcessSampler? = nil, spindumper: ProcessSpindumper? = nil,
        responsivenessMonitor: ResponsivenessMonitor? = nil, exitWatcher: ProcessExitWatcher? = nil,
        maintenanceProvider: MaintenanceStatusProvider? = nil,
        shortcutRunner: ShortcutLauncher? = nil, volumeReader: VolumeMonitor? = nil,
        energyMode: EnergyModeMonitor? = nil
    ) {
        self.energyMode = energyMode
        self.shortcutRunner = shortcutRunner
        self.volumeReader = volumeReader
        self.controller = controller
        self.askService = askService
        self.notifier = notifier
        self.historyRecorder = historyRecorder
        self.sleepProvider = sleepProvider
        self.maintenanceProvider = maintenanceProvider
        self.connectionMonitor = connectionMonitor
        self.serverNameResolver = serverNameResolver
        self.startupProvider = startupProvider
        self.inspector = inspector
        self.assertionReader = assertionReader
        self.openFileMonitor = openFileMonitor
        self.sessionArchive = sessionArchive
        self.sampler = sampler
        self.spindumper = spindumper
        self.responsivenessMonitor = responsivenessMonitor
        self.exitWatcher = exitWatcher
        self.monitor = monitor
        self.interval = interval
        self.processMonitor = processMonitor
        self.processInterval = processInterval
        self.networkMonitor = networkMonitor
        self.diskMonitor = diskMonitor
        self.gpuMonitor = gpuMonitor
        self.powerMonitor = powerMonitor
        self.sensorMonitor = sensorMonitor
        self.siliconMonitor = siliconMonitor
        self.trafficMonitor = trafficMonitor
    }

    deinit {
        worker?.cancel()
        askTask?.cancel()
        sleepImport?.cancel()
        maintenanceRead?.cancel()
        volumeRead?.cancel()
        storedLoad?.cancel()
        connectionSample?.cancel()
        openFileSample?.cancel()
        startupLoad?.cancel()
        inspection?.cancel()
    }

    public var latest: CapturedSnapshot? { frames.last }

    // A cursor reads the nearest sample within these windows, or nothing.
    private static let cursorTolerance: TimeInterval = 1.5
    private static let contributorTolerance: TimeInterval = 2.5
    private static let wakeSettleDelay: Duration = .seconds(10)
    /// Two short tool runs every five minutes keep diagnostics current at negligible cost.
    private static let maintenanceRefreshAge: TimeInterval = 300
    /// Selecting backupd or Spotlight rereads a status older than this.
    private static let maintenanceSelectionAge: TimeInterval = 10
    /// The recorder flushes every 30 s; rereading the store more often finds nothing new.
    private static let storedReloadInterval: TimeInterval = 60
    /// One hour of two-second process samples, matching live history.
    private static let contributorCapacity = 1800

    /// Host frame at the cursor, or the latest frame without one.
    public var displayedFrame: CapturedSnapshot? { atCursor(frames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedGPUFrame: CapturedGPU? { atCursor(gpuFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedPowerFrame: CapturedPower? { atCursor(powerFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    /// Lanes showing their detail in place (plan: double-click expands a lane).
    public private(set) var expandedLanes: Set<LaneKind> = []

    public func toggleDetail(_ lane: LaneKind) {
        if expandedLanes.contains(lane) { expandedLanes.remove(lane) } else { expandedLanes.insert(lane) }
    }

    /// The lane whose facts the inspector shows while no process is selected.
    public var inspectedLane: LaneKind? {
        didSet { if inspectedLane != nil { inspectorShown = true } }
    }
    public var displayedNetworkFrame: CapturedNetwork? { atCursor(networkFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedDiskFrame: CapturedDisks? { atCursor(diskFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime } }
    public var displayedSensorFrame: CapturedSensors? {
        atCursor(sensorFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime }
    }
    public var displayedSiliconFrame: CapturedSilicon? {
        atCursor(siliconFrames, tolerance: Self.cursorTolerance) { $0.stamp.wallTime }
    }

    /// Heuristic hints over the last seconds of displayed data (plan:
    /// bottleneck hints); empty without silicon or GPU readings.
    public var bottleneckHints: [BottleneckHint] {
        guard let end = displayedEndTime else { return [] }
        let thermal = frames.last.flatMap { ThermalPressureLevel(reading: $0.thermalPressure) }
        return BottleneckHints.evaluate(gpu: gpuFrames, silicon: siliconFrames, thermal: thermal, now: end)
    }

    /// System draw from one qualified source (plan): an SMC rail where the
    /// Mac publishes one, otherwise battery discharge while unplugged.
    public var displayedSystemPower: DashboardReading? {
        if let rail = displayedSensorFrame?.systemPowerWatts, rail.numericValue != nil { return rail }
        return displayedPowerFrame?.systemPowerWatts ?? displayedSensorFrame?.systemPowerWatts
    }
    /// Before the live process samples, the stored ledger answers for the
    /// cursor with what it kept: CPU, disk and network per app.
    public var displayedContributors: ContributorSnapshot? {
        if let live = atCursor(contributorHistory, tolerance: Self.contributorTolerance, time: { $0.time }) { return live }
        guard let cursorTime, cursorTime < contributorHistory.first?.time ?? .distantFuture else { return nil }
        return storedHistory?.ledger.contributors(at: cursorTime)
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

    /// How far behind the newest displayed data the window ends; scrolling sets it.
    public private(set) var panOffset: TimeInterval = 0

    /// What the lanes draw: the range's width, ending `panOffset` before the newest data.
    public var visibleWindow: ClosedRange<Date>? {
        guard let newest = displayedEndTime else { return nil }
        let end = newest.addingTimeInterval(-panOffset)
        return end.addingTimeInterval(-timeRange.seconds)...end
    }

    /// Plan: scrolling pans further back, as far as history goes. Positive
    /// seconds go back in time and detach from live; the window stays
    /// between the oldest data held and the newest.
    public func pan(bySeconds seconds: TimeInterval) {
        guard seconds.isFinite, let newest = displayedEndTime else { return }
        let offset = clampedPan(panOffset + seconds, newest: newest)
        // Leaving live is a consequence of moving; with no history to move into, stay.
        if offset > 0, displayMode == .live { toggleDisplayHold() }
        panOffset = offset
    }

    /// Plan: pinching zooms through the range pills, keeping the window's end.
    public enum ZoomStep: Sendable { case closer, wider }

    public func zoom(_ step: ZoomStep) {
        let ranges = TimeRange.allCases
        guard let index = ranges.firstIndex(of: timeRange) else { return }
        let next = step == .closer ? index - 1 : index + 1
        guard ranges.indices.contains(next) else { return }
        timeRange = ranges[next]
    }

    private func clampedPan(_ offset: TimeInterval, newest: Date) -> TimeInterval {
        let oldest = [frames.first?.stamp.wallTime, storedHistory?.start].compactMap { $0 }.min() ?? newest
        let room = max(0, newest.timeIntervalSince(oldest) - timeRange.seconds)
        return min(max(offset, 0), room)
    }

    public var displayedEndTime: Date? {
        [
            latest?.stamp.wallTime, networkFrames.last?.stamp.wallTime,
            diskFrames.last?.stamp.wallTime, gpuFrames.last?.stamp.wallTime,
            powerFrames.last?.stamp.wallTime, sensorFrames.last?.stamp.wallTime,
            siliconFrames.last?.stamp.wallTime
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

    /// What a range report depends on. Hovering re-renders the window at
    /// pointer rate, so the report is rebuilt only when one of these changes.
    private struct RangeReportInputs: Equatable {
        let selection: ClosedRange<Date>
        let ledgerIntervals: Int
        let ledgerEnd: Date?
        let frame: UUID?
        let gpuFrame: UUID?
        let sensorFrame: UUID?
        let storedStart: Date?
        let storedEnd: Date?
    }

    @ObservationIgnored private var rangeReportCache: [ClosedRange<Date>: (inputs: RangeReportInputs, report: RangeReport)] = [:]
    /// How many reports were built; tests check that rereading reuses one.
    @ObservationIgnored private(set) var rangeReportBuilds = 0

    /// Totals for the selected range, from displayed (possibly held) data
    /// and, on the 6 h range, stored history before it.
    public var rangeReport: RangeReport? { selection.map(report) }

    /// A second range, Command-dragged, to compare with the selection (plan P7).
    public var comparison: ClosedRange<Date>?
    /// The comparison range while its drag is in progress.
    public var draftComparison: ClosedRange<Date>?

    /// The selection and the comparison range side by side; nil without both.
    public var rangeComparison: RangeComparison? {
        guard let selection, let comparison else { return nil }
        return RangeComparison.make(first: report(selection), second: report(comparison))
    }

    private func report(_ range: ClosedRange<Date>) -> RangeReport {
        let inputs = RangeReportInputs(
            selection: range, ledgerIntervals: ledger.intervals.count, ledgerEnd: ledger.intervals.last?.end,
            frame: frames.last?.id, gpuFrame: gpuFrames.last?.id, sensorFrame: sensorFrames.last?.id,
            storedStart: storedHistory?.start, storedEnd: storedHistory?.end
        )
        if let cache = rangeReportCache[range], cache.inputs == inputs { return cache.report }
        let report = RangeReport.make(
            range: range, ledger: ledger, frames: frames, gpuFrames: gpuFrames, sensorFrames: sensorFrames,
            stored: storedHistory
        )
        // Only the selection and the comparison are ever shown.
        rangeReportCache = rangeReportCache.filter { $0.key == selection || $0.key == comparison }
        rangeReportCache[range] = (inputs, report)
        rangeReportBuilds += 1
        return report
    }

    /// Also drops a drag the system cancelled before it ended, whose band
    /// would otherwise stay on every lane with no panel to clear it.
    public func clearSelection() {
        selection = nil
        draftSelection = nil
        comparison = nil
        draftComparison = nil
    }

    /// Back to one range.
    public func clearComparison() {
        comparison = nil
        draftComparison = nil
    }

    /// The selected range as an export document of displayed (possibly held)
    /// live data. Stored history is not exported yet, so the document starts
    /// where live data does; nil when the whole selection predates it.
    public var rangeExport: RangeExport.Document? {
        guard let selection, let liveStart = frames.first?.stamp.wallTime else { return nil }
        let start = max(selection.lowerBound, liveStart)
        guard start <= selection.upperBound else { return nil }
        let live = start...selection.upperBound
        let frames = DashboardFrames(
            host: frames, network: networkFrames, disks: diskFrames,
            gpu: gpuFrames, power: powerFrames, sensors: sensorFrames
        )
        let apps = ledger.totals(in: live).apps.sorted { $0.cpuSeconds > $1.cpuSeconds }
        return RangeExport.document(range: live, model: frames, apps: apps, naming: exportNaming)
    }

    /// The selected range as a `.coreotrace` recording of displayed data,
    /// the live hour or an open recording, plus the stored history covering
    /// an earlier part. Throws why when that earlier part has no stored
    /// history; the recording is never trimmed to live data silently.
    /// The stored part is re-read from the store at save time: a loaded
    /// history keeps only the reduced form, not the raw series a file
    /// carries.
    public func recordingData(name: String) async throws(Recording.Failure) -> Data {
        // A replayed recording can carry its stored part only, so absent
        // frames mean the whole selection predates live data, not an invalid
        // range; with neither it is invalid.
        guard let selection else { throw .invalidRange }
        let liveStart = frames.first?.stamp.wallTime
        guard liveStart != nil || storedHistory != nil else { throw .invalidRange }
        // The frames and ledger are captured before the store read suspends,
        // so the document stays one instant's snapshot.
        let frames = DashboardFrames(
            host: frames, network: networkFrames, disks: diskFrames, gpu: gpuFrames, power: powerFrames, sensors: sensorFrames
        )
        let ledger = ledger
        let markers = ownMarkers
        var stored: StoredHistory.RawData?
        if selection.lowerBound < (liveStart ?? .distantFuture) {
            guard let history = storedHistory else {
                // A replayed recording without a stored part will never load one.
                if openRecording != nil { throw .missingHistory("The recording holds nothing before its first sample.") }
                throw .missingHistory(storedHistoryProblem ?? "The stored part is still loading; try again in a moment.")
            }
            guard history.start <= selection.lowerBound else {
                throw .missingHistory(
                    "Stored history reaches back only to \(history.start.formatted(date: .abbreviated, time: .shortened))."
                )
            }
            if let openStoredData {
                stored = openStoredData
            } else {
                guard let historyRecorder else {
                    throw .missingHistory(storedHistoryProblem ?? "History is not being recorded.")
                }
                // Under the tier the window's load selected: the replayed
                // file then draws the stored part as the window did.
                do {
                    stored = try await StoredHistory.rawData(
                        from: historyRecorder, tier: history.tier,
                        start: selection.lowerBound, end: selection.upperBound
                    )
                } catch {
                    throw .missingHistory("Stored history could not be read: \(error)")
                }
            }
        }
        // With stored history the recording starts at the selection; without
        // it, at the first live frame as before.
        let start = stored == nil ? max(selection.lowerBound, liveStart ?? selection.lowerBound) : selection.lowerBound
        guard start <= selection.upperBound else { throw .invalidRange }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = Recording.make(
            name: trimmed.isEmpty ? "Recording \(start.formatted(date: .abbreviated, time: .shortened))" : trimmed,
            range: start...selection.upperBound,
            frames: frames,
            ledger: ledger, stored: stored, markers: markers, naming: exportNaming
        )
        return try Recording.encode(document)
    }

    /// A recording file the app could not read at all.
    public func reportRecordingFailure(_ message: String) { actionMessage = message }

    /// Show a recording in the held display; Return to live goes back.
    /// Decoding runs off the main actor, since a file may hold 256 MB. The
    /// file's name, which the person chose, names it over the saved one.
    /// Returns why it could not be opened.
    @discardableResult
    public func openRecording(_ data: Data, fileName: String? = nil) async -> String? {
        // The newest open wins; returning to live meanwhile cancels it.
        let opening = UUID()
        recordingOpening = opening
        let decoded = await Task.detached { () -> Result<Recording.Document, Recording.Failure> in
            do throws(Recording.Failure) { return .success(try Recording.decode(data)) } catch { return .failure(error) }
        }.value
        guard recordingOpening == opening else { return nil }
        recordingOpening = nil
        let document: Recording.Document
        switch decoded {
        case .success(let read):
            document = read
        case .failure(let error):
            actionMessage = error.message
            return error.message
        }
        displayMode = .held
        openRecording = OpenRecording(
            name: fileName ?? document.name, start: document.start, end: document.end, appNames: document.appNames
        )
        frames = document.host
        networkFrames = document.network
        diskFrames = document.disks
        gpuFrames = document.gpu
        powerFrames = document.power
        sensorFrames = document.sensors
        siliconFrames = []
        // Process detail is live state; a recording carries per-app totals only.
        processSnapshot = nil
        contributorHistory = []
        connectionSnapshot = nil
        trafficSnapshot = nil
        openFileSnapshot = nil
        ledger = AppLedger(stored: document.ledger.map { interval in
            LedgerInterval(
                start: interval.start, end: interval.end, cores: interval.cores, coversNetwork: interval.coversNetwork,
                coversEnergy: interval.coversEnergy,
                entries: interval.entries.map {
                    LedgerEntry(app: $0.app, cpuSeconds: $0.cpuSeconds, diskBytes: $0.diskBytes,
                                networkBytes: $0.networkBytes, energyJoules: $0.energyJoules, isLowerBound: $0.isLowerBound)
                }
            )
        })
        recordingMarkers = document.markers.map { TimelineMarker(time: $0.time, label: $0.label, kind: $0.kind ?? .note) }
        cursorTime = nil
        clearSelection()
        let duration = document.end.timeIntervalSince(document.start)
        // A recording carrying a stored part needs the smallest range that
        // covers it, or its earlier part sits outside the window the lanes
        // draw; a live-only one stays on the ranges live data alone fills.
        timeRange = document.stored == nil
            ? TimeRange.allCases.first { $0.seconds >= duration && !$0.reachesStoredHistory } ?? .hour
            : TimeRange.allCases.first { $0.seconds >= duration } ?? .month
        // A live load still in flight must not land over the recording's stored part.
        storedLoad?.cancel()
        storedLoad = nil
        storedLoadedAt = nil
        storedScopedCache = nil
        storedHistoryProblem = nil
        let storedData = document.stored.map {
            StoredHistory.RawData(replaying: $0, range: document.start...document.end)
        }
        openStoredData = storedData
        storedHistory = storedData.map { StoredHistory(reducing: $0) }
        refreshSystemMarkers()
        return nil
    }

    /// Hand the newest live readings to the recorder, which batches writes.
    /// The same readings feed an active session, which keeps them past the live hour.
    /// Each record call waits for the one before it, so waiting for the
    /// newest is waiting for all of them (quitting needs that).
    @ObservationIgnored private var lastRecord: Task<Void, Never>?

    private func enqueueRecord(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let previous = lastRecord
        lastRecord = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func recordHistory() {
        guard historyRecorder != nil || sessionRecording != nil else { return }
        let samples = HistorySamples.latest(
            host: liveFrames.last, network: liveNetworkFrames.last, disks: liveDiskFrames.last,
            gpu: liveGPUFrames.last, power: livePowerFrames.last, sensors: liveSensorFrames.last,
            silicon: liveSiliconFrames.last, sources: &recordedSources
        )
        sessionRecording?.record(samples)
        guard let historyRecorder else { return }
        let now = Date()
        enqueueRecord { [weak self] in
            await historyRecorder.record(samples, at: now)
            let problem = await historyRecorder.lastError
            self?.historyProblem = problem
        }
    }

    /// Load the stored part of a long range, or drop it for a short one. A
    /// held display keeps the prefix it has; a failed read retries at the
    /// reload interval rather than every sample. An open recording's own
    /// stored part stands in for history and is never loaded over.
    private func refreshStoredHistory(now: Date = Date()) {
        guard openRecording == nil else { return }
        guard timeRange.reachesStoredHistory, let historyRecorder else {
            storedLoad?.cancel()
            storedLoad = nil
            storedLoadedAt = nil
            storedHistory = nil
            storedScopedCache = nil
            storedHistoryProblem = timeRange.reachesStoredHistory
                ? (historyProblem ?? "History is not being recorded.") : nil
            return
        }
        guard storedLoad == nil else { return }
        if let storedLoadedAt {
            if displayMode == .held && storedHistory != nil { return }
            // A long range redraws only when a new chart bucket fills: 30 d
            // rereads its month of rollups every two hours, not every minute.
            let reload = max(Self.storedReloadInterval, timeRange.seconds / Double(Decimation.defaultBuckets))
            if now.timeIntervalSince(storedLoadedAt) < reload { return }
        }

        storedLoadedAt = now
        let start = now.addingTimeInterval(-timeRange.seconds)
        let recentRetention = historyRetention.plan.recent
        let dayRetention = historyRetention.plan.day
        storedLoad = Task { [weak self] in
            let result: Result<StoredHistory, any Error>
            do {
                result = .success(try await StoredHistory.load(
                    from: historyRecorder, start: start, end: now, recentRetention: recentRetention,
                    dayRetention: dayRetention
                ))
            } catch {
                result = .failure(error)
            }
            // A load outliving its window — cancelled, or a recording opened
            // meanwhile — must not land its state over the recording's.
            guard let self, !Task.isCancelled, self.openRecording == nil else { return }
            self.storedLoad = nil
            switch result {
            case .success(let loaded):
                self.storedHistory = loaded
                self.refreshSystemMarkers()
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

    /// Every reading's availability and provenance, for Settings (plan: the Data Sources pane).
    public var dataSources: [DataSourceStatus] { DiagnosticTools.dataSources(diagnosticSnapshot()) }

    public func refreshHistorySize() async {
        guard let historyRecorder else { return }
        historyBytes = try? await historyRecorder.size()
    }

    private func applyRetention() {
        guard let historyRecorder else { return }
        let plan = historyRetention.plan
        Task { await historyRecorder.setRetention(plan) }
    }

    /// A recording's stored part leaves only with the recording, not on a
    /// range or retention change.
    private func dropStoredHistory() {
        guard openRecording == nil else { return }
        storedLoad?.cancel()
        storedLoad = nil
        storedLoadedAt = nil
        storedHistory = nil
        openStoredData = nil
        storedScopedCache = nil
    }

    /// One-click deletion of everything recorded on disk.
    public func deleteHistory() async -> String? {
        guard let historyRecorder else { return "History is not being recorded." }
        do {
            try await historyRecorder.deleteAll()
            // Deleted history leaves the screen now, even while the display
            // is held; an open recording's stored part is not the store's.
            if openRecording == nil {
                storedLoad?.cancel()
                storedLoad = nil
                storedLoadedAt = nil
                storedHistory = nil
                storedScopedCache = nil
            }
            if timeRange.reachesStoredHistory { refreshStoredHistory() }
            return nil
        } catch HistoryStoreError.storage(let reason) {
            return reason
        } catch {
            return "\(error)"
        }
    }

    /// Every rule, shipped first, for Settings.
    public var alertRules: [AlertRule] { alertEngine.rules }

    /// The person's own rules; saved, and in effect as soon as edited. An
    /// edited rule starts cleared; the others keep their state.
    public var customAlertRules: [CustomAlertRule] = [] {
        didSet {
            let cleaned = CustomAlertRules.cleaned(customAlertRules)
            if cleaned != customAlertRules {
                customAlertRules = cleaned
                return
            }
            guard customAlertRules != oldValue else { return }
            customAlertStore.save(customAlertRules)
            applyCustomAlertRules(replacing: oldValue)
        }
    }

    private func applyCustomAlertRules(replacing previous: [CustomAlertRule]) {
        let unchanged = customAlertRules.filter { previous.contains($0) }.map(\.alertRule.id)
        alertEngine = alertEngine.replacingRules(
            AlertRules.shipped + customAlertRules.map(\.alertRule),
            keeping: Set(AlertRules.shipped.map(\.id) + unchanged)
        )
        // A deleted rule's Shortcut goes with it.
        let removed = Set(previous.map(\.alertRule.id)).subtracting(customAlertRules.map(\.alertRule.id))
        for id in removed where alertShortcuts[id] != nil { setShortcut(nil, for: id) }
        refreshActiveAlerts()
    }

    private func refreshActiveAlerts() {
        let titles = AlertRules.activeTitles(alertEngine.rules, active: alertEngine.activeRuleIDs)
        if titles != activeAlerts { activeAlerts = titles }
    }

    /// Tests keep their rules out of the person's preferences.
    func useCustomAlertStore(_ defaults: UserDefaults) {
        customAlertStore = CustomAlertRules(defaults: defaults)
        customAlertRules = customAlertStore.all
    }
    /// Each rule's Shortcut, by rule id; saved.
    public private(set) var alertShortcuts: [String: String] = [:]
    /// The person's Shortcuts, read on request; nil until read or when the tool failed.
    public private(set) var availableShortcuts: [String]?
    /// Whether listing Shortcuts was tried and failed, as opposed to not tried yet.
    public private(set) var shortcutsUnlisted = false

    public func setShortcut(_ name: String?, for ruleID: String) {
        alertShortcuts = shortcutStore.set(name, for: ruleID)
    }

    public func refreshShortcuts() async {
        guard let shortcutRunner else { return }
        if case .success(let names) = await shortcutRunner.list() {
            availableShortcuts = names
            shortcutsUnlisted = false
        } else {
            availableShortcuts = nil
            shortcutsUnlisted = true
        }
    }

    /// Tests keep their actions out of the person's preferences.
    func useShortcutStore(_ defaults: UserDefaults) {
        shortcutStore = AlertShortcuts(defaults: defaults)
        alertShortcuts = shortcutStore.all
    }

    /// Volume capacity changes slowly; read it once a minute, off the sampling path.
    private static let volumeReadInterval: TimeInterval = 60

    private func refreshStartupCapacity(now: Date) {
        guard let volumeReader, volumeRead == nil else { return }
        if let volumeReadAt, now.timeIntervalSince(volumeReadAt) < Self.volumeReadInterval { return }
        volumeReadAt = now
        volumeRead = Task { [weak self] in
            let fraction = await volumeReader.freeFraction()
            let volumes = await volumeReader.volumes()
            guard let self else { return }
            self.volumeRead = nil
            self.startupFreeFraction = fraction
            self.volumes = volumes
        }
    }

    /// Run a rule's Shortcut once per raise, never two of the same at once.
    private func runShortcut(for rule: AlertRule, at time: Date) {
        guard let shortcutRunner, let name = alertShortcuts[rule.id], !runningShortcuts.contains(rule.id),
              shortcutCooldown.admit(rule.id, at: time) else { return }
        runningShortcuts.insert(rule.id)
        Task { [weak self] in
            let result = await shortcutRunner.run(name)
            guard let self else { return }
            self.runningShortcuts.remove(rule.id)
            switch result {
            case .success:
                self.markers.append(TimelineMarker(time: Date(), label: "Ran Shortcut \(name)", kind: .alert))
            case .failure(let error):
                self.actionMessage = "Shortcut \(name) for “\(rule.title)” failed: \(error.description)"
                // The timeline keeps failures too; "why did nothing run?" is asked afterwards.
                self.markers.append(TimelineMarker(time: Date(), label: "Shortcut \(name) failed", kind: .alert))
            }
        }
    }

    /// Rules read live data, so a held display never delays an alert.
    private func evaluateAlerts() {
        let host = liveFrames.last
        let power = livePowerFrames.last
        refreshStartupCapacity(now: host?.stamp.wallTime ?? Date())
        let now = host?.stamp.wallTime ?? Date()
        // The person's rules read what history records, from a fresh source choice each time.
        var readings: [AlertMetric: Double] = [:]
        if !customAlertRules.isEmpty {
            var sources = RecordedSources()
            let samples = HistorySamples.latest(
                host: host, network: liveNetworkFrames.last, disks: liveDiskFrames.last, gpu: liveGPUFrames.last,
                power: power, sensors: liveSensorFrames.last, silicon: liveSiliconFrames.last, sources: &sources
            )
            readings = AlertReadings.latest(samples, now: now)
        }
        let inputs = AlertInputs(
            memoryPressure: host?.memory.pressureLevel,
            thermalPressure: host.flatMap { ThermalPressureLevel(reading: $0.thermalPressure) },
            batteryPercent: power?.batteryChargePercent.numericValue,
            onBattery: power?.powerSource.map { $0 == .battery },
            startupFreeFraction: startupFreeFraction,
            readings: readings
        )
        for event in alertEngine.evaluate(inputs, at: now) {
            guard event.kind == .raised, let rule = alertEngine.rules.first(where: { $0.id == event.ruleID }) else { continue }
            markers.append(TimelineMarker(time: event.time, label: rule.title, kind: .alert))
            runShortcut(for: rule, at: event.time)
            guard rule.notifies, let notifier, alertCooldown.admit(rule.id, at: event.time) else { continue }
            Task { await notifier.deliver(ruleID: rule.id, title: rule.title, body: "Open Coreography to see what is using it.") }
        }
        refreshActiveAlerts()
    }

    /// Freeze the displayed data for one diagnostic question.
    public func diagnosticSnapshot() -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            takenAt: displayedEndTime ?? Date(), host: frames, network: networkFrames, gpu: gpuFrames,
            power: powerFrames, sensors: sensorFrames, processes: processSnapshot, ledger: ledger,
            sleep: sleepState, assertions: assertionSnapshot, maintenance: maintenanceStatus, silicon: siliconFrames
        )
    }

    /// Run tmutil and mdutil off the sampling path when the last read is
    /// older than `age`; never two reads at once.
    private func refreshMaintenance(olderThan age: TimeInterval) {
        guard let maintenanceProvider, maintenanceRead == nil else { return }
        if let readAt = maintenanceStatus?.readAt, Date().timeIntervalSince(readAt) < age { return }
        maintenanceRead = Task { [weak self] in
            let status = await maintenanceProvider.load()
            guard let self else { return }
            self.maintenanceStatus = status
            self.maintenanceRead = nil
        }
    }

    /// Import sleep history once at start and again after each wake, when
    /// new records exist; never on the sampling path, never twice at once.
    private func importSleepHistory(after delay: Duration) {
        guard let sleepProvider, sleepImport == nil else { return }
        sleepImport = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
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
            self.refreshSystemMarkers()
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

    /// Show what an answer rests on: select its process, scope its app, or
    /// select its range. A PID is matched only to a process that started
    /// by the time the answer's snapshot was taken, never a later reuse.
    public func follow(_ evidence: AskEvidence) {
        switch evidence {
        case .app(let name):
            scopedApp = name
        case .range(let range):
            selection = range
        case .process(let pid):
            // A link from an answer no longer shown does nothing.
            guard case .answered(let answer) = askState else { return }
            guard let process = AskEvidence.process(pid, in: processSnapshot, askedAt: answer.takenAt) else {
                actionMessage = "PID \(pid) is no longer running"
                return
            }
            selectedProcessRow = ProcessGroups.rowID(process)
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

    public func actionRequest(for process: ObservedProcess, action: ProcessAction) -> ProcessActionRequest {
        ProcessActions.request(for: process, action: action, in: processSnapshot)
    }

    /// Send a confirmed request; the identity is re-checked at the last moment.
    public func perform(_ request: ProcessActionRequest) {
        if let refusal = request.refusal {
            actionMessage = "\(request.name): \(refusal)"
            return
        }
        let outcome: ProcessActionOutcome = switch request.action {
        case .quit: controller.terminate(request.target, mode: .graceful)
        case .forceQuit: controller.terminate(request.target, mode: .forced)
        case .suspend: controller.send(.suspend, to: request.target)
        case .resume: controller.send(.resume, to: request.target)
        case .hangUp: controller.send(.hangUp, to: request.target)
        case .interrupt: controller.send(.interrupt, to: request.target)
        case .user1: controller.send(.user1, to: request.target)
        case .user2: controller.send(.user2, to: request.target)
        case .info: controller.send(.info, to: request.target)
        case .lowerPriority: controller.lowerPriority(of: request.target)
        case .raisePriority: controller.raisePriority(of: request.target)
        }
        guard case .notPermitted(let reason) = outcome, controller.canAskHelper else {
            return finish(request, outcome, route: .direct)
        }

        // Another user's process, or a priority only root may raise: ask the
        // helper; without it, the refusal stands as it was.
        Task {
            let helped = await performThroughHelper(request)
            finish(request, helped ?? .failed(reason: reason), route: helped == nil ? .direct : .helper)
        }
    }

    private enum ActionRoute { case direct, helper }

    private func performThroughHelper(_ request: ProcessActionRequest) async -> ProcessActionOutcome? {
        switch request.action {
        case .quit: await controller.terminateThroughHelper(request.target, mode: .graceful)
        case .forceQuit: await controller.terminateThroughHelper(request.target, mode: .forced)
        case .suspend: await controller.sendThroughHelper(.suspend, to: request.target)
        case .resume: await controller.sendThroughHelper(.resume, to: request.target)
        case .hangUp: await controller.sendThroughHelper(.hangUp, to: request.target)
        case .interrupt: await controller.sendThroughHelper(.interrupt, to: request.target)
        case .user1: await controller.sendThroughHelper(.user1, to: request.target)
        case .user2: await controller.sendThroughHelper(.user2, to: request.target)
        case .info: await controller.sendThroughHelper(.info, to: request.target)
        case .lowerPriority: await controller.lowerPriorityThroughHelper(of: request.target)
        case .raisePriority: await controller.raisePriorityThroughHelper(of: request.target)
        }
    }

    private func finish(_ request: ProcessActionRequest, _ outcome: ProcessActionOutcome, route: ActionRoute) {
        switch outcome {
        case .requested:
            let verb = request.action.verb
            markers.append(TimelineMarker(time: Date(), label: "\(verb) \(request.name)", kind: .action))
            let through = route == .helper ? " through the privileged helper" : ""
            actionMessage = "\(verb) \(request.name) (PID \(request.target.pid)): requested\(through)"
        case .failed(let reason), .notPermitted(let reason):
            actionMessage = "\(request.name): \(reason)"
        }
    }

    /// Sample one process's call stacks with the system tool; the report opens in the app.
    public func sampleProcess(_ process: ObservedProcess) async {
        guard let sampler else { return }
        await capture(process, tool: .sample, seconds: ProcessSampler.defaultSeconds) {
            switch await sampler.sample(process) {
            case .success(let report): .finished(report)
            case .failure(let failure): .failed(name: process.name, tool: .sample, reason: failure.reason)
            }
        }
    }

    /// A spindump of one process through the privileged helper; the report opens in the app.
    public func spindumpProcess(_ process: ObservedProcess) async {
        guard let spindumper else { return }
        await capture(process, tool: .spindump, seconds: ProcessSpindumper.defaultSeconds) {
            switch await spindumper.spindump(process) {
            case .success(let report): .finished(report)
            case .failure(let failure): .failed(name: process.name, tool: .spindump, reason: failure.reason)
            case nil:
                .failed(
                    name: process.name,
                    tool: .spindump,
                    reason: "The privileged helper is not answering; install or approve it in Settings."
                )
            }
        }
    }

    /// Runs one report tool while the sheet shows progress; a second request
    /// while one runs is ignored, and a report for a dismissed run is dropped.
    private func capture(_ process: ObservedProcess, tool: ProcessReportTool, seconds: Int, _ run: () async -> SampleState) async {
        if case .running = sampleState { return }
        let token = UUID()
        sampleRun = token
        sampleState = .running(name: process.name, tool: tool, seconds: seconds)
        let outcome = await run()
        // Closed while it ran: the tool stops at its own time limit, and its report is dropped.
        guard sampleRun == token else { return }
        sampleState = outcome
    }

    /// Also closes a running sample, so the sheet's Close and Escape always work.
    public func dismissSample() {
        sampleRun = nil
        sampleState = .idle
    }

    /// One process as text or JSON, for the Copy commands.
    public func copyText(for process: ObservedProcess) -> String { ProcessActions.text(for: process) }
    public func copyJSON(for process: ObservedProcess) -> String { ProcessActions.json(for: process) }

    /// Coreography's own process cost, from the latest process sample.
    public var selfCost: SelfCost? {
        SelfCost.measure(in: processSnapshot, logicalCPUCount: latest?.inventory.logicalCPUCount, samplingSeconds: samplingSeconds)
    }

    /// Append the selected process's live readings; a gap starts a new segment.
    private func recordSelectedHistory(_ processes: CapturedProcesses, traffic: CapturedTraffic?) {
        guard let selectedProcessRow else { return }
        guard let process = processes.processes.first(where: { ProcessGroups.rowID($0) == selectedProcessRow }) else {
            // A sample that missed the process is a gap the line must not bridge.
            selectedHistorySegment += 1
            return
        }
        if processes.continuity != .continuous { selectedHistorySegment += 1 }
        refreshSelectedThreads(process)
        let disk = ProcessGroups.total([process.diskReadBytesPerSecond, process.diskWriteBytesPerSecond], overlap: nil)
        let network = ProcessNetwork.rates(for: process, in: traffic)
        selectedProcessHistory.append(ProcessHistoryPoint(
            id: UUID(), time: processes.stamp.wallTime, cpuPercent: process.cpuPercentOfMachine.numericValue,
            footprintBytes: process.memoryFootprintBytes.numericValue, diskBytesPerSecond: disk.numericValue,
            networkBytesPerSecond: ProcessNetwork.total(network.received, network.sent), segment: selectedHistorySegment
        ))
        if selectedProcessHistory.count > Self.contributorCapacity {
            selectedProcessHistory.removeFirst(selectedProcessHistory.count - Self.contributorCapacity)
        }
    }

    /// The names known now; UIDs not yet asked about are looked up in the
    /// background, and their groups read their UID until the names arrive.
    private func knownAccountNames() -> [UInt32: String] {
        let uids = Set((processSnapshot?.processes ?? []).map(\.uid))
        let unasked = uids.subtracting(accountsAsked)
        guard !unasked.isEmpty, accountLookup == nil else { return accountNames }
        accountsAsked.formUnion(unasked)
        let accounts = accounts
        let wanted = accountsAsked
        accountLookup = Task { [weak self] in
            let lookup = await Task.detached { accounts.lookup(wanted) }.value
            guard let self else { return }
            self.accountLookup = nil
            // A failed lookup is asked again on a later refresh, not pinned to its UID.
            self.accountsAsked.subtract(lookup.unanswered)
            if lookup.names != self.accountNames { self.accountNames = lookup.names }
        }
        return accountNames
    }

    /// Whether the table shows its signer column; checks start only then,
    /// and a batch already running finishes into the cache. Showing it again
    /// retries programs that could not be checked.
    public var showsSigners = false {
        didSet { if showsSigners, !oldValue { signersAsked = [] } }
    }

    /// Whether the table shows its ports column; connections are read while it does.
    public var showsPorts = false {
        didSet { if showsPorts, !oldValue { sampleConnections() } }
    }

    /// The signers known now; programs not yet checked are checked in the
    /// background, and their rows show no signer until the answers arrive.
    private func knownSigners() -> [String: CapturedSigner] {
        let paths = Set((processSnapshot?.processes ?? []).compactMap(\.executablePath))
        let unasked = paths.subtracting(signersAsked)
        guard !unasked.isEmpty, signerLookup == nil else { return signers }
        signersAsked.formUnion(unasked)
        let directory = signerDirectory
        signerLookup = Task { [weak self] in
            let found = await directory.signers(for: unasked)
            guard let self else { return }
            self.signerLookup = nil
            if !found.isEmpty { self.signers.merge(found) { _, checked in checked } }
        }
        return signers
    }

    /// Whole-machine CPU outside the readable processes over the displayed
    /// process interval: other users' processes, the kernel and processes
    /// too short-lived to sample. Nil where the two do not line up.
    public var unattributedCPUPercent: Double? {
        guard let processSnapshot else { return nil }
        // The interval spans a few host samples; the newest suffice.
        let host = frames.suffix(Self.attributionHostFrames).map { (time: $0.stamp.wallTime, cpu: $0.cpuPercentOfMachine) }
        return ProcessAttribution.unattributedCPU(
            host: host, processes: processSnapshot, interval: processSamplingSeconds
        )
    }

    /// TCP and UDP bytes per second macOS counted but tied to no process.
    public var unattributedNetworkBytesPerSecond: Double? {
        trafficSnapshot.flatMap {
            ProcessNetwork.total($0.unattributedReceivedBytesPerSecond, $0.unattributedSentBytesPerSecond)
        }
    }

    /// One process's TCP and UDP rates from the displayed traffic sample.
    public func networkRates(for process: ObservedProcess) -> (received: DashboardReading, sent: DashboardReading) {
        ProcessNetwork.rates(for: process, in: trafficSnapshot)
    }

    public var visibleProcessRows: [ProcessRow] {
        let time = processSnapshot?.stamp.wallTime ?? Date()
        let lifecycle = lifecycle
        let rows = ProcessGroups.rows(
            in: processSnapshot, matching: processFilter, sortedBy: processSort, grouping: processGrouping,
            isNew: { lifecycle.isNew($0, at: time) },
            facts: ProcessFacts(
                sockets: connectionSnapshot.map(SocketFacts.init), sleepPreventers: assertionSnapshot?.sleepPreventers,
                openFiles: openFileSnapshot?.files, traffic: trafficSnapshot, notResponding: notResponding,
                cpuFactor: processCPUFactor,
                // Only the by-user view and `user:<name>` need account names.
                accountNames: processGrouping == .user || ProcessFilter.parse(processFilter).usesAccountNames
                    ? knownAccountNames() : [:],
                signers: showsSigners ? knownSigners() : [:]
            )
        )
        let ranked = rangeRanked(rows)
        guard let scopedApp else { return ranked }
        return ProcessGroups.scoped(ranked, to: scopedApp)
    }

    /// With a selection, sorting by CPU ranks apps by their CPU-seconds
    /// inside it (plan P7: the pane re-ranks by usage inside the window).
    /// Only grouped rows: the ledger counts apps, not single processes.
    public var ranksBySelection: Bool { selection != nil && processSort == .cpu && processGrouping == .app }

    private func rangeRanked(_ rows: [ProcessRow]) -> [ProcessRow] {
        guard ranksBySelection, let report = rangeReport else { return rows }
        let cpu = Dictionary(report.apps.map { ($0.name, $0.cpuSeconds) }) { first, _ in first }
        return rows.enumerated().sorted { lhs, rhs in
            let left = cpu[lhs.element.appName] ?? 0
            let right = cpu[rhs.element.appName] ?? 0
            return left != right ? left > right : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Filter terms that were not applied, named for the person who typed them.
    public var processFilterIssues: [String] {
        let filter = ProcessFilter.parse(processFilter)
        var issues = filter.issues
        if filter.usesFiles {
            if let files = openFileSnapshot {
                if let reason = files.unavailableReason { issues.append("file: matches nothing: \(reason)") }
                if files.restrictedProcesses > 0 { issues.append("file: covers your own processes; other users' need the helper") }
                if files.failedProcesses > 0 { issues.append("file: could not read \(files.failedProcesses) of the processes") }
            } else {
                issues.append("file: is waiting for open-file data")
            }
        }
        if filter.usesAssertions {
            if let reason = assertionSnapshot?.unavailableReason { issues.append("#preventing-sleep matches nothing: \(reason)") }
            if assertionSnapshot == nil { issues.append("#preventing-sleep is waiting for power assertions") }
        }
        if filter.usesResponsiveness {
            if responsivenessMonitor == nil { issues.append("#not-responding is unavailable here") }
            else if notResponding == nil { issues.append("#not-responding is waiting for process samples") }
        }
        guard filter.usesSockets else { return issues }
        guard let connections = connectionSnapshot else { return issues + ["#listening and port: are waiting for connection data"] }
        if let reason = connections.unavailableReason { return issues + ["#listening and port: match nothing: \(reason)"] }
        guard connections.restrictedProcesses > 0 else { return issues }
        return issues + ["#listening and port: cover your own processes; other users' need the helper"]
    }

    /// The Connections tab's rows, by app, from displayed (possibly held) data.
    public var appConnections: [AppConnections] {
        guard let connectionSnapshot else { return [] }
        return ConnectionGroups.apps(
            in: connectionSnapshot, processes: processSnapshot, matching: connectionFilter, serverNames: serverNames
        )
    }

    private var wantsOpenFiles: Bool { ProcessFilter.parse(processFilter).usesFiles }

    /// The probe runs only while a filter term needs it; kept streaks reset.
    private var wantsResponsiveness: Bool {
        responsivenessMonitor != nil && ProcessFilter.parse(processFilter).usesResponsiveness
    }

    /// One read of every process's open files, off the sampling loop and never two at once.
    private func sampleOpenFiles() {
        guard let openFileMonitor, let processes = liveProcesses, openFileSample == nil else { return }
        openFileSample = Task { [weak self] in
            let snapshot = await openFileMonitor.sample(processes)
            guard let self, !Task.isCancelled else { return }
            self.openFileSample = nil
            self.liveOpenFiles = snapshot
            if self.displayMode == .live { self.openFileSnapshot = snapshot }
        }
    }

    private var wantsConnections: Bool {
        detailPane == .connections || showsPorts || ProcessFilter.parse(processFilter).usesSockets
    }

    /// Apply a link or Shortcut command (plan: automation); returns, and
    /// shows, why it could not be applied. Showing the window and the HUD
    /// belongs to the app.
    @discardableResult
    public func perform(_ command: AutomationCommand) async -> String? {
        let failure: String?
        switch command {
        case .show, .toggleHUD:
            failure = nil
        case .filter(let text):
            detailPane = .processes
            processFilter = text
            failure = nil
        case .selectProcess(let pid):
            if let process = processSnapshot?.processes.first(where: { $0.id.pid == pid }) {
                detailPane = .processes
                selectedProcessRow = ProcessGroups.rowID(process)
                failure = nil
            } else {
                failure = "No observed process has PID \(pid)"
            }
        case .range(let range):
            timeRange = range
            failure = nil
        case .startRecording(let name):
            failure = sessionRecording == nil ? nil : "A session is already recording"
            if failure == nil { startRecording(name: name) }
        case .stopRecording:
            failure = sessionRecording == nil ? "No session is recording" : await stopRecording()
        }
        if let failure { actionMessage = failure }
        return failure
    }

    /// The command palette (plan: Command-Shift-P).
    public var paletteShown = false
    /// The named-marker prompt (plan: M drops a named marker).
    public var markerPromptShown = false
    /// The range inspector asks for an annotation's name.
    public var annotationPromptShown = false
    /// Text fields in the window taking typing now, so plain-letter shortcuts stand aside.
    public private(set) var typingFields: Set<String> = []

    public func setTyping(_ field: String, _ typing: Bool) {
        if typing { typingFields.insert(field) } else { typingFields.remove(field) }
    }

    /// When the newest live sample arrived, held display or not; surfaces
    /// that always show live data (the Dock graph) redraw on it.
    public private(set) var liveSampleTime: Date?

    /// Per-process CPU in whole-machine shares or one core = 100 %; saved.
    public var processCPUScale = ProcessCPUScale.saved() {
        didSet { if processCPUScale != oldValue { processCPUScale.save() } }
    }

    /// The multiplier from a process's whole-machine share to the chosen scale.
    public var processCPUFactor: Double { processCPUScaleInEffect.factor(logicalCPUs: latest?.inventory.logicalCPUCount ?? 1) }

    /// The scale the numbers are in: one core needs the core count, so the
    /// whole machine stands in until a host sample names it.
    public var processCPUScaleInEffect: ProcessCPUScale { latest == nil ? .machine : processCPUScale }

    /// Lane order, hidden lanes and sizes; saved as they change.
    public var laneLayout = LaneLayout.saved() {
        didSet { if laneLayout != oldValue { laneLayout.save() } }
    }

    /// The menu bar extra's items; saved, at most three.
    public var menuBarItems = MenuBarLayout.saved() {
        didSet {
            let normalized = MenuBarLayout.normalized(menuBarItems)
            if normalized != menuBarItems { menuBarItems = normalized; return }
            if menuBarItems != oldValue { MenuBarLayout.save(menuBarItems) }
        }
    }

    /// One menu bar item's current value: displayed, so a held window holds it too.
    public func menuBarValue(_ metric: MenuBarMetric) -> DashboardReading? {
        switch metric {
        case .cpu: reading(for: .cpu)
        case .memory: reading(for: .memory)
        case .gpu: menuBarGPU?.utilizationPercent
        case .download: reading(for: .networkReceived)
        case .upload: reading(for: .networkSent)
        case .temperature: displayedSensorFrame?.hottest?.celsius
        }
    }

    /// The last minute of one item's series, for its sparkline.
    public func menuBarPoints(_ metric: MenuBarMetric) -> [DashboardPoint] {
        let series: [DashboardPoint] = switch metric {
        case .cpu: points(for: .cpu)
        case .memory: points(for: .memory)
        case .gpu: gpuSeries().first { $0.id == menuBarGPU?.id }?.points ?? []
        case .download: points(for: .networkReceived)
        case .upload: points(for: .networkSent)
        case .temperature: hottestTemperaturePoints()
        }
        guard let end = series.last?.time else { return [] }
        let start = end.addingTimeInterval(-Self.menuBarSeconds)
        return series.filter { $0.time >= start }
    }
    private static let menuBarSeconds: TimeInterval = 60

    /// The busiest displayed GPU, which both the value and its graph describe.
    private var menuBarGPU: CapturedGPUDevice? {
        displayedGPUFrame?.devices.max { ($0.utilizationPercent.numericValue ?? -1) < ($1.utilizationPercent.numericValue ?? -1) }
    }

    /// What the Dock icon shows; saved.
    public var dockIcon = DockIconStyle.saved() {
        didSet { if dockIcon != oldValue { dockIcon.save() } }
    }

    /// The Dock graph's last minute of live samples, even while the window is held;
    /// missing readings and interruptions start new segments.
    public var dockIconPoints: [DashboardPoint] {
        guard let metric = dockIcon.metric, liveSampleTime != nil, let end = liveFrames.last?.stamp.wallTime else { return [] }
        let start = end.addingTimeInterval(-Self.dockIconSeconds)
        var segment = 0
        var result: [DashboardPoint] = []
        for frame in liveFrames {
            if frame.continuity == .interrupted { segment += 1 }
            let reading = metric == .cpu ? frame.cpuPercentOfMachine : frame.memoryUsedBytes
            guard let value = reading.numericValue else {
                segment += 1
                continue
            }
            guard frame.stamp.wallTime >= start else { continue }
            result.append(DashboardPoint(id: frame.id, time: frame.stamp.wallTime, value: value, segment: segment))
        }
        return result
    }

    /// The Dock graph's fixed top: the whole machine for CPU, physical memory for memory.
    public var dockIconScale: Double? {
        switch dockIcon {
        case .appIcon: nil
        case .cpu: 100
        case .memory: liveFrames.last.map { Double($0.inventory.physicalMemoryBytes) }
        }
    }
    private static let dockIconSeconds: TimeInterval = 60

    /// Every action by name, with why each unavailable one cannot run now.
    public var paletteEntries: [PaletteEntry] {
        func entry(_ title: String, _ action: PaletteAction, unavailable reason: String? = nil) -> PaletteEntry {
            PaletteEntry(title: title, action: action, unavailableReason: reason)
        }
        var entries = [
            entry(inspectorShown ? "Hide Inspector" : "Show Inspector", .toggleInspector),
            entry(displayMode == .live ? "Hold Display" : "Return to Live", .toggleHold),
            sessionRecording == nil ? entry("Start Recording", .startRecording) : entry("Stop Recording", .stopRecording),
            entry(samplingPaused ? "Resume Recording" : "Pause Recording", .toggleSampling),
            entry("Return to Now", .returnToNow),
            entry("Add Marker…", .addMarker),
            entry("Toggle HUD", .toggleHUD),
            entry("Open Settings", .openSettings)
        ]
        entries += TimeRange.allCases.map { entry(CommandPalette.rangeTitle($0), .range($0)) }
        entries += DetailPane.allCases.map { entry(CommandPalette.paneTitle($0), .pane($0)) }
        entries += [
            entry("Group Processes by App", .grouping(.app)), entry("Show Processes as a Tree", .grouping(.tree)),
            entry("Show Processes Ungrouped", .grouping(.flat)), entry("Group Processes by User", .grouping(.user))
        ]
        entries += ProcessSort.allCases.map { entry(CommandPalette.sortTitle($0), .sort($0)) }
        entries += CommandPalette.filterPresets.map { entry($0.title, .filter($0.filter)) }
        entries += savedFilters.map { entry("Saved Filter: \($0)", .filter($0)) }

        let filter = processFilter.trimmingCharacters(in: .whitespaces)
        entries += [
            entry("Clear Filter", .clearFilter, unavailable: filter.isEmpty ? "No filter is set" : nil),
            entry("Save Filter", .saveFilter, unavailable: filter.isEmpty ? "No filter is set" : savedFilters.contains(filter) ? "Already saved" : nil),
            entry("Clear App Scope", .clearScope, unavailable: scopedApp == nil ? "No app is scoped" : nil),
            entry("Clear Range Selection", .clearSelection, unavailable: selection == nil ? "No range is selected" : nil),
            entry("Reset Sensor Statistics", .resetSensorStats),
            entry("Refresh Startup Items", .refreshStartup)
        ]

        // Process actions name their target, so the palette never acts on a surprise.
        let selected = selectedProcess
        let noSelection = selected == nil ? "Select a process first" : nil
        let name = selected?.name ?? "Selected Process"
        let actions: [ProcessAction] = [.quit, .forceQuit, .suspend, .resume, .hangUp, .interrupt, .user1, .user2, .info, .lowerPriority, .raisePriority]
        entries += actions.map { entry(CommandPalette.processTitle($0, name), .processAction($0), unavailable: noSelection) }
        entries += [
            entry("Sample \(name) for \(SampleTool.defaultSeconds) Seconds", .sampleSelected, unavailable: noSelection ?? (sampler == nil ? "Sampling is not available here" : nil)),
            entry("Spindump \(name) for \(SpindumpTool.defaultSeconds) Seconds", .spindumpSelected, unavailable: noSelection ?? (spindumper == nil ? "Spindump is not available here" : nil)),
            entry("Copy \(name) as Text", .copySelected, unavailable: noSelection)
        ]
        return entries
    }

    /// Run a palette action the model owns. Confirmations, windows, the
    /// HUD and the pasteboard belong to the app, which handles those first.
    public func run(_ action: PaletteAction) async {
        switch action {
        case .toggleInspector: inspectorShown.toggle()
        case .toggleHold: toggleDisplayHold()
        case .toggleSampling: samplingPaused ? resumeSampling() : pauseSampling()
        case .returnToNow: returnToNow()
        case .startRecording: startRecording()
        case .stopRecording: await stopRecording()
        case .range(let range): timeRange = range
        case .pane(let pane): detailPane = pane
        case .grouping(let grouping): processGrouping = grouping
        case .sort(let sort): processSort = sort
        case .filter(let text):
            detailPane = .processes
            processFilter = text
        case .clearFilter: processFilter = ""
        case .saveFilter: saveProcessFilter()
        case .clearScope: scopedApp = nil
        case .clearSelection: clearSelection()
        case .resetSensorStats: resetSensorStats()
        case .refreshStartup: refreshStartupItems()
        case .sampleSelected:
            if let process = selectedProcess { await sampleProcess(process) }
        case .spindumpSelected:
            if let process = selectedProcess { await spindumpProcess(process) }
        case .processAction(.resume):
            if let process = selectedProcess { perform(actionRequest(for: process, action: .resume)) }
        case .processAction, .copySelected, .toggleHUD, .openSettings, .addMarker:
            break
        }
    }

    /// Parse and apply a `coreography://` link; a refusal is shown. Returns
    /// the command, so the app can show its window or the HUD.
    public func open(_ url: URL) async -> AutomationCommand? {
        switch AutomationLink.command(from: url) {
        case .success(let command):
            await perform(command)
            return command
        case .failure(let error):
            actionMessage = error.message
            return nil
        }
    }

    /// Who holds a port now: one socket read over the latest process sample.
    public func holders(ofPort port: UInt16) async -> HolderLookup {
        guard let connectionMonitor else { return HolderLookup(holders: [], limitations: ["Connections are not read here"]) }
        guard let processes = liveProcesses else { return HolderLookup(holders: [], limitations: ["Waiting for the first process sample"]) }
        return HolderLookups.port(port, in: processes, connections: await connectionMonitor.sample(processes))
    }

    /// Who has a file open now whose path contains `text`; `~` is the home folder.
    public func holders(ofFile text: String) async -> HolderLookup {
        guard let openFileMonitor else { return HolderLookup(holders: [], limitations: ["Open files are not read here"]) }
        guard let processes = liveProcesses else { return HolderLookup(holders: [], limitations: ["Waiting for the first process sample"]) }
        let files = await openFileMonitor.sample(processes)
        return HolderLookups.file(ProcessFilter.expandingHome(text), in: processes, files: files)
    }

    /// One read of every process's sockets, off the sampling loop and never
    /// two at once; a pass covers hundreds of processes.
    private func sampleConnections() {
        guard let connectionMonitor, let processes = liveProcesses, connectionSample == nil else { return }
        connectionSample = Task { [weak self] in
            let snapshot = await connectionMonitor.sample(processes)
            guard let self, !Task.isCancelled else { return }
            self.connectionSample = nil
            self.liveConnections = snapshot
            if self.displayMode == .live { self.connectionSnapshot = snapshot }
            if let displayed = self.connectionSnapshot { self.resolveServerNames(of: displayed) }
        }
    }

    /// Peers' names fill in behind the table; one batch at a time, only
    /// while the Connections pane shows.
    private func resolveServerNames(of snapshot: CapturedConnections) {
        guard detailPane == .connections, let serverNameResolver, serverNameTask == nil else { return }
        let addresses = snapshot.connections.compactMap { $0.remote?.address }
        serverNameTask = Task { [weak self] in
            let names = await serverNameResolver.resolve(addresses)
            guard let self, !Task.isCancelled else { return }
            self.serverNameTask = nil
            self.serverNames = names
        }
    }

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

    /// The scoped app's network rate now; nil when not read lately.
    public var scopedNetworkRate: Double? { scopedSeries().flatMap(AppLedger.currentNetworkRate) }

    /// The scoped app's memory or GPU reading in the displayed process
    /// sample; nil without a scoped app or when the sample lacks it.
    public func scopedAppReading(_ metric: ScopedMetric) -> ScopedAppReading? {
        guard let scopedApp, let processSnapshot else { return nil }

        // Lanes ask on every redraw, cursor moves included; group once per sample and app.
        if let cache = scopedReadingCache, cache.app == scopedApp, cache.stamp == processSnapshot.stamp {
            return cache.readings[metric]
        }
        let readings = ScopedApp.readings(of: scopedApp, in: processSnapshot)
        scopedReadingCache = (app: scopedApp, stamp: processSnapshot.stamp, readings: readings)
        return readings[metric]
    }

    /// The scoped app's CPU share and disk rate from the ledger, for lane
    /// overlays; on the 6 h range, stored intervals come first.
    public func scopedSeries() -> (cpu: [DashboardPoint], disk: [DashboardPoint], network: [DashboardPoint])? {
        guard let scopedApp else { return nil }
        let live = ledger.series(for: scopedApp)
        guard let stored = storedScopedSeries(scopedApp) else { return live }
        let liveStart = ledger.intervals.first?.end
        return (
            prefixed(live.cpu, stored: stored.cpu, liveStart: liveStart),
            prefixed(live.disk, stored: stored.disk, liveStart: liveStart),
            prefixed(live.network, stored: stored.network, liveStart: liveStart)
        )
    }

    /// Built and reduced once per load and app: the stored ledger holds up
    /// to six hours of intervals, too many to walk on every redraw.
    private func storedScopedSeries(_ app: String) -> (cpu: [DashboardPoint], disk: [DashboardPoint], network: [DashboardPoint])? {
        guard let storedHistory else { return nil }
        // Keyed on the whole window: the reduction depends on its start as well as its end.
        let window = storedHistory.start...storedHistory.end
        if let cache = storedScopedCache, cache.app == app, cache.window == window { return cache.series }
        let series = storedHistory.ledger.series(for: app)
        func reduce(_ points: [DashboardPoint]) -> [DashboardPoint] {
            Decimation.points(points, start: storedHistory.start, end: storedHistory.end)
        }
        let reduced = (cpu: reduce(series.cpu), disk: reduce(series.disk), network: reduce(series.network))
        storedScopedCache = (app: app, window: window, series: reduced)
        return reduced
    }

    /// Does nothing while the person has paused recording.
    public func start() {
        guard worker == nil, !samplingPaused, let monitor else { return }
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
        let siliconMonitor = siliconMonitor
        let trafficMonitor = trafficMonitor
        let assertionReader = assertionReader
        let energyMode = energyMode

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
            await siliconMonitor?.reset()
            await trafficMonitor?.reset()
            var nextProcessSample = ContinuousClock.now
            while !Task.isCancelled {
                // Low Power Mode halves every cadence (plan: sampling); the window says so.
                let cadence: SamplingCadence = energyMode?.current() == .lowPower ? .lowPower : .normal
                let pace = (self?.samplingRate ?? .oneSecond).multiplier(with: cadence)
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
                    var temperatures: [CapturedTemperature] = []
                    if let sensorMonitor {
                        _ = try await sensorMonitor.sample()
                        sensors = await sensorMonitor.history()
                        temperatures = await sensorMonitor.temperatures()
                    }
                    var silicon: [CapturedSilicon]?
                    if let siliconMonitor {
                        _ = try await siliconMonitor.sample()
                        silicon = await siliconMonitor.history()
                    }
                    var processes: CapturedProcesses?
                    var assertions: CapturedAssertions?
                    var traffic: CapturedTraffic?
                    if let processMonitor, ContinuousClock.now >= nextProcessSample {
                        processes = try await processMonitor.sample()
                        // Read right after processes, so PIDs and names describe the same moment.
                        traffic = try await trafficMonitor?.sample()
                        // One call to powerd; read beside processes so PIDs match the same moment.
                        assertions = await assertionReader?.read()
                        nextProcessSample = ContinuousClock.now.advanced(by: processInterval * pace)
                    }
                    guard let self, self.generation == run, !Task.isCancelled else { return }
                    if self.samplingCadence != cadence { self.samplingCadence = cadence }
                    self.liveFrames = history
                    self.liveSampleTime = history.last?.stamp.wallTime
                    // An interrupted sample usually follows a wake; powerd may still be writing its record.
                    if history.last?.continuity == .interrupted, self.wakeImports.admit(at: Date()) {
                        self.importSleepHistory(after: Self.wakeSettleDelay)
                    }
                    if let processes {
                        self.liveProcesses = processes
                        self.liveContributorHistory.append(Contributors.snapshot(from: processes, traffic: traffic))
                        self.liveContributorHistory = Array(self.liveContributorHistory.suffix(Self.contributorCapacity))
                        let interval = self.liveLedger.record(
                            processes, traffic: traffic, logicalCPUCount: history.last?.inventory.logicalCPUCount
                        )
                        if let interval, let recorder = self.historyRecorder { self.enqueueRecord { await recorder.recordLedger(interval) } }
                        if let interval { self.sessionRecording?.record(interval) }
                        // Drain before watching: exits that happened since
                        // the last sample join the ghosts this record makes.
                        self.liveLifecycle.record(processes, exits: self.exitWatcher?.drain() ?? [:])
                        self.exitWatcher?.watch(Set(processes.processes.map(\.id)))
                        if self.wantsResponsiveness { self.responsivenessMonitor?.record(processes.processes) }
                        else { self.responsivenessMonitor?.reset() }
                        self.recordSelectedHistory(processes, traffic: traffic)
                        if self.wantsConnections { self.sampleConnections() }
                        if self.wantsOpenFiles { self.sampleOpenFiles() }
                    }
                    if let assertions { self.liveAssertions = assertions }
                    if let traffic { self.liveTraffic = traffic }
                    if let network { self.liveNetworkFrames = network }
                    if let disks { self.liveDiskFrames = disks }
                    if let gpus { self.liveGPUFrames = gpus }
                    if let power { self.livePowerFrames = power }
                    if let silicon { self.liveSiliconFrames = silicon }
                    if let sensors {
                        self.liveSensorFrames = sensors
                        self.sensorStats.record(
                            temperatures: temperatures, sensors: sensors.last, at: sensors.last?.stamp.wallTime ?? Date()
                        )
                        if self.displayMode == .live, self.detailPane == .sensors { self.publishSensorStats() }
                    }
                    self.evaluateAlerts()
                    self.refreshMaintenance(olderThan: Self.maintenanceRefreshAge)
                    self.recordHistory()
                    if self.timeRange.reachesStoredHistory, self.recordsHistory { self.refreshStoredHistory() }
                    if self.displayMode == .live {
                        self.frames = history
                        if let assertions { self.assertionSnapshot = assertions }
                        if let traffic { self.trafficSnapshot = traffic }
                        if let processes {
                            self.processSnapshot = processes
                            self.contributorHistory = self.liveContributorHistory
                            self.ledger = self.liveLedger
                            self.lifecycle = self.liveLifecycle
                            self.notResponding = self.wantsResponsiveness ? self.responsivenessMonitor?.notResponding : nil
                        }
                        if let network { self.networkFrames = network }
                        if let disks { self.diskFrames = disks }
                        if let gpus { self.gpuFrames = gpus }
                        if let power { self.powerFrames = power }
                        if let sensors { self.sensorFrames = sensors }
                        if let silicon { self.siliconFrames = silicon }
                        self.refreshSystemMarkers()
                    }
                    try await Task.sleep(for: self.interval * pace)
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

    /// How fast sampling runs now; Low Power Mode halves it.
    public private(set) var samplingCadence: SamplingCadence = .normal

    /// The person's choice; the next sample follows it.
    public var samplingRate = SamplingRate.saved() {
        didSet { samplingRate.save() }
    }

    /// Seconds between whole-machine samples at the current cadence.
    public var samplingSeconds: Double { Self.seconds(interval * samplingRate.multiplier(with: samplingCadence)) }

    /// Seconds between process samples at the current cadence.
    public var processSamplingSeconds: Double { Self.seconds(processInterval * samplingRate.multiplier(with: samplingCadence)) }

    /// How far back the selected process's history reaches at the current cadence.
    public var selectedHistorySpan: TimeInterval { Double(Self.contributorCapacity) * processSamplingSeconds }

    private static func seconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / attosecondsPerSecond
    }
    private static let attosecondsPerSecond = 1e18

    /// Sampling stopped by the person (plan: Pause Recording stops sampling and
    /// leaves a labelled gap in every series; Hold only freezes the display).
    public private(set) var samplingPaused = false
    /// A marker name longer than this is not a name.
    static let maximumMarkerLength = 120

    public func pauseSampling() {
        guard !samplingPaused else { return }
        markers.append(TimelineMarker(time: Date(), label: "Recording paused", kind: .note))
        samplingPaused = true
        stop()
    }

    public func resumeSampling() {
        guard samplingPaused else { return }
        samplingPaused = false
        markers.append(TimelineMarker(time: Date(), label: "Recording resumed", kind: .note))
        start()
    }

    /// Command-0: back to the live edge, without changing the range or selection.
    public func returnToNow() {
        if displayMode == .held { toggleDisplayHold() }
        cursorTime = nil
    }

    /// M: a named marker at the live edge; a blank name becomes the time.
    public func addMarker(named name: String, at time: Date = Date()) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumMarkerLength))
        let label = trimmed.isEmpty ? "Marker \(time.formatted(date: .omitted, time: .standard))" : trimmed
        appendOwnMarker(TimelineMarker(time: time, label: label, kind: .note))
    }

    /// A marker made while a recording is open belongs to the replay, which is what shows.
    private func appendOwnMarker(_ marker: TimelineMarker) {
        if openRecording == nil { markers.append(marker) } else { recordingMarkers.append(marker) }
    }

    /// Plan: Annotate a time range. Its name marks where the range starts,
    /// and "End of" the name where it ends, on every lane.
    public func annotateSelection(named name: String) {
        guard let selection else { return }
        addMarker(named: name, at: selection.lowerBound)
        guard selection.upperBound > selection.lowerBound, let start = ownMarkers.last else { return }
        let end = String("End of \(start.label)".prefix(Self.maximumMarkerLength))
        appendOwnMarker(TimelineMarker(time: selection.upperBound, label: end, kind: .note))
    }

    public func stop() {
        halt()
        if let historyRecorder { Task { await historyRecorder.flush() } }
    }

    /// Stops sampling and returns once buffered history is on disk, so
    /// quitting does not lose the seconds since the last write.
    public func stopForQuit() async {
        halt()
        // Records still on their way to the recorder go into this last write.
        await lastRecord?.value
        await historyRecorder?.flush()
    }

    private func halt() {
        generation = UUID()
        worker?.cancel()
        worker = nil
    }

    public func toggleDisplayHold() {
        if displayMode == .live {
            displayMode = .held
            return
        }
        displayMode = .live
        panOffset = 0
        let hadRecording = openRecording != nil
        openRecording = nil
        recordingOpening = nil
        recordingMarkers = []
        // A recording's stored part leaves with it; live-loaded history stays.
        if hadRecording { dropStoredHistory() }
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
        siliconFrames = liveSiliconFrames
        connectionSnapshot = liveConnections
        assertionSnapshot = liveAssertions
        trafficSnapshot = liveTraffic
        openFileSnapshot = liveOpenFiles
        if detailPane == .sensors { publishSensorStats() }
        refreshSystemMarkers()
    }

    /// Rebuilt from displayed frames: a held display keeps its markers, and
    /// the 6 h range shows sleep and wake back to its stored start. App
    /// starts and exits are live only: a recording keeps no process list.
    private func refreshSystemMarkers() {
        let sleepEvents: [PowerEvent] = if case .imported(let history) = sleepState { history.events } else { [] }
        systemMarkers = AutomaticMarkers.derive(
            host: frames, power: powerFrames, sleepEvents: sleepEvents,
            appEvents: openRecording == nil ? lifecycle.appEvents : [], since: storedHistory?.start
        )
    }

    /// The Startup tab's rows, joined to displayed (possibly held) process data.
    public var startupRows: [StartupRow] {
        guard let startupInventory else { return [] }
        return StartupRows.rows(
            startupInventory, processes: processSnapshot, ledger: ledger,
            now: processSnapshot?.stamp.wallTime ?? Date(), visibility: startupVisibility
        )
    }

    /// The selected process as it now stands; nil for a group row, or once it exited.
    public var selectedProcess: ObservedProcess? {
        guard let selectedProcessRow, let processSnapshot else { return nil }
        return processSnapshot.processes.first { ProcessGroups.rowID($0) == selectedProcessRow }
    }

    /// Identity, parent chain, signature, arguments and sockets of the selected process.
    public var processInspection: ProcessInspection? {
        guard let process = selectedProcess, let processSnapshot else { return nil }
        return ProcessInspections.make(
            process, in: processSnapshot, startup: startupInventory, detail: processDetail, sockets: inspectedSockets,
            maintenance: maintenanceStatus
        )
    }

    /// Start a named session; a blank name becomes the start time.
    public func startRecording(name: String = "") {
        guard sessionRecording == nil else { return }
        let start = Date()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "Session \(start.formatted(date: .abbreviated, time: .shortened))" : trimmed
        sessionRecording = SessionRecording(name: label, start: start)
    }

    /// Stop, report and save the session; returns why saving failed, if it did.
    @discardableResult
    public func stopRecording() async -> String? {
        guard let recording = sessionRecording else { return nil }
        sessionRecording = nil
        let session = recording.finish(at: Date())
        // The message also goes to the window: a toolbar button has nowhere else to show it.
        guard let sessionArchive else {
            sessions.insert(session, at: 0)
            actionMessage = "Sessions cannot be saved on this Mac; this one lasts until Coreography quits."
            return actionMessage
        }
        do {
            try await sessionArchive.save(session)
        } catch {
            sessions.insert(session, at: 0)
            actionMessage = "The session could not be saved: \(error)"
            return actionMessage
        }
        await refreshSessions()
        return nil
    }

    public func refreshSessions() async {
        guard let sessionArchive else { return }
        sessions = await sessionArchive.all()
    }

    /// A new name is saved with the session; a blank one is ignored.
    public func renameSession(_ id: UUID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].name = trimmed
        do {
            try await sessionArchive?.save(sessions[index])
        } catch {
            actionMessage = "The new name could not be saved and lasts until Coreography quits: \(error)"
        }
    }

    /// Sessions picked for comparison; picking a third drops the oldest pick.
    public private(set) var comparedSessions: [UUID] = []

    public func toggleComparison(_ id: UUID) {
        if let index = comparedSessions.firstIndex(of: id) {
            comparedSessions.remove(at: index)
            return
        }
        comparedSessions = Array((comparedSessions + [id]).suffix(2))
    }

    /// The two picked sessions overlaid, aligned at their starts.
    public var sessionComparison: SessionComparison? {
        let picked = comparedSessions.compactMap { id in sessions.first { $0.id == id } }
        guard picked.count == 2 else { return nil }
        return SessionComparison.make(picked[0], picked[1])
    }

    public func deleteSession(_ id: UUID) async {
        do {
            try await sessionArchive?.delete(id)
        } catch {
            // Still on disk: the row and its comparison pick stay, so the list does not lie until the next refresh.
            actionMessage = "The session could not be deleted: \(error)"
            return
        }
        comparedSessions.removeAll { $0 == id }
        sessions.removeAll { $0.id == id }
    }

    public func saveProcessFilter() { savedFilters = filterStore.save(processFilter) }

    /// Blank by the store's own test, so the button never offers a save that does nothing.
    public var canSaveProcessFilter: Bool { !SavedFilters.isBlank(processFilter) }

    public func removeSavedFilter(_ filter: String) { savedFilters = filterStore.remove(filter) }

    /// Tests keep their chips out of the person's preferences.
    func useFilterStore(_ defaults: UserDefaults) {
        filterStore = SavedFilters(defaults: defaults)
        savedFilters = filterStore.all
    }

    /// Who holds the Mac or its display awake now (plan P2), joined to the
    /// displayed process names; longest-held first.
    public var sleepPreventers: [AssertionHolder] {
        guard let assertionSnapshot else { return [] }
        let names = Dictionary((processSnapshot?.processes ?? []).map { ($0.id.pid, $0.name) }) { first, _ in first }
        return assertionSnapshot.assertions
            .filter { $0.effect != .other }
            .map { AssertionHolder(assertion: $0, processName: names[$0.pid]) }
            .sorted { ($0.assertion.since ?? .distantFuture) < ($1.assertion.since ?? .distantFuture) }
    }

    /// The selected process's assertions, for the inspector.
    public var selectedAssertions: [CapturedAssertion] {
        guard let process = selectedProcess else { return [] }
        return assertionSnapshot?.assertions.filter { $0.pid == process.id.pid } ?? []
    }

    /// The inspector's summary when nothing is selected.
    public func systemFacts() -> CapturedSystemFacts { SystemFacts.read() }

    /// Reread the inspected process's thread count with each process sample;
    /// a read still running skips this one.
    private func refreshSelectedThreads(_ process: ObservedProcess) {
        guard threadRead == nil, let inspector, processDetail?.process == process.id else { return }
        threadRead = Task { [weak self] in
            let read = await inspector.threads(of: process)
            // A cancelled read's handle was already cleared, and may now belong to a newer read.
            guard let self, !Task.isCancelled else { return }
            self.threadRead = nil
            guard self.processDetail?.process == process.id else { return }
            self.processDetail?.threads = read.count
            self.processDetail?.threadsProblem = read.problem
        }
    }

    /// Read the selected process's detail once per selection, off the main actor.
    private func inspectSelection() {
        inspection?.cancel()
        threadRead?.cancel()
        threadRead = nil
        processDetail = nil
        inspectedSockets = nil
        inspectedFiles = nil
        inspectedFilesCut = false
        guard let process = selectedProcess, let inspector else { return }
        if MaintenanceWork.of(process) != nil { refreshMaintenance(olderThan: Self.maintenanceSelectionAge) }
        let connectionMonitor = connectionMonitor
        let openFileMonitor = openFileMonitor
        inspection = Task { [weak self] in
            async let detail = inspector.detail(of: process)
            async let sockets = connectionMonitor?.connections(of: process)
            async let files = openFileMonitor?.files(of: process)
            let (readDetail, readSockets, readFiles) = await (detail, sockets, files)
            guard let self, !Task.isCancelled else { return }
            self.processDetail = readDetail
            self.inspectedSockets = readSockets.flatMap { $0 }
            self.inspectedFiles = readFiles.flatMap { $0 }?.paths
            self.inspectedFilesCut = readFiles.flatMap { $0 }?.isComplete == false
        }
        if startupInventory == nil { refreshStartupItems() }
    }

    /// Reread startup definitions and launchd's enable state; never two reads at once.
    public func refreshStartupItems() {
        guard let startupProvider, startupLoad == nil else { return }
        startupLoad = Task { [weak self] in
            let inventory = await startupProvider.load()
            guard let self, !Task.isCancelled else { return }
            self.startupLoad = nil
            self.startupInventory = inventory
        }
    }

    /// Start the Sensors tab's statistics over (plan P15).
    public func resetSensorStats() {
        sensorStats.reset()
        publishSensorStats()
    }

    /// Rows change only while the Sensors tab shows, so a hidden tab costs no redraws.
    private func publishSensorStats() {
        sensorRows = sensorStats.rows()
        sensorStatsSince = sensorStats.since
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

    /// Efficiency- and performance-cluster activity for the CPU lane's
    /// detail, stored behind live as the lanes are. Every point is an
    /// IOReport residency estimate; missing kinds and dropped frames break
    /// segments rather than bridge them.
    public func clusterActivityPoints() -> (efficiency: [DashboardPoint], performance: [DashboardPoint]) {
        let liveStart = siliconFrames.first?.stamp.wallTime
        return (
            prefixed(
                liveClusterPoints(kind: .e), stored: storedHistory?.lines[.efficiencyClusterActivePercent],
                liveStart: liveStart
            ),
            prefixed(
                liveClusterPoints(kind: .p), stored: storedHistory?.lines[.performanceClusterActivePercent],
                liveStart: liveStart
            )
        )
    }

    /// One point per frame per tier kind, folded like the stored series.
    private func liveClusterPoints(kind: CPUTierKind) -> [DashboardPoint] {
        var result: [DashboardPoint] = []
        var segment = 0
        for frame in siliconFrames {
            if frame.continuity == .interrupted { segment += 1 }
            guard let value = HistorySamples.clusterMean(frame.cpuTiers, kind: kind, \.activePercent)?.numericValue
            else {
                segment += 1
                continue
            }
            result.append(DashboardPoint(id: frame.id, time: frame.stamp.wallTime, value: value, segment: segment))
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

    /// The recorder stores a gap where the hottest sensor changed, so both parts break there.
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

    /// Every interface's received and sent rates in the shown range, for
    /// the network lane's detail (plan: per-interface small multiples).
    public func interfaceSeries(in range: ClosedRange<Date>) -> [TransferSeries] {
        TransferSeriesBuilder.series(networkFrames.filter { range.contains($0.stamp.wallTime) }.map { frame in
            TransferSeriesBuilder.Frame(
                id: frame.id, time: frame.stamp.wallTime, interrupted: frame.continuity == .interrupted,
                samples: frame.interfaces.map {
                    TransferSeriesBuilder.Sample(
                        key: "\($0.id.index)-\($0.id.name)", name: $0.id.name,
                        above: $0.receivedBytesPerSecond.numericValue, below: $0.sentBytesPerSecond.numericValue
                    )
                }
            )
        })
    }

    /// Swap in and out, and page-ins from files, in the shown range, for the
    /// memory lane's detail (plan: swap rate and page-ins).
    public func pagingSeries(in range: ClosedRange<Date>) -> [TransferSeries] {
        TransferSeriesBuilder.series(frames.filter { range.contains($0.stamp.wallTime) }.map { frame in
            TransferSeriesBuilder.Frame(
                id: frame.id, time: frame.stamp.wallTime, interrupted: frame.continuity == .interrupted,
                samples: [
                    TransferSeriesBuilder.Sample(
                        key: "swap", name: "Swap", above: frame.memory.swapInBytesPerSecond.numericValue,
                        below: frame.memory.swapOutBytesPerSecond.numericValue
                    ),
                    TransferSeriesBuilder.Sample(
                        key: "page-ins", name: "Page-ins", above: frame.memory.pageInBytesPerSecond.numericValue, below: nil
                    )
                ]
            )
        })
    }

    /// Every storage device's read and write rates in the shown range, for
    /// the disk lane's detail. Devices are never summed: they can overlap.
    public func deviceSeries(in range: ClosedRange<Date>) -> [TransferSeries] {
        TransferSeriesBuilder.series(diskFrames.filter { range.contains($0.stamp.wallTime) }.map { frame in
            TransferSeriesBuilder.Frame(
                id: frame.id, time: frame.stamp.wallTime, interrupted: frame.continuity == .interrupted,
                samples: frame.devices.map {
                    TransferSeriesBuilder.Sample(
                        key: "\($0.id.registryEntryID)", name: $0.name,
                        above: $0.readBytesPerSecond.numericValue, below: $0.writtenBytesPerSecond.numericValue
                    )
                }
            )
        })
    }

    /// Only a lone GPU is recorded, so stored utilization extends a lone series only.
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

public enum SamplingCadence: Sendable {
    case normal, lowPower

    /// Every interval is this many times its normal length.
    var multiplier: Int {
        switch self {
        case .normal: 1
        case .lowPower: 2
        }
    }
}

/// Interrupted samples follow wakes, but also stalls under load; each would
/// re-run pmset over megabytes of log. One re-import per spacing is enough.
struct WakeImportSpacing: Sendable {
    static let spacing: TimeInterval = 60
    private var last: Date?

    mutating func admit(at time: Date) -> Bool {
        if let last, time.timeIntervalSince(last) < Self.spacing { return false }
        last = time
        return true
    }
}
