import Foundation

public protocol ResponsivenessProbing: Sendable {
    /// True when the process's event connection has stopped answering the
    /// WindowServer; nil when it cannot be judged (no serial number, so not
    /// a UI process the session knows).
    func unresponsive(_ pid: Int32) -> Bool?
}

/// The check Activity Monitor uses, resolved at runtime so its absence is a
/// clean "unavailable" rather than a link dependency: SkyLight answers
/// `CGSEventIsAppUnresponsive` for a ProcessSerialNumber, which the still
/// exported `GetProcessForPID` fills. Only processes in this login session's
/// WindowServer can be judged; everything else answers nil.
public struct ResponsivenessDriver: ResponsivenessProbing {
    #if os(macOS)
    // A ProcessSerialNumber is two UInt32s; raw pointers keep the C
    // signatures representable, which a Swift struct pointer is not.
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SerialForPID = @convention(c) (Int32, UnsafeMutableRawPointer) -> Int32
    private typealias IsUnresponsive = @convention(c) (Int32, UnsafeRawPointer) -> UInt8
    private let mainConnection: MainConnection
    private let serialForPID: SerialForPID
    private let isUnresponsive: IsUnresponsive

    /// SkyLight on modern macOS; CoreGraphics still exports the same
    /// symbols on versions before the split.
    private static let windowServerLibraries = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    ]
    /// HIServices sits under both umbrella frameworks; either path loads it.
    private static let processManagerLibraries = [
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        "/System/Library/Frameworks/Carbon.framework/Frameworks/HIServices.framework/HIServices"
    ]

    private static func symbol<T>(_ name: String, in libraries: [String], as type: T.Type = T.self) -> T? {
        for path in libraries {
            guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { continue }
            if let resolved = dlsym(library, name) { return unsafeBitCast(resolved, to: T.self) }
        }
        return nil
    }
    #endif

    public init?() {
        #if os(macOS)
        guard let mainConnection = Self.symbol("CGSMainConnectionID", in: Self.windowServerLibraries, as: MainConnection.self),
              let serialForPID = Self.symbol("GetProcessForPID", in: Self.processManagerLibraries, as: SerialForPID.self),
              let isUnresponsive = Self.symbol("CGSEventIsAppUnresponsive", in: Self.windowServerLibraries, as: IsUnresponsive.self)
        else { return nil }
        self.mainConnection = mainConnection
        self.serialForPID = serialForPID
        self.isUnresponsive = isUnresponsive
        #else
        return nil
        #endif
    }

    public func unresponsive(_ pid: Int32) -> Bool? {
        #if os(macOS)
        var serial: UInt64 = 0
        guard pid > 0 else { return nil }
        let status = withUnsafeMutableBytes(of: &serial) { serialForPID(pid, $0.baseAddress!) }
        guard status == 0 else { return nil }
        return withUnsafeBytes(of: &serial) { isUnresponsive(mainConnection(), $0.baseAddress!) } != 0
        #else
        return nil
        #endif
    }
}
