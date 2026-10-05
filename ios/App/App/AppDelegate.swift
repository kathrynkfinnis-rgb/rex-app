import UIKit
import Capacitor


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // AsyncImage rides on URLSession.shared, whose default cache is a few
        // hundred KB — barely one thumbnail. Feed photos were re-downloading
        // on every scroll-back for lack of anywhere to keep them. This is the
        // other half of the slow-photos fix alongside downscaling on upload.
        //
        // Sept 29: a second, larger URLCache was briefly added above this one
        // to explain "images on the feed aren't loading" — which was wrong
        // twice over. It was dead (this line ran after it and won), and the
        // cache was never the problem: 50MB was already ample. The map tiles
        // were simply slow to fetch from Google, and they don't come from the
        // network at all any more. See RexMapSnapshot.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024
        )

        // Sept 29 — the Google Maps SDK is no longer initialised. Nothing
        // creates a GMSMapView since the map moved to MapKit (see
        // AppleMapView), and keying the SDK is what starts a Dynamic Maps
        // billing relationship. Google is still used for place search, but
        // that goes over REST with its own key and header — it never touched
        // GMSServices. The package can come out of the project entirely for
        // the app-size saving whenever someone's in Xcode.

        // Oct 5 — "when I click on a push notification, it takes you to the
        // feed not the notification." Nothing was listening: the app
        // registered for push and handled the token but never set a
        // notification-centre delegate, so a tap just launched the app
        // wherever it last was. Set before the first view exists, because a
        // cold launch from a notification delivers the tap immediately.
        RexNotificationDelegate.shared.register()

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    // #175 — the device token only ever arrives here, asynchronously, some
    // time after RexPushNotifications.requestPermission() calls
    // registerForRemoteNotifications(). Converted to the hex string APNs
    // itself expects, then handed to RexAPI so the send-push function has
    // somewhere to deliver to.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        RexPushNotifications.record("Apple gave this phone a push address; saving it\u{2026}")
        Task {
            // Sept 15 — this used to be `try?`, which is how a failing save
            // went unnoticed for two weeks. Still never interrupts anything,
            // but the outcome is recorded and a failure reported.
            do {
                try await RexAPI.shared.registerPushToken(deviceToken: token)
                RexPushNotifications.record("This phone is registered for notifications.")
            } catch {
                RexPushNotifications.record("Couldn't save this phone's push address: \(error.localizedDescription)")
                await RexPushNotifications.reportFailure("token save failed: \(error.localizedDescription)")
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Never interrupts anything else, but no longer silent either.
        RexPushNotifications.record("Apple wouldn't register this phone for notifications: \(error.localizedDescription)")
        Task { await RexPushNotifications.reportFailure("APNs registration failed: \(error.localizedDescription)") }
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
