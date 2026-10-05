import Foundation
import UIKit
import UserNotifications

/// Oct 5 — "when I click on a push notification, it takes you to the feed not
/// the notification", "when I clicked on the Rex notification to say you had
/// liked my Rex, it brings me to the feed rather than the actual post", and
/// "clicking on this notification should take you to the person's profile not
/// to the friends page."
///
/// Three reports, one cause: nothing was listening. The app registered for
/// remote notifications and handled the device token, but never set a
/// `UNUserNotificationCenterDelegate`, so a tap did what a tap on any
/// notification does with no handler — launched the app wherever it last was.
/// The payload has carried `entity_type` and `entity_id` since push was built
/// (see send-push); it was simply never read.
///
/// The tap can land before the UI exists — a cold launch from a notification
/// runs the delegate before any view has appeared — so the destination is
/// stored rather than delivered, and whoever ends up on screen picks it up.
@MainActor
final class RexPushRouter: ObservableObject {
    static let shared = RexPushRouter()

    /// Where a tapped notification wants to go. Cleared by whoever handles it.
    @Published var pending: Destination?

    enum Destination: Equatable {
        /// A Rex, a want, a trip — anything with an item behind it.
        case recommendation(String)
        case item(String)
        case profile(String)
        case blast(String)
        /// Something we don't have a screen for, or a notification with no
        /// entity at all. The notifications list is the honest answer: it
        /// always has the thing that was tapped in it.
        case notifications
    }

    private init() {}

    /// Reads the payload send-push attaches. `entity_type` mirrors the
    /// `notifications.entity_type` column, so the cases here are that column's
    /// values rather than a second vocabulary invented for push.
    func route(from userInfo: [AnyHashable: Any]) {
        let entityType = userInfo["entity_type"] as? String
        let entityId = userInfo["entity_id"] as? String

        guard let entityId, !entityId.isEmpty else {
            pending = .notifications
            return
        }

        switch entityType {
        case "recommendation": pending = .recommendation(entityId)
        case "want": pending = .recommendation("want-\(entityId)")
        case "item": pending = .item(entityId)
        case "user", "profile", "friendship": pending = .profile(entityId)
        case "request", "blast": pending = .blast(entityId)
        default: pending = .notifications
        }
    }
}

/// The delegate itself. Separate from AppDelegate so the routing above can be
/// read and tested without dragging the whole app launch in with it.
final class RexNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RexNotificationDelegate()

    func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// A notification that arrives while the app is open should still be seen.
    /// Without this, iOS silently drops it — which looked like push not
    /// working at all whenever the person happened to be using the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            RexPushRouter.shared.route(from: userInfo)
            // The badge is a count of things you haven't looked at; having
            // just looked at one, it shouldn't still be counted.
            UNUserNotificationCenter.current().setBadgeCount(0)
            completionHandler()
        }
    }
}
