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
        /// A Rex, a trip — anything with an item behind it.
        case recommendation(String)
        /// A want-to-try. It has no page of its own, so whoever handles this
        /// looks up the item it is about; the id here is the want's.
        case want(String)
        case item(String)
        case profile(String)
        case blast(String)
        /// A shared collection, by list id.
        case collection(String)
        /// A friend request or acceptance, by friendship row id — see route().
        case friendship(String)
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
        // Oct 5 — "please can you fix want to try". This used to encode the
        // want id into a recommendation id with a "want-" prefix, which the
        // feed then recognised and answered by opening the notifications list
        // — so tapping a push about your want-to-try went nowhere in
        // particular. A want is its own kind of thing; saying so lets the
        // destination be the item it is about.
        case "want": pending = .want(entityId)
        case "item": pending = .item(entityId)
        case "user", "profile": pending = .profile(entityId)
        // Oct 5 — "got a new friend request. But it just took me to the home
        // page." A friendship notification's entity_id is the friendship ROW's
        // id, not a user's, so sending it to .profile asked for a profile that
        // doesn't exist and the push went nowhere. The row knows both people;
        // whoever handles this works out which of them isn't you.
        case "friendship": pending = .friendship(entityId)
        case "request", "blast": pending = .blast(entityId)
        case "list", "collection": pending = .collection(entityId)
        default: pending = .notifications
        }
    }

    /// Oct 5 — a find-rex.com link tapped in WhatsApp, now that the app claims
    /// those domains. The paths are the web routes' own (src/routes/r.$id,
    /// t.$id, c.$id), so a link always opens the same thing whether or not the
    /// person has the app; anything else is left to Safari rather than
    /// swallowed, which is why this reports whether it handled the URL.
    @discardableResult
    func route(from url: URL) -> Bool {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[1].isEmpty else { return false }
        let id = parts[1]

        switch parts[0] {
        // A trip is a recommendation too — the feed sorts out which screen it
        // needs once it knows what kind of item is behind it.
        case "r", "t": pending = .recommendation(id)
        case "c": pending = .collection(id)
        case "w": pending = .want(id)
        default: return false
        }
        return true
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
