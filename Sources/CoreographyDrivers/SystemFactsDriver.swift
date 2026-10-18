import Foundation

#if os(macOS)
import Darwin
#endif

/// Static facts about this Mac and its load, for the inspector's
/// nothing-selected summary.
public struct RawSystemFacts: Equatable, Sendable {
    /// The model identifier, e.g. `Mac15,8`.
    public let model: String?
    /// The processor brand, e.g. `Apple M3 Max`.
    public let chip: String?
    /// The OS build, e.g. `25A354`.
    public let osBuild: String?
    public let bootTime: Date?
    /// One, five and fifteen minute load averages.
    public let loadAverages: [Double]?
}

public enum SystemFactsDriver {
    private static let loadAverageCount: Int32 = 3

    public static func read() -> RawSystemFacts {
        #if os(macOS)
        var loads = [Double](repeating: 0, count: Int(loadAverageCount))
        let loaded = getloadavg(&loads, loadAverageCount) == loadAverageCount
        return RawSystemFacts(
            model: string("hw.model"), chip: string("machdep.cpu.brand_string"), osBuild: string("kern.osversion"),
            bootTime: bootTime(), loadAverages: loaded ? loads : nil
        )
        #else
        return RawSystemFacts(model: nil, chip: nil, osBuild: nil, bootTime: nil, loadAverages: nil)
        #endif
    }

    #if os(macOS)
    private static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func bootTime() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
    #endif
}
