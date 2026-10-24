import Foundation

public protocol ServerNameResolving: Sendable {
    /// The PTR name for an address, or nil when it has none or is not one.
    func lookup(_ address: String) async -> String?
}

/// Runs blocking reverse DNS outside Swift's cooperative task pool.
public struct ServerNameDriver: ServerNameResolving {
    public init() {}

    public func lookup(_ address: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.blockingLookup(address))
            }
        }
    }

    private static func blockingLookup(_ address: String) -> String? {
        var storage = sockaddr_storage()
        var length = 0
        var v4 = in_addr()
        var v6 = in6_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            var sa = sockaddr_in()
            sa.sin_family = sa_family_t(AF_INET)
            #if os(macOS)
            sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            #endif
            sa.sin_addr = v4
            length = MemoryLayout<sockaddr_in>.size
            _ = withUnsafeBytes(of: &sa) { memcpy(&storage, $0.baseAddress!, length) }
        } else if inet_pton(AF_INET6, address, &v6) == 1 {
            var sa = sockaddr_in6()
            sa.sin6_family = sa_family_t(AF_INET6)
            #if os(macOS)
            sa.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            #endif
            sa.sin6_addr = v6
            length = MemoryLayout<sockaddr_in6>.size
            _ = withUnsafeBytes(of: &sa) { memcpy(&storage, $0.baseAddress!, length) }
        } else {
            return nil
        }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(length), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard result == 0 else { return nil }
        let name = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }
}
