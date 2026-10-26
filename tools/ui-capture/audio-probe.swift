// Times the first touches of this Mac's audio output, as the braid's
// sound driver makes them, so a slow or missing device shows in the log.
import AVFAudio
import CoreAudio
import Foundation

func timed<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
    let start = Date()
    let value = try body()
    print(String(format: "%-28@ %7.1f ms  %@", label, Date().timeIntervalSince(start) * 1000, String(describing: value)))
    return value
}

var device = AudioDeviceID(kAudioObjectUnknown)
var size = UInt32(MemoryLayout<AudioDeviceID>.size)
var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
_ = timed("default output device") {
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        ? "\(device)" : "none"
}
let engine = timed("AVAudioEngine()") { AVAudioEngine() }
_ = timed("output format") { engine.outputNode.outputFormat(forBus: 0) }
_ = timed("start") { () -> String in
    do { try engine.start(); return "running" } catch { return "failed: \(error)" }
}
