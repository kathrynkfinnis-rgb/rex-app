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
        #if DEBUG
        // -RexCardHarness 1 renders a feed card against a mock, so card
        // layout can be looked at without a session. See CardLayoutHarness.
        if UserDefaults.standard.bool(forKey: "RexCardHarness") {
            window?.rootViewController = UIHostingController(rootView: CardLayoutHarness())
            window?.overrideUserInterfaceStyle = .light
            window?.makeKeyAndVisible()
            return
        }
        #endif
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

#if DEBUG
import SwiftUI

/// TEMPORARY — a way to look at a feed card without a session.
///
/// Nov 22. Build 107 shipped a feed with no margins: "there is no margin at
/// the side of the screen any more. Or buffer between items." The cause was
/// an action row whose minimum width exceeded the card's, which forced the
/// card wider than the screen; a vertical ScrollView centres oversized
/// content, so both margins went off the edges at once.
///
/// That was shipped unseen, because the simulator has no session and the feed
/// is behind sign-in. This renders a real RecommendationCardView, in the
/// feed's own container geometry, against decoded JSON — so the fix can be
/// looked at rather than reasoned about.
///
/// Reached only with `-RexCardHarness 1` on the launch arguments, and only in
/// a DEBUG build. Delete once the card layout has a settled home.
struct CardLayoutHarness: View {
    private static let json = """
    {
      "id": "harness-1",
      "rating": 8,
      "note": "Delicious spot for a galette lunch. Le Chevre every day. Wash it down with a cup of cidre.",
      "created_at": "2026-11-22T08:00:00Z",
      "photo_url": null,
      "photo_urls": null,
      "tags": ["Shop"],
      "user_id": "harness-user",
      "item_id": "harness-item",
      "trip_section": null,
      "is_anonymous": false,
      "list_section": null,
      "show_in_feed": true,
      "recommendation_tags": null,
      "items": {
        "id": "harness-item",
        "type": "place",
        "title": "TYCOZ - CRÊPERIE & OYSTER BAR",
        "subtitle": "2021 · Shop",
        "image_url": null,
        "genre": "Shop",
        "address": "Paris"
      },
      "profiles": {
        "username": "phoebe",
        "display_name": "Phoebe",
        "avatar_url": null
      },
      "creators": null
    }
    """

    private var rec: FeedRecommendation? {
        try? JSONDecoder().decode(FeedRecommendation.self, from: Data(Self.json.utf8))
    }

    var body: some View {
        // The feed's own container, copied from FeedView: a vertical
        // ScrollView, a LazyVStack spaced by betweenCards, and page padding
        // on the stack. The bug only shows through this geometry — a card
        // rendered on its own is given exactly the width it asks for and
        // looks fine no matter how wide it insists on being.
        ScrollView {
            LazyVStack(spacing: RexSpacing.betweenCards) {
                if let rec {
                    ForEach(0..<3, id: \.self) { _ in
                        RecommendationCardView(
                            rec: rec,
                            rexCount: 2,
                            isOnMyList: false,
                            wanters: []
                        )
                    }
                } else {
                    Text("Mock failed to decode")
                        .font(RexFont.text(15))
                        .foregroundStyle(RexColor.destructive)
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.vertical, RexSpacing.page)
        }
        .background(RexColor.background)
    }
}
#endif
