import UIKit
import UserNotifications

/// #175 — thin wrapper around UNUserNotificationCenter + UIApplication's
/// remote-notification registration. Kept separate from RexAPI (which is
/// the Supabase HTTP layer) since this talks to iOS, not the network.
enum RexPushNotifications {
    /// Requests OS permission and, if granted, kicks off APNs registration.
    /// The actual device token arrives asynchronously via AppDelegate's
    /// didRegisterForRemoteNotificationsWithDeviceToken — this function
    /// only reports whether it's worth waiting for that.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            return granted
        } catch {
            return false
        }
    }
}
