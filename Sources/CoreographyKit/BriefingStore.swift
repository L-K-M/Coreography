import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// One plain-language account of the last minutes, written by the app for
/// the Briefing widget, or why it could not be written.
public struct Briefing: Codable, Equatable, Sendable {
    public enum Outcome: Codable, Equatable, Sendable {
        case text(String)
        case failed(String)
    }

    public let outcome: Outcome
    /// The model that wrote it, as its provider names it.
    public let model: String
    /// The readings it covers; shorter than five minutes after a gap.
    public let windowStart: Date
    public let windowEnd: Date

    public init(outcome: Outcome, model: String, windowStart: Date, windowEnd: Date) {
        self.outcome = outcome
        self.model = model
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
}

public enum BriefingStoreError: Error, Equatable, Sendable {
    case unreadable(String)
}

/// The file the app writes and the sandboxed widget reads. It sits in the
/// real home folder, not a container: the widget reaches it through a
/// read-only sandbox exception for exactly this directory, so the two need
/// no shared team ID or app group.
public struct BriefingStore: Sendable {
    /// Must match the widget's `home-relative-path.read-only` entitlement.
    public static let relativeDirectory = "Library/Application Support/Coreography/Widgets"
    private static let fileName = "briefing.json"
    /// A briefing is a few hundred bytes; anything larger is not ours.
    private static let maximumBytes = 64 * 1024

    public let fileURL: URL

    public init() { self.init(directory: Self.defaultDirectory) }

    init(directory: URL) { fileURL = directory.appendingPathComponent(Self.fileName) }

    /// The user's real home. Inside the sandbox, `NSHomeDirectory()` is the container.
    static var defaultDirectory: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(relativeDirectory, isDirectory: true)
    }

    /// The newest briefing; nil when none is written, as when briefings are off.
    public func read() -> Result<Briefing?, BriefingStoreError> {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return .success(nil)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        guard data.count <= Self.maximumBytes else { return .failure(.unreadable("The briefing file is too large")) }
        do {
            return .success(try Self.decoder.decode(Briefing.self, from: data))
        } catch {
            return .failure(.unreadable("The briefing file is not a briefing"))
        }
    }

    public func write(_ briefing: Briefing) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(briefing).write(to: fileURL, options: .atomic)
    }

    /// Removes the briefing so the widget stops showing it; already absent is fine.
    public func remove() throws {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
