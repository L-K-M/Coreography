import Foundation

#if os(macOS)
import CoreographySystem
#endif

/// One process as the kernel describes it, for tracing who launched a peer.
public struct RawPeerProcess: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let uid: UInt32
    public let path: String?

    public init(pid: Int32, parentPID: Int32, uid: UInt32, path: String?) {
        self.pid = pid
        self.parentPID = parentPID
        self.uid = uid
        self.path = path
    }
}

public protocol PeerProcessReading: Sendable {
    func process(_ pid: Int32) -> RawPeerProcess?
    func signing(path: String) -> CodeSigning
}

/// Reads a process's parent, owner and executable through the libproc
/// bridge, and an app's signature through Security.
public struct PeerProcessDriver: PeerProcessReading {
    public init() {}

    public func process(_ pid: Int32) -> RawPeerProcess? {
        #if os(macOS)
        var sample = coreo_process_sample()
        guard coreo_process_read(pid, &sample) == 0 else { return nil }
        let path = sample.path_error != 0 ? nil : withUnsafeBytes(of: sample.path) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return RawPeerProcess(pid: pid, parentPID: Int32(bitPattern: sample.parent_pid), uid: sample.uid, path: path)
        #else
        return nil
        #endif
    }

    public func signing(path: String) -> CodeSigning { CodeSignatureReader.signing(path: path) }
}
