import Foundation

/// Coalesces the app's requests for new widget samples. WidgetKit still
/// decides when to deliver them; background requests share its daily budget.
@MainActor
public final class WidgetRefresh {
    public enum Activity: Sendable {
        case foreground, background

        fileprivate var interval: TimeInterval {
            switch self {
            case .foreground: 5 * 60
            case .background: 15 * 60
            }
        }
    }

    private let reload: @MainActor () -> Void
    private var lastRequested: Date?

    public init(reload: @escaping @MainActor () -> Void) { self.reload = reload }

    /// The first live sample refreshes every widget, then subsequent samples
    /// are coalesced. A clock correction starts a new interval.
    public func request(at date: Date, activity: Activity) {
        if let lastRequested {
            let elapsed = date.timeIntervalSince(lastRequested)
            guard elapsed < 0 || elapsed >= activity.interval else { return }
        }
        lastRequested = date
        reload()
    }
}
