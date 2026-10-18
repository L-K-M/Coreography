import Foundation
import CoreographyDrivers

/// Delivers alert notifications: asks permission once, and posts under the
/// rule's identifier so a repeat replaces the previous banner rather than
/// stacking (plan: notifications collapse repeats).
public actor AlertDelivery {
    private static let identifierPrefix = "coreography.alert."
    private let poster: any NotificationPosting
    private var permitted: Bool?

    public init() { self.init(poster: UserNotificationDriver()) }

    init(poster: any NotificationPosting) { self.poster = poster }

    /// Returns false when permission is denied or posting fails; alerts still tint and mark.
    @discardableResult
    public func deliver(ruleID: String, title: String, body: String) async -> Bool {
        if permitted == nil { permitted = await poster.requestPermission() }
        guard permitted == true else { return false }
        do {
            try await poster.post(identifier: Self.identifierPrefix + ruleID, title: title, body: body)
            return true
        } catch {
            return false
        }
    }
}
