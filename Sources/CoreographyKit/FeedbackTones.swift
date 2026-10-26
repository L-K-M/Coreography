import Foundation
import CoreographyDrivers

/// The braid's sounds, for the person's own gestures only, never for live
/// data. Silent when macOS interface sound effects are off, when Settings
/// turns them off here, or when no output device starts; never an error.
@MainActor
public final class FeedbackTones {
    /// The app's own switch, beside macOS's.
    public static let settingKey = "braidSounds"
    private let output: any TonePlaying
    private let defaults: UserDefaults
    /// Synthesized once per cue: each is the same every time.
    private var cache: [String: [Float]] = [:]

    public convenience init() { self.init(output: AudioToneDriver(), defaults: .standard) }

    init(output: any TonePlaying, defaults: UserDefaults) {
        self.output = output
        self.defaults = defaults
    }

    /// Both switches default to on; macOS's is reread on every cue so a
    /// change in System Settings applies at once.
    public var isEnabled: Bool {
        let own = defaults.object(forKey: Self.settingKey) as? Bool ?? true
        return own && UserInterfaceSoundSetting.enabled(in: defaults)
    }

    /// Returns the playback, which never blocks the caller; nil when silent.
    @discardableResult
    public func play(_ cue: PluckTone.Cue) -> Task<Bool, Never>? {
        guard isEnabled else { return nil }
        let key = Self.key(cue)
        let samples = cache[key] ?? PluckTone.samples(for: cue)
        cache[key] = samples
        let output = output
        return Task { await output.play(samples, sampleRate: PluckTone.sampleRate) }
    }

    private static func key(_ cue: PluckTone.Cue) -> String {
        switch cue {
        case .open: "open"
        case .fold: "fold"
        case .scope(let app): "scope:\(PluckTone.frequency(for: app))"
        }
    }
}
