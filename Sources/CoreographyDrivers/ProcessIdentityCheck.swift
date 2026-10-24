import Foundation

#if os(macOS)
import CoreographySystem
#endif

/// Whether a PID still names the process it did, guarding against reuse
/// between the moment the app saw it and the moment a tool attaches.
enum ProcessIdentityCheck {
    #if os(macOS)
    static func matches(_ pid: Int32, _ seconds: UInt64, _ microseconds: UInt64) -> Bool {
        var sample = coreo_process_sample()
        guard coreo_process_read(pid, &sample) == 0 else { return false }
        return sample.start_seconds == seconds && sample.start_microseconds == microseconds
    }
    #endif
}
