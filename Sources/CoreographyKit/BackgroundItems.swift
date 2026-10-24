import Foundation

/// Parses `sfltool dumpbtm` text into startup items. The dump lists every
/// user's Background Task Management records as per-UID sections of `#N`
/// records of aligned `Key: value` lines; the field set and spellings have
/// drifted between macOS releases, so parsing keeps what it can recognize
/// and never drops a record it started.
public enum BackgroundItems {
    /// Every record parsed as an item. A record keeps its UUID as the id
    /// when it names nothing readable.
    public static func items(in dump: String) -> [StartupItem] {
        var items: [StartupItem] = []
        var uid: UInt?
        var fields: [String: String] = [:]
        var hasRecord = false

        func flush() {
            guard hasRecord else { return }
            items.append(item(fields, owner: uid))
            fields = [:]
            hasRecord = false
        }

        for line in dump.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if let found = text.firstMatch(of: /Records for UID\s+(\d+)/)?.output.1, let owner = UInt(found) {
                flush()
                uid = owner
                continue
            }
            // A record begins at a bare "#N" line; "#N: child" lines inside a
            // record name its embedded items and are skipped with it.
            if text.wholeMatch(of: /#\d+/) != nil {
                flush()
                hasRecord = true
                continue
            }
            guard hasRecord, let keyEnd = text.firstIndex(of: ":") else { continue }
            let key = String(text[..<keyEnd])
            fields[key] = String(text[text.index(after: keyEnd)...])
                .trimmingCharacters(in: .whitespaces).nilIfPlaceholder
        }
        flush()
        return items
    }

    /// The bit fields dumpbtm prints: `Type: login item (0x4)` and
    /// `Disposition: [enabled allowed visible notified] (11)` — the type
    /// mask decides the kind, the disposition's first bit the state.
    private static func item(_ fields: [String: String], owner: UInt?) -> StartupItem {
        let typeMask = hexMask(fields["Type"])
        let kind: StartupItemKind =
            typeMask & 0x4 != 0 ? .loginItem :
            typeMask & 0x8 != 0 ? .agent :
            typeMask & 0x10 != 0 ? .daemon : .backgroundItem

        let name = fields["Name"]
        let uuid = fields["UUID"]
        let label = [fields["Bundle Identifier"], fields["Identifier"].flatMap(Self.plainIdentifier), name, uuid]
            .lazy.compactMap { $0 }.first ?? "Background item"
        let path = fields["URL"].flatMap(Self.urlPath)
        let program = fields["Executable Path"]
        let apple = isApple(developer: fields["Developer Name"], urlPath: path, program: program)
        let runsAtLoad = kind == .loginItem || kind == .backgroundItem
        return StartupItem(
            label: label, kind: kind, plistPath: path ?? "btm:\(uuid ?? label)", program: program,
            runsAtLoad: runsAtLoad, keepsAlive: false,
            state: enabledState(fields["Disposition"]), isApple: apple, ownerUID: owner
        )
    }

    /// `(0x90010)` → its value; missing or malformed hex means "type not
    /// named in a way we know", which leaves the catch-all kind.
    private static func hexMask(_ text: String?) -> UInt {
        guard let text, let hex = text.firstMatch(of: /\(0x([0-9a-fA-F]+)\)/)?.output.1 else { return 0 }
        return UInt(hex, radix: 16) ?? 0
    }

    /// `[enabled …] (11)`: the first word decides; the trailing mask backs
    /// it up for spellings we have not seen.
    private static func enabledState(_ text: String?) -> StartupEnabledState {
        guard let text else { return .unconfirmed }
        if let words = text.firstMatch(of: /\[[^\]]*\]/)?.output {
            if words.contains("disabled") { return .disabled }
            if words.contains("enabled") { return .enabled }
        }
        guard let mask = text.firstMatch(of: /\((\d+)\)/)?.output.1, let value = Int(mask) else {
            return .unconfirmed
        }
        return value & 0x1 != 0 ? .enabled : .disabled
    }

    /// An `Identifier:` that is really a code requirement — long, with
    /// "anchor"/"identifier" keywords — names nothing short to show.
    private static func plainIdentifier(_ text: String) -> String? {
        text.contains(" ") || text.contains("(") ? nil : text
    }

    private static func urlPath(_ text: String) -> String? {
        if let url = URL(string: text), url.scheme == "file" { return url.path(percentEncoded: false) }
        return nil
    }

    private static func isApple(developer: String?, urlPath: String?, program: String?) -> Bool {
        if developer?.localizedCaseInsensitiveContains("apple") == true { return true }
        return [urlPath, program].compactMap { $0 }.contains { $0.hasPrefix("/System/") || $0.hasPrefix("/Apple Internal/") }
    }
}

private extension String {
    /// sfltool prints "(null)" for absent values.
    var nilIfPlaceholder: String? {
        self == "(null)" ? nil : self
    }
}
