import Foundation
#if os(macOS)
import AVFAudio
import CoreAudio
#endif

/// Plays short mono cues through the default output device.
public protocol TonePlaying: Sendable {
    /// Returns false when no output could start; the caller stays silent.
    func play(_ samples: [Float], sampleRate: Double) async -> Bool
}

/// The person's macOS setting "Play user interface sound effects", read
/// from the global defaults domain where System Settings keeps it. The key
/// is undocumented: nil when it is unset or unreadable, never a guess.
public enum UserInterfaceSoundSetting {
    private static let key = "com.apple.sound.uiaudio.enabled"

    public static func enabled(in defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: key) as? NSNumber)?.boolValue ?? true
    }
}

/// AVAudioEngine output for interface cues, on its own actor: Core Audio
/// can take seconds to answer when a Mac has no output device, and the
/// main thread must not wait for it. The engine starts on the first cue,
/// pauses once the last one has played, and a Mac without an output device
/// keeps returning false rather than raising.
public actor AudioToneDriver: TonePlaying {
    #if os(macOS)
    /// Its own thread, not the shared pool: a slow Core Audio call must not
    /// hold up the samplers' tasks either.
    private let queue = DispatchSerialQueue(label: "ch.lkmc.Coreography.tones")
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private var engine: AVAudioEngine?
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    /// Only the newest cue's end may pause the engine.
    private var cue = 0
    #endif

    public init() {}

    public func play(_ samples: [Float], sampleRate: Double) -> Bool {
        #if os(macOS)
        guard !samples.isEmpty, Self.hasOutputDevice(), let engine = prepare(sampleRate: sampleRate),
              let format, start(engine) else { return false }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        // A new cue replaces the one still ringing: one voice, never a pile-up.
        cue += 1
        let current = cue
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { await self?.finish(current) }
        }
        if !player.isPlaying { player.play() }
        return true
        #else
        return false
        #endif
    }

    #if os(macOS)
    /// One property read, so a Mac without speakers never builds an engine.
    private static func hasOutputDevice() -> Bool {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown
    }

    /// Attach once per sample rate; a device without channels has no output.
    private func prepare(sampleRate: Double) -> AVAudioEngine? {
        let engine = self.engine ?? AVAudioEngine()
        self.engine = engine
        if let format, format.sampleRate == sampleRate { return engine }
        guard engine.outputNode.outputFormat(forBus: 0).channelCount > 0,
              let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        if format == nil { engine.attach(player) } else { engine.disconnectNodeOutput(player) }
        engine.connect(player, to: engine.mainMixerNode, format: mono)
        format = mono
        return engine
    }

    /// A running engine keeps the audio hardware awake: pause once the last cue is heard.
    private func finish(_ played: Int) {
        guard played == cue else { return }
        player.stop()
        engine?.pause()
    }

    private func start(_ engine: AVAudioEngine) -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }
    #endif
}
