import Foundation
import Dispatch

#if os(macOS)
import Darwin
import SystemConfiguration
import CoreographySystem
#endif

public enum NetworkDriverError: Error, Equatable, Sendable {
    case unsupportedPlatform
    case unavailable(reason: String)
    case restricted(code: Int32)
    case systemCall(operation: String, code: Int32)
}

public enum NetworkLinkState: String, Codable, Sendable { case up, down }
public enum PrimaryNetworkFamily: String, Codable, Sendable { case ipv4, ipv6 }

public struct PrimaryNetworkInterface: Equatable, Sendable {
    public let name: String
    public let family: PrimaryNetworkFamily

    public init(name: String, family: PrimaryNetworkFamily) {
        self.name = name
        self.family = family
    }
}

public struct RawNetworkInterface: Sendable {
    public let index: UInt32
    public let name: String
    public let linkState: NetworkLinkState
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let monotonicNanoseconds: UInt64

    public init(
        index: UInt32, name: String, linkState: NetworkLinkState,
        receivedBytes: UInt64, sentBytes: UInt64, monotonicNanoseconds: UInt64
    ) {
        self.index = index
        self.name = name
        self.linkState = linkState
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.monotonicNanoseconds = monotonicNanoseconds
    }
}

public struct NetworkReadFailure: Sendable {
    public let index: UInt32
    public let error: NetworkDriverError

    public init(index: UInt32, error: NetworkDriverError) {
        self.index = index
        self.error = error
    }
}

public struct NetworkEnumeration: Sendable {
    public let interfaces: [RawNetworkInterface]
    public let failures: [NetworkReadFailure]
    public let isTruncated: Bool

    public init(
        interfaces: [RawNetworkInterface], failures: [NetworkReadFailure] = [],
        isTruncated: Bool = false
    ) {
        self.interfaces = interfaces
        self.failures = failures
        self.isTruncated = isTruncated
    }
}

public struct RawNetworkSnapshot: Sendable {
    public let clockID: UUID
    public let monotonicNanoseconds: UInt64
    public let wallTime: Date
    public let enumeration: Result<NetworkEnumeration, NetworkDriverError>
    public let primaryInterface: Result<PrimaryNetworkInterface, NetworkDriverError>

    public init(
        clockID: UUID, monotonicNanoseconds: UInt64, wallTime: Date,
        enumeration: Result<NetworkEnumeration, NetworkDriverError>,
        primaryInterface: Result<PrimaryNetworkInterface, NetworkDriverError>
    ) {
        self.clockID = clockID
        self.monotonicNanoseconds = monotonicNanoseconds
        self.wallTime = wallTime
        self.enumeration = enumeration
        self.primaryInterface = primaryInterface
    }
}

public protocol NetworkSampleReading: Sendable {
    func read() async -> RawNetworkSnapshot
}

/// IFMIB exposes full-width counters; routing statistics truncate third-party byte counts.
public actor NetworkInterfacesDriver: NetworkSampleReading {
    private static let interfaceCapacity = 1024
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.network-sampling")
    private let clockID = UUID()

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    public func read() async -> RawNetworkSnapshot {
        let enumeration = readInterfaces()
        let primary = readPrimaryInterface()
        return RawNetworkSnapshot(
            clockID: clockID, monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            wallTime: Date(), enumeration: enumeration, primaryInterface: primary
        )
    }

    private func readInterfaces() -> Result<NetworkEnumeration, NetworkDriverError> {
        #if os(macOS)
        var indices = [UInt32](repeating: 0, count: Self.interfaceCapacity)
        var count: Int32 = 0
        var truncated: Int32 = 0
        let status = coreo_network_indices(&indices, Int32(Self.interfaceCapacity), &count, &truncated)
        guard status == 0 else { return .failure(Self.failure(status, operation: "if_nameindex")) }
        guard count >= 0, Int(count) <= Self.interfaceCapacity else {
            return .failure(.unavailable(reason: "Invalid interface enumeration count"))
        }
        var interfaces: [RawNetworkInterface] = []
        var failures: [NetworkReadFailure] = []
        for index in Set(indices.prefix(Int(count))).sorted() {
            if Task.isCancelled { break }
            var sample = coreo_network_sample()
            let error = coreo_network_read(index, &sample)
            let time = DispatchTime.now().uptimeNanoseconds
            guard error == 0 else {
                failures.append(NetworkReadFailure(
                    index: index, error: Self.failure(error, operation: "IFDATA_GENERAL")
                ))
                continue
            }
            let name = withUnsafeBytes(of: sample.name) {
                String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let up = sample.flags & UInt32(IFF_UP) != 0
                && sample.flags & UInt32(IFF_RUNNING) != 0
            interfaces.append(RawNetworkInterface(
                index: index, name: name, linkState: up ? .up : .down,
                receivedBytes: sample.received_bytes, sentBytes: sample.sent_bytes,
                monotonicNanoseconds: time
            ))
        }
        return .success(NetworkEnumeration(
            interfaces: interfaces, failures: failures,
            isTruncated: truncated != 0 || Task.isCancelled
        ))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    private func readPrimaryInterface() -> Result<PrimaryNetworkInterface, NetworkDriverError> {
        #if os(macOS)
        let ipv4 = primaryName(entity: kSCEntNetIPv4)
        if case .success(let name?) = ipv4 {
            return .success(PrimaryNetworkInterface(name: name, family: .ipv4))
        }
        let ipv6 = primaryName(entity: kSCEntNetIPv6)
        if case .success(let name?) = ipv6 {
            return .success(PrimaryNetworkInterface(name: name, family: .ipv6))
        }
        if case .failure(let error) = ipv4 { return .failure(error) }
        if case .failure(let error) = ipv6 { return .failure(error) }
        return .failure(.unavailable(reason: "No primary IPv4 or IPv6 interface is published"))
        #else
        return .failure(.unsupportedPlatform)
        #endif
    }

    #if os(macOS)
    private func primaryName(entity: CFString) -> Result<String?, NetworkDriverError> {
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
            nil, kSCDynamicStoreDomainState, entity
        )
        guard let raw = SCDynamicStoreCopyValue(nil, key) else {
            let code = SCError()
            if code == kSCStatusNoKey { return .success(nil) }
            return .failure(.systemCall(operation: "SCDynamicStoreCopyValue", code: code))
        }
        guard let properties = raw as? [String: Any] else {
            return .failure(.unavailable(reason: "Malformed primary-interface metadata"))
        }
        guard let value = properties[kSCDynamicStorePropNetPrimaryInterface as String] else {
            return .success(nil)
        }
        guard let name = value as? String, !name.isEmpty else {
            return .failure(.unavailable(reason: "Malformed primary-interface name"))
        }
        return .success(name)
    }

    private static func failure(_ code: Int32, operation: String) -> NetworkDriverError {
        switch code {
        case EACCES, EPERM: .restricted(code: code)
        case ENOENT, ENXIO: .unavailable(reason: "Interface disappeared or detached during collection")
        case ENOTSUP: .unsupportedPlatform
        default: .systemCall(operation: operation, code: code)
        }
    }
    #endif
}
