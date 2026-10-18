import Foundation
#if os(macOS)
import UserNotifications
#endif

public protocol NotificationPosting: Sendable {
    func requestPermission() async -> Bool
    func post(identifier: String, title: String, body: String) async throws
}

/// System notifications through UserNotifications, which honours Focus.
/// Only a bundled app may use it; command-line hosts must not create one.
public struct UserNotificationDriver: NotificationPosting {
    public init() {}

    public func requestPermission() async -> Bool {
        #if os(macOS)
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
        #else
        false
        #endif
    }

    public func post(identifier: String, title: String, body: String) async throws {
        #if os(macOS)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
        #endif
    }
}
