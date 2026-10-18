import Foundation

/// Where a launchd job is defined; the folder decides who runs it and when.
public enum LaunchDomain: String, CaseIterable, Sendable {
    /// `~/Library/LaunchAgents`: this user, at login.
    case userAgents
    /// `/Library/LaunchAgents`: every user, at login.
    case agents
    /// `/Library/LaunchDaemons`: root, at boot.
    case daemons
    /// `/System/Library/LaunchAgents`: Apple's, sealed by SIP.
    case systemAgents
    /// `/System/Library/LaunchDaemons`: Apple's, sealed by SIP.
    case systemDaemons
}

public enum CodeSignature: Sendable {
    case apple
    case otherSigner
    case unsigned
    /// Missing program, unreadable signature, or off macOS.
    case unknown
}

/// One job definition as its property list states it.
public struct RawLaunchJob: Equatable, Sendable {
    public let domain: LaunchDomain
    public let plistPath: String
    public let label: String
    /// `Program`, else the first of `ProgramArguments`.
    public let program: String?
    public let runAtLoad: Bool
    /// `KeepAlive` true or a condition dictionary: launchd restarts it.
    public let keepAlive: Bool
    public let disabledInPlist: Bool
    public let signature: CodeSignature
}

public struct RawLaunchJobs: Sendable {
    public let jobs: [RawLaunchJob]
    /// Property lists that could not be read or lack a label.
    public let unreadable: Int
    /// launchd's enable and disable overrides by label, which win over the plist.
    public let overrides: [String: Bool]
    /// Why overrides could not be read, when they could not.
    public let overridesProblem: String?
}

public protocol LaunchJobReading: Sendable {
    func read() async -> RawLaunchJobs
}

/// Reads launchd job definitions from the standard folders and launchd's
/// own enable state through `launchctl print-disabled`, which needs no
/// root. Login and background items are not here: listing them needs the
/// helper.
public struct LaunchJobDriver: LaunchJobReading {
    private static let launchctl = URL(fileURLWithPath: "/bin/launchctl")
    private static let overridesTimeout: Duration = .seconds(5)
    private static let overridesBytes = 1024 * 1024
    private let folders: [(LaunchDomain, URL)]
    private let readsOverrides: Bool
    private let runner = BoundedCommandRunner()

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.init(folders: [
            (.userAgents, home.appendingPathComponent("Library/LaunchAgents")),
            (.agents, URL(fileURLWithPath: "/Library/LaunchAgents")),
            (.daemons, URL(fileURLWithPath: "/Library/LaunchDaemons")),
            (.systemAgents, URL(fileURLWithPath: "/System/Library/LaunchAgents")),
            (.systemDaemons, URL(fileURLWithPath: "/System/Library/LaunchDaemons"))
        ], readsOverrides: true)
    }

    init(folders: [(LaunchDomain, URL)], readsOverrides: Bool) {
        self.folders = folders
        self.readsOverrides = readsOverrides
    }

    public func read() async -> RawLaunchJobs {
        var jobs: [RawLaunchJob] = []
        var unreadable = 0
        for (domain, folder) in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "plist" {
                guard let job = Self.job(at: file, domain: domain) else {
                    unreadable += 1
                    continue
                }
                jobs.append(job)
            }
        }

        guard readsOverrides else { return RawLaunchJobs(jobs: jobs, unreadable: unreadable, overrides: [:], overridesProblem: nil) }
        let (overrides, problem) = await readOverrides()
        return RawLaunchJobs(jobs: jobs, unreadable: unreadable, overrides: overrides, overridesProblem: problem)
    }

    static func job(at file: URL, domain: LaunchDomain) -> RawLaunchJob? {
        guard let data = try? Data(contentsOf: file),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String else { return nil }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let keepAlive = (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] is [String: Any])
        return RawLaunchJob(
            domain: domain, plistPath: file.path, label: label, program: program,
            runAtLoad: plist["RunAtLoad"] as? Bool ?? false, keepAlive: keepAlive,
            disabledInPlist: plist["Disabled"] as? Bool ?? false,
            signature: program.map { CodeSignatureReader.signing(path: $0).signature } ?? .unknown
        )
    }

    /// Parses `launchctl print-disabled` lines such as
    /// `"com.example.agent" => disabled` (older systems print true or false).
    static func overrides(_ text: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch parts[1].trimmingCharacters(in: .whitespaces) {
            case "disabled", "true": result[label] = true
            case "enabled", "false": result[label] = false
            default: continue
            }
        }
        return result
    }

    private func readOverrides() async -> ([String: Bool], String?) {
        #if os(macOS)
        var overrides: [String: Bool] = [:]
        for domain in ["gui/\(getuid())", "system"] {
            do {
                let output = try await runner.run(
                    Self.launchctl, arguments: ["print-disabled", domain],
                    timeout: Self.overridesTimeout, keepBytes: Self.overridesBytes
                )
                guard output.exitStatus == 0, !output.timedOut, !output.truncated else {
                    return (overrides, "launchctl print-disabled \(domain) did not finish cleanly")
                }
                overrides.merge(Self.overrides(String(decoding: output.data, as: UTF8.self))) { user, _ in user }
            } catch {
                return (overrides, "launchctl could not start: \(error)")
            }
        }
        return (overrides, nil)
        #else
        return ([:], "launchd overrides need macOS")
        #endif
    }
}
