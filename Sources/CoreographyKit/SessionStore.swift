import Foundation

public enum SessionStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case storage(String)

    /// Messages interpolate the error; they should read the reason, not the case.
    public var description: String {
        switch self {
        case .storage(let reason): reason
        }
    }
}

/// Recorded sessions as private files beside history (plan: recordings are
/// frozen copies of a range). The store keeps opaque documents; the
/// service layer owns their format.
///
/// ```text
/// ~/Library/Application Support/Coreography/Sessions/   0700, excluded from backups
///     <uuid>.json                                      0600
/// ```
public actor SessionStore {
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600
    private static let fileExtension = "json"

    private let directory: URL

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coreography/Sessions", isDirectory: true)
    }

    public init(directory: URL = SessionStore.defaultDirectory) throws {
        self.directory = directory
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: Self.directoryPermissions]
            )
            try FileManager.default.setAttributes([.posixPermissions: Self.directoryPermissions], ofItemAtPath: directory.path)
            #if os(macOS)
            var url = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            #endif
        } catch {
            throw SessionStoreError.storage("\(error)")
        }
    }

    public func save(_ document: Data, id: UUID) throws {
        let file = url(id)
        do {
            try document.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: Self.filePermissions], ofItemAtPath: file.path)
        } catch {
            throw SessionStoreError.storage("\(error)")
        }
    }

    public func load(_ id: UUID) throws -> Data {
        do { return try Data(contentsOf: url(id)) } catch { throw SessionStoreError.storage("\(error)") }
    }

    /// Every stored session; unreadable names are skipped.
    public func list() -> [UUID] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == Self.fileExtension }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }

    public func delete(_ id: UUID) throws {
        do { try FileManager.default.removeItem(at: url(id)) } catch { throw SessionStoreError.storage("\(error)") }
    }

    private func url(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }
}
