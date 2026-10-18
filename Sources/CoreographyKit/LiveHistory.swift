/// The in-memory history tier (plan: one hour in memory).
public enum LiveHistory {
    /// One hour of one-second samples per monitor.
    public static let capacity = 3600
}
