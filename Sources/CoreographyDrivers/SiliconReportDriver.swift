import Foundation
import Dispatch

#if os(macOS)
import IOKit
#endif

/// One state of a residency channel and its time in that state over the interval.
public struct RawReportState: Equatable, Sendable {
    public let name: String
    public let residency: Int64

    public init(name: String, residency: Int64) {
        self.name = name
        self.residency = residency
    }
}

/// One IOReport channel's change over an interval.
public struct RawReportChannel: Equatable, Sendable {
    public let group: String
    public let subgroup: String
    public let name: String
    public let unit: String
    /// The counter's change, for simple channels such as energy.
    public let value: Int64?
    /// Residency per state, for performance-state channels.
    public let states: [RawReportState]

    public init(group: String, subgroup: String, name: String, unit: String, value: Int64?, states: [RawReportState]) {
        self.group = group
        self.subgroup = subgroup
        self.name = name
        self.unit = unit
        self.value = value
        self.states = states
    }
}

public enum SiliconDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    /// A virtual machine publishes no power counters or frequency tables.
    case virtualMachine
    case unavailable(String)
}

/// Deltas since the previous read; the first read only sets the baseline.
public struct RawSiliconSample: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    /// Elapsed time the deltas cover; nil for the baseline read.
    public let intervalNanoseconds: UInt64?
    public let channels: Result<[RawReportChannel], SiliconDriverError>

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date, intervalNanoseconds: UInt64?,
        channels: Result<[RawReportChannel], SiliconDriverError>
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.intervalNanoseconds = intervalNanoseconds
        self.channels = channels
    }
}

/// Raw DVFS tables from the power manager's registry node, unscaled:
/// M1-M3 store hertz and M4 and later kilohertz.
public struct RawFrequencyTables: Equatable, Sendable {
    /// Frequency values by property name, such as "voltage-states5-sram".
    public let tables: [String: [UInt32]]
    /// `acc-clusters` as (voltage-states index, cluster type) pairs, where present.
    public let clusters: [RawClusterEntry]

    public init(tables: [String: [UInt32]], clusters: [RawClusterEntry]) {
        self.tables = tables
        self.clusters = clusters
    }
}

public struct RawClusterEntry: Equatable, Sendable {
    public let tableIndex: UInt8
    /// 0 is the lowest-performance tier.
    public let type: UInt8

    public init(tableIndex: UInt8, type: UInt8) {
        self.tableIndex = tableIndex
        self.type = type
    }
}

public protocol SiliconReportReading: Sendable {
    func read() async -> RawSiliconSample
    func frequencyTables() async -> Result<RawFrequencyTables, SiliconDriverError>
}

/// Reads Apple Silicon energy and performance-state counters through the
/// private IOReport library (owner-approved), loaded at run time so a Mac
/// without it reports why instead of failing to launch. Read-only.
///
/// ```text
/// Energy Model                              CPU/GPU/ANE/DRAM energy, mJ uJ nJ
/// CPU Stats / CPU Core Performance States   per-core residency: IDLE, V0P5, …
/// GPU Stats / GPU Performance States        GPUPH residency: OFF, IDLE, P1, …
/// ```
public actor SiliconReportDriver: SiliconReportReading {
    static let subscribedGroups: [(group: String, subgroup: String?)] = [
        ("Energy Model", nil),
        ("CPU Stats", "CPU Core Performance States"),
        ("GPU Stats", "GPU Performance States")
    ]
    /// Power manager tables are numbered; M5 Max uses 23.
    static let maximumTableIndex: UInt8 = 31

    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.ioreport-sampling")
    private let clockID = UUID()
    #if os(macOS)
    private var report: IOReportLibrary.Subscription?
    private var setupError: SiliconDriverError?
    private var previous: (sample: CFDictionary, nanoseconds: UInt64)?
    #endif

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func read() async -> RawSiliconSample {
        #if os(macOS)
        let now = DispatchTime.now().uptimeNanoseconds
        let wall = Date()
        func sample(_ interval: UInt64?, _ channels: Result<[RawReportChannel], SiliconDriverError>) -> RawSiliconSample {
            RawSiliconSample(clockID: clockID, monotonicNanoseconds: now, wallTime: wall, intervalNanoseconds: interval, channels: channels)
        }
        guard let subscription = subscription() else {
            return sample(nil, .failure(setupError ?? .unavailable("IOReport is not available")))
        }
        guard let current = subscription.sample() else {
            previous = nil
            return sample(nil, .failure(.unavailable("IOReportCreateSamples returned nothing")))
        }
        defer { previous = (current, now) }
        guard let baseline = previous, now > baseline.nanoseconds else { return sample(nil, .success([])) }
        guard let delta = subscription.delta(from: baseline.sample, to: current) else {
            return sample(nil, .failure(.unavailable("IOReportCreateSamplesDelta returned nothing")))
        }
        return sample(now - baseline.nanoseconds, .success(subscription.channels(in: delta)))
        #else
        return RawSiliconSample(
            clockID: clockID, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds, wallTime: Date(),
            intervalNanoseconds: nil, channels: .failure(.unsupportedPlatform)
        )
        #endif
    }

    public func frequencyTables() async -> Result<RawFrequencyTables, SiliconDriverError> {
        #if os(macOS)
        if Self.isVirtualMachine { return .failure(.virtualMachine) }
        return PowerManagerTables.read()
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    /// `kern.hv_vmm_present` is 1 inside a virtual machine.
    static var isVirtualMachine: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0) == 0 && value != 0
    }

    private func subscription() -> IOReportLibrary.Subscription? {
        if let report { return report }
        if setupError != nil { return nil }
        if Self.isVirtualMachine {
            setupError = .virtualMachine
            return nil
        }
        switch IOReportLibrary.subscribe(to: Self.subscribedGroups) {
        case .success(let subscription):
            report = subscription
            return subscription
        case .failure(let error):
            setupError = error
            return nil
        }
    }
    #endif
}

#if os(macOS)
/// The IOReport entry points, resolved from the shared cache at run time.
/// Copy and Create functions return +1 references; Get functions +0.
enum IOReportLibrary {
    fileprivate typealias CopyAllChannels = @convention(c) (UInt64, UInt64) -> Unmanaged<CFDictionary>?
    fileprivate typealias CreateSubscription = @convention(c) (
        UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, UnsafeRawPointer?
    ) -> UnsafeMutableRawPointer?
    fileprivate typealias CreateSamples = @convention(c) (UnsafeMutableRawPointer, CFMutableDictionary, UnsafeRawPointer?) -> Unmanaged<CFDictionary>?
    fileprivate typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, UnsafeRawPointer?) -> Unmanaged<CFDictionary>?
    fileprivate typealias ChannelText = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    fileprivate typealias SimpleInteger = @convention(c) (CFDictionary, Int32) -> Int64
    fileprivate typealias StateCount = @convention(c) (CFDictionary) -> Int32
    fileprivate typealias StateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    fileprivate typealias StateResidency = @convention(c) (CFDictionary, Int32) -> Int64

    private static let path = "/usr/lib/libIOReport.dylib"
    private static let channelsKey = "IOReportChannels"
    /// A state channel never has more states than this; more means a misread.
    private static let maximumStates: Int32 = 64

    /// The resolved entry points.
    fileprivate struct Functions: @unchecked Sendable {
        let copyAllChannels: CopyAllChannels
        let createSubscription: CreateSubscription
        let createSamples: CreateSamples
        let createSamplesDelta: CreateSamplesDelta
        let group: ChannelText
        let subgroup: ChannelText
        let name: ChannelText
        let unit: ChannelText
        let integer: SimpleInteger
        let stateCount: StateCount
        let stateName: StateName
        let stateResidency: StateResidency
    }

    /// One subscription; its channel dictionary is what IOReport accepted.
    final class Subscription: @unchecked Sendable {
        private let functions: Functions
        private let handle: UnsafeMutableRawPointer
        private let subscribed: CFMutableDictionary

        fileprivate init(functions: Functions, handle: UnsafeMutableRawPointer, subscribed: CFMutableDictionary) {
            self.functions = functions
            self.handle = handle
            self.subscribed = subscribed
        }

        deinit { Unmanaged<AnyObject>.fromOpaque(handle).release() }

        func sample() -> CFDictionary? {
            functions.createSamples(handle, subscribed, nil)?.takeRetainedValue()
        }

        func delta(from previous: CFDictionary, to current: CFDictionary) -> CFDictionary? {
            functions.createSamplesDelta(previous, current, nil)?.takeRetainedValue()
        }

        /// Metadata comes from each item of the actual sample: IOReport may
        /// omit or reorder channels relative to the request.
        func channels(in sample: CFDictionary) -> [RawReportChannel] {
            guard let items = (sample as NSDictionary)[IOReportLibrary.channelsKey as NSString] as? [NSDictionary] else { return [] }
            return items.map { item in
                let channel = item as CFDictionary
                let group = text(functions.group, channel)
                let subgroup = text(functions.subgroup, channel)
                let isEnergy = group == "Energy Model"
                var states: [RawReportState] = []
                if !isEnergy {
                    let count = functions.stateCount(channel)
                    if count > 0, count <= IOReportLibrary.maximumStates {
                        states = (0..<count).map { index in
                            RawReportState(
                                name: functions.stateName(channel, index).map { $0.takeUnretainedValue() as String } ?? "S\(index)",
                                residency: functions.stateResidency(channel, index)
                            )
                        }
                    }
                }
                return RawReportChannel(
                    group: group, subgroup: subgroup, name: text(functions.name, channel),
                    unit: text(functions.unit, channel).trimmingCharacters(in: .whitespaces),
                    value: isEnergy ? functions.integer(channel, 0) : nil, states: states
                )
            }
        }

        private func text(_ function: ChannelText, _ channel: CFDictionary) -> String {
            function(channel).map { $0.takeUnretainedValue() as String } ?? ""
        }
    }

    static func subscribe(to groups: [(group: String, subgroup: String?)]) -> Result<Subscription, SiliconDriverError> {
        guard let functions = resolve() else { return .failure(.unavailable("libIOReport or one of its functions is missing")) }
        guard let all = functions.copyAllChannels(0, 0)?.takeRetainedValue(),
              let items = (all as NSDictionary)[channelsKey as NSString] as? [NSDictionary] else {
            return .failure(.unavailable("IOReport lists no channels"))
        }

        let selected = items.filter { item in
            let channel = item as CFDictionary
            let group = functions.group(channel).map { $0.takeUnretainedValue() as String } ?? ""
            let subgroup = functions.subgroup(channel).map { $0.takeUnretainedValue() as String } ?? ""
            return groups.contains { $0.group == group && ($0.subgroup == nil || $0.subgroup == subgroup) }
        }
        guard !selected.isEmpty else { return .failure(.unavailable("IOReport has no energy or performance-state channels")) }

        let request = NSMutableDictionary(dictionary: all as NSDictionary)
        request[channelsKey as NSString] = selected
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let handle = functions.createSubscription(nil, request as CFMutableDictionary, &subscribed, 0, nil) else {
            subscribed?.release()
            return .failure(.unavailable("IOReportCreateSubscription failed"))
        }
        guard let channels = subscribed?.takeRetainedValue() else {
            Unmanaged<AnyObject>.fromOpaque(handle).release()
            return .failure(.unavailable("IOReport accepted no channels"))
        }
        return .success(Subscription(functions: functions, handle: handle, subscribed: channels))
    }

    private static func resolve() -> Functions? {
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(library, name).map { unsafeBitCast($0, to: type) }
        }
        guard let copyAllChannels = symbol("IOReportCopyAllChannels", as: CopyAllChannels.self),
              let createSubscription = symbol("IOReportCreateSubscription", as: CreateSubscription.self),
              let createSamples = symbol("IOReportCreateSamples", as: CreateSamples.self),
              let createSamplesDelta = symbol("IOReportCreateSamplesDelta", as: CreateSamplesDelta.self),
              let group = symbol("IOReportChannelGetGroup", as: ChannelText.self),
              let subgroup = symbol("IOReportChannelGetSubGroup", as: ChannelText.self),
              let name = symbol("IOReportChannelGetChannelName", as: ChannelText.self),
              let unit = symbol("IOReportChannelGetUnitLabel", as: ChannelText.self),
              let integer = symbol("IOReportSimpleGetIntegerValue", as: SimpleInteger.self),
              let stateCount = symbol("IOReportStateGetCount", as: StateCount.self),
              let stateName = symbol("IOReportStateGetNameForIndex", as: StateName.self),
              let stateResidency = symbol("IOReportStateGetResidency", as: StateResidency.self) else { return nil }
        return Functions(
            copyAllChannels: copyAllChannels, createSubscription: createSubscription, createSamples: createSamples,
            createSamplesDelta: createSamplesDelta, group: group, subgroup: subgroup, name: name, unit: unit,
            integer: integer, stateCount: stateCount, stateName: stateName, stateResidency: stateResidency
        )
    }
}

/// DVFS tables on the power manager node: "pmgr" through M5, "pmgr-child" on M6.
enum PowerManagerTables {
    private static let nodeNames: Set<String> = ["pmgr", "pmgr-child"]
    private static let entryBytes = 8

    static func read() -> Result<RawFrequencyTables, SiliconDriverError> {
        var iterator = io_iterator_t()
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &iterator)
        guard status == KERN_SUCCESS else { return .failure(.unavailable("AppleARMIODevice lookup failed (\(status))")) }
        defer { IOObjectRelease(iterator) }

        var tables: [String: [UInt32]] = [:]
        var clusters: [RawClusterEntry] = []
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            var buffer = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
            guard IORegistryEntryGetName(service, &buffer) == KERN_SUCCESS else { continue }
            let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard nodeNames.contains(name) else { continue }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { continue }

            for index in 0...SiliconReportDriver.maximumTableIndex {
                for key in ["voltage-states\(index)-sram", "voltage-states\(index)"] {
                    guard tables[key] == nil, let data = properties[key] as? Data else { continue }
                    tables[key] = frequencies(data)
                }
            }
            if clusters.isEmpty, let data = properties["acc-clusters"] as? Data {
                clusters = stride(from: 0, to: data.count - 1, by: entryBytes).map {
                    RawClusterEntry(tableIndex: data[data.startIndex + $0], type: data[data.startIndex + $0 + 1])
                }
            }
        }
        guard !tables.isEmpty else { return .failure(.unavailable("The power manager publishes no frequency tables")) }
        return .success(RawFrequencyTables(tables: tables, clusters: clusters))
    }

    /// Pairs of little-endian (frequency, voltage) words; the frequency comes first.
    private static func frequencies(_ data: Data) -> [UInt32] {
        stride(from: 0, through: data.count - entryBytes, by: entryBytes).map { offset in
            data[(data.startIndex + offset)..<(data.startIndex + offset + 4)].enumerated().reduce(UInt32(0)) {
                $0 | UInt32($1.element) << (8 * UInt32($1.offset))
            }
        }
    }
}
#endif
