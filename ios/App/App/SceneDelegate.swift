import UIKit
import SwiftUI
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        // Native SwiftUI rewrite in progress — screens not yet ported still live only
        // in the Capacitor/WebView build. See CAPBridgeViewController() for that path.
        window?.rootViewController = UIHostingController(rootView: RootView())
        // Belt and braces alongside RootView's .preferredColorScheme — this
        // catches anything hosted directly off the window rather than through
        // that SwiftUI tree (a UIKit-presented sheet, for instance).
        window?.overrideUserInterfaceStyle = .light
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
        handleLaunchActivity(connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    /// Oct 5 — "if you have the app already on your phone, it should take you
    /// to the app, not the webpage."
    ///
    /// A find-rex.com link tapped in WhatsApp arrives here as a browsing
    /// activity, because App.entitlements claims the domain and Apple has
    /// fetched /.well-known/apple-app-site-association from it. Unclaimed
    /// paths fall through to the Capacitor proxy and then to Safari, so a
    /// link we don't have a screen for still opens rather than dying here.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL,
           RexPushRouter.shared.route(from: url) {
            return
        }
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }

    /// The same, for a link that opens the app from cold: iOS hands the
    /// launching activity to the connection options rather than calling the
    /// method above.
    private func handleLaunchActivity(_ options: UIScene.ConnectionOptions) {
        guard let activity = options.userActivities.first(where: {
            $0.activityType == NSUserActivityTypeBrowsingWeb
        }), let url = activity.webpageURL else { return }
        RexPushRouter.shared.route(from: url)
    }
}
