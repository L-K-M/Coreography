import Foundation

/// Process filters kept as chips (plan P22: saved filters as chips),
/// newest first, without duplicates.
struct SavedFilters {
    private static let defaultsKey = "savedProcessFilters"
    /// A row of chips, not a library.
    static let limit = 12

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    var all: [String] { defaults.stringArray(forKey: Self.defaultsKey) ?? [] }

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
        let updated = all.filter { $0 != filter }
        defaults.set(updated, forKey: Self.defaultsKey)
        return updated
    }
}
