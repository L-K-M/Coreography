import Foundation

/// Process filters kept as chips (plan P22: saved filters as chips),
/// newest first, without duplicates.
struct SavedFilters {
    private static let defaultsKey = "savedProcessFilters"
    /// A row of chips, not a library.
    static let limit = 12

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// Chips are keyed by their text, so whatever was stored, each appears once and none is blank.
    var all: [String] {
        var seen: Set<String> = []
        return (defaults.stringArray(forKey: Self.defaultsKey) ?? []).filter {
            !Self.isBlank($0) && seen.insert($0).inserted
        }
    }

    /// The same test the Save button uses.
    static func isBlank(_ filter: String) -> Bool { filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Blank filters are not saved; saving one again moves it to the front.
    @discardableResult
    func save(_ filter: String) -> [String] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        let updated = Array(([trimmed] + all.filter { $0 != trimmed }).prefix(Self.limit))
        defaults.set(updated, forKey: Self.defaultsKey)
        return updated
    }

    @discardableResult
    func remove(_ filter: String) -> [String] {
        let current = all
        guard current.contains(filter) else { return current }
        let updated = current.filter { $0 != filter }
        defaults.set(updated, forKey: Self.defaultsKey)
        return updated
    }
}
