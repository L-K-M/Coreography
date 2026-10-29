import Foundation

/// The space a folder tree takes on disk, and how much of it was seen.
public struct RawFolderSize: Equatable, Sendable {
    public enum Ending: Equatable, Sendable {
        /// Every item was read.
        case complete
        /// The walk stopped at its deadline; the bytes are a lower bound.
        case timedOut
        /// The walk was cancelled; the bytes are a lower bound.
        case cancelled
    }

    /// Allocated bytes of every file seen, each hard-linked file once.
    public let bytes: Int64
    /// Allocated bytes per first-level child, by name ("Xcode.app" -> bytes).
    public let children: [String: Int64]
    /// Items macOS would not let the walk read; they count as nothing.
    public let unreadable: Int
    public let files: Int
    public let ending: Ending

    public init(bytes: Int64, children: [String: Int64], unreadable: Int, files: Int, ending: Ending) {
        self.bytes = bytes
        self.children = children
        self.unreadable = unreadable
        self.files = files
        self.ending = ending
    }
}

public protocol FolderSizing: Sendable {
    /// Walks each root, never crossing into another volume or into a
    /// skipped path. A missing root counts as empty.
    func size(of roots: [String], skipping: Set<String>, deadline: ContinuousClock.Instant) async -> RawFolderSize
}

/// Sums allocated sizes with a file enumerator on its own queue, so a walk
/// of hundreds of thousands of files never holds a cooperative thread.
///
/// ```text
/// /Applications/Xcode.app/Contents/...   -> children["Xcode.app"]
/// ~/Library/Caches/...                   -> children["Caches"]
/// ```
public actor FolderSizeDriver: FolderSizing {
    private let samplingExecutor = DriverSamplingExecutor(label: "CoreographyDrivers.folder-size")
    /// Deadline and cancellation are checked every this many items, not every file.
    private static let checkInterval = 512

    public init() {}

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        samplingExecutor.asUnownedSerialExecutor()
    }

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isVolumeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .linkCountKey
    ]

    public func size(of roots: [String], skipping: Set<String>, deadline: ContinuousClock.Instant) async -> RawFolderSize {
        var walk = Walk()
        for root in roots {
            guard walk.ending == .complete else { break }
            walk.add(root: root, skipping: skipping, deadline: deadline)
        }
        return RawFolderSize(
            bytes: walk.bytes, children: walk.children, unreadable: walk.unreadable, files: walk.files, ending: walk.ending
        )
    }

    private struct Walk {
        var bytes: Int64 = 0
        var children: [String: Int64] = [:]
        var unreadable = 0
        var files = 0
        var ending = RawFolderSize.Ending.complete
        /// Device and inode of files with more than one link, so each counts once.
        private var linked: Set<[UInt64]> = []

        mutating func add(root: String, skipping: Set<String>, deadline: ContinuousClock.Instant) {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL
            guard FileManager.default.fileExists(atPath: rootURL.path) else { return }
            let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
            var denied = 0
            guard let items = FileManager.default.enumerator(
                at: rootURL, includingPropertiesForKeys: FolderSizeDriver.keys, options: [],
                errorHandler: { _, _ in
                    denied += 1
                    return true
                }
            ) else {
                unreadable += 1
                return
            }

            var seen = 0
            while let url = items.nextObject() as? URL {
                seen += 1
                if seen % FolderSizeDriver.checkInterval == 0 {
                    if Task.isCancelled { ending = .cancelled; break }
                    if ContinuousClock.now >= deadline { ending = .timedOut; break }
                }

                let path = url.path
                if skipping.contains(path) {
                    items.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: Set(FolderSizeDriver.keys)) else {
                    unreadable += 1
                    continue
                }
                // A mounted volume inside the tree is someone else's space.
                if values.isVolume == true {
                    items.skipDescendants()
                    continue
                }
                guard values.isRegularFile == true else { continue }
                if let links = values.linkCount, links > 1, !firstLink(path) { continue }

                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
                bytes += size
                files += 1
                guard path.hasPrefix(prefix) else { continue }
                let child = path.dropFirst(prefix.count).prefix { $0 != "/" }
                children[String(child), default: 0] += size
            }
            unreadable += denied
        }

        /// True the first time a hard-linked file is met.
        private mutating func firstLink(_ path: String) -> Bool {
            var info = stat()
            guard lstat(path, &info) == 0 else { return true }
            return linked.insert([UInt64(info.st_dev), UInt64(info.st_ino)]).inserted
        }
    }
}
