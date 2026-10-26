import Foundation

/// The braid's three sounds, synthesized rather than shipped as assets:
/// a plucked string (Karplus-Strong). A burst of noise circulates through
/// a delay line one period long and is averaged on every pass, so it rings
/// at that pitch and dies away like a string.
///
/// ```text
/// noise ─▶ [ delay: sampleRate / frequency ] ──┬──▶ out
///              ▲                               │
///              └── damping × mean(two taps) ◀──┘
/// ```
/// Pitch is feedback, never telemetry: an app always plucks the same note,
/// whatever it is doing.
public enum PluckTone {
    public enum Cue: Sendable {
        /// The braid opened fully: light and high.
        case open
        /// An app was caught: its own note, dry and short.
        case scope(app: String)
        /// The braid folded closed: muted and low.
        case fold
    }

    public static let sampleRate = 44_100.0
    /// A minor pentatonic over two octaves, so any two notes agree.
    static let scale: [Double] = [220.00, 261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33]
    private static let openFrequency = 880.0
    private static let foldFrequency = 110.0
    private static let fadeSeconds = 0.004

    /// The same app always gets the same note: FNV-1a over its name, not
    /// Swift's per-launch hash seed.
    public static func frequency(for app: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in app.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return scale[Int(hash % UInt64(scale.count))]
    }

    /// Mono samples at `sampleRate`, peaking at the cue's level.
    public static func samples(for cue: Cue) -> [Float] {
        switch cue {
        case .open: pluck(frequency: openFrequency, seconds: 0.06, decibels: -30, damping: 0.98, seed: 3)
        case .scope(let app): pluck(frequency: frequency(for: app), seconds: 0.11, decibels: -22, damping: 0.995, seed: 7)
        case .fold: pluck(frequency: foldFrequency, seconds: 0.07, decibels: -28, damping: 0.97, seed: 11)
        }
    }

    /// - Parameters:
    ///   - damping: kept per pass round the loop; lower dies faster and duller.
    ///   - seed: the noise burst is seeded, so a cue sounds the same every time.
    static func pluck(frequency: Double, seconds: Double, decibels: Double, damping: Double, seed: UInt64) -> [Float] {
        let count = Int(seconds * sampleRate)
        let period = max(2, Int((sampleRate / frequency).rounded()))
        var state = seed
        var line = (0..<period).map { _ -> Double in
            // A linear congruential step is plenty for a noise burst.
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) * 2 - 1
        }

        var output = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let tap = index % period
            output[index] = line[tap]
            line[tap] = damping * 0.5 * (line[tap] + line[(tap + 1) % period])
        }

        // Short fades at both ends, so the cue starts and stops without a click.
        let fade = Int(fadeSeconds * sampleRate)
        for index in 0..<min(fade, count) {
            let gain = Double(index) / Double(fade)
            output[index] *= gain
            output[count - 1 - index] *= gain
        }
        let peak = output.map(abs).max() ?? 0
        guard peak > 0 else { return output.map { Float($0) } }
        let scale = pow(10, decibels / 20) / peak
        return output.map { Float($0 * scale) }
    }
}
