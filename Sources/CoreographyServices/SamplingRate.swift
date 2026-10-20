import Foundation

/// The sampling rate chosen in the toolbar (plan: "1 s ⌄"). Two seconds is
/// as slow as every monitor's gap limit allows (host readings break after
/// 3 s), and it is the pace Low Power Mode sets, so the slower of the two
/// applies and they never stack.
public enum SamplingRate: Int, CaseIterable, Identifiable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2

    public var id: Self { self }

    private static let defaultsKey = "samplingRate"

    /// Every interval is this many times its normal length.
    func multiplier(with cadence: SamplingCadence) -> Int { max(rawValue, cadence.multiplier) }

    static func saved(in defaults: UserDefaults = .standard) -> SamplingRate {
        SamplingRate(rawValue: defaults.integer(forKey: defaultsKey)) ?? .oneSecond
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
