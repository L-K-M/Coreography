import Foundation
import CoreographyDrivers

/// A first-level place where the startup volume's space goes.
public enum SpaceArea: String, CaseIterable, Codable, Sendable {
    case applications, desktop, documents, downloads, movies, music, pictures, library, appData, cloud, otherHome

    /// macOS asks the person before an app reads these: Desktop, Documents
    /// and Downloads once each, other apps' containers and cloud drives as
    /// "data from other apps". They are only measured when the person asks.
    public var asksMacOS: Bool {
        switch self {
        case .desktop, .documents, .downloads, .appData, .cloud: true
        case .applications, .movies, .music, .pictures, .library, .otherHome: false
        }
    }
}

/// Whether a survey may walk folders that make macOS ask the person.
public enum SpaceAccess: String, Codable, Sendable {
    /// Only folders that never raise a prompt.
    case withoutPrompts
    /// Every area; macOS asks once for each protected one.
    case askingMacOS
}

public struct SpaceItem: Equatable, Codable, Sendable {
    public let name: String
    public let bytes: Int64
}

/// One area's measured size.
public struct SpaceAreaSize: Equatable, Codable, Sendable {
    public enum Completeness: Equatable, Codable, Sendable {
        case complete
        /// macOS would not let some items be read (Mail, Photos without Full Disk Access).
        case unreadable(Int)
        /// The walk ran out of time.
        case timedOut
    }

    public let area: SpaceArea
    public let bytes: Int64
    /// The biggest first-level items, largest first.
    public let largest: [SpaceItem]
    public let completeness: Completeness
    /// Where Finder should reveal the area.
    public let path: String

    /// The bytes are a lower bound.
    public var isLowerBound: Bool { completeness != .complete }
}

/// Measures the areas of the person's home and the Applications folder.
///
/// ```text
/// /Applications, ~/Applications         applications
/// ~/Desktop ~/Documents ~/Downloads     asks macOS
/// ~/Movies ~/Music ~/Pictures           as named
/// ~/Library                             minus app data and cloud drives
/// ~/Library/Containers, Group Containers   appData (asks macOS)
/// ~/Library/Mobile Documents, CloudStorage cloud (asks macOS)
/// everything else in ~                  otherHome
/// ```
public struct SpaceSurvey: Sendable {
    /// One area may walk this long; a bigger one is reported as "at least".
    public static let areaTimeLimit = Duration.seconds(90)
    private static let largestShown = 3

    private let driver: any FolderSizing
    private let home: String

    public init() { self.init(driver: FolderSizeDriver(), home: Self.realHome()) }

    init(driver: any FolderSizing, home: String) {
        self.driver = driver
        self.home = home
    }

    /// Areas in the order a survey walks them: quick, prompt-free ones first.
    public static let order: [SpaceArea] = [
        .applications, .movies, .music, .pictures, .otherHome, .library, .desktop, .documents, .downloads, .appData, .cloud
    ]

    public func measure(_ area: SpaceArea) async -> SpaceAreaSize {
        let paths = roots(area)
        let deadline = ContinuousClock.now + Self.areaTimeLimit
        let raw = await driver.size(of: paths, skipping: skipped(area), deadline: deadline)
        let completeness: SpaceAreaSize.Completeness = switch raw.ending {
        case .timedOut, .cancelled: .timedOut
        case .complete: raw.unreadable > 0 ? .unreadable(raw.unreadable) : .complete
        }
        let largest = raw.children
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(Self.largestShown)
            .map { SpaceItem(name: Self.displayName($0.key), bytes: $0.value) }
        return SpaceAreaSize(area: area, bytes: raw.bytes, largest: largest, completeness: completeness, path: paths[0])
    }

    private func roots(_ area: SpaceArea) -> [String] {
        let library = home + "/Library"
        return switch area {
        case .applications: ["/Applications", home + "/Applications"]
        case .desktop: [home + "/Desktop"]
        case .documents: [home + "/Documents"]
        case .downloads: [home + "/Downloads"]
        case .movies: [home + "/Movies"]
        case .music: [home + "/Music"]
        case .pictures: [home + "/Pictures"]
        case .library: [library]
        case .appData: [library + "/Containers", library + "/Group Containers"]
        case .cloud: [library + "/Mobile Documents", library + "/CloudStorage"]
        case .otherHome: [home]
        }
    }

    /// Paths an area's walk must not enter: other areas, so nothing counts twice.
    private func skipped(_ area: SpaceArea) -> Set<String> {
        switch area {
        case .library:
            Set(roots(.appData) + roots(.cloud))
        case .otherHome:
            Set([SpaceArea.desktop, .documents, .downloads, .movies, .music, .pictures, .library].flatMap(roots))
                .union([home + "/Applications"])
        default:
            []
        }
    }

    /// "Xcode.app" reads as "Xcode", as Finder shows it.
    private static func displayName(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// The person's real home, never a container.
    private static func realHome() -> String {
        getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }
}
