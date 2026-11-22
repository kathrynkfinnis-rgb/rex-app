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
        if UserDefaults.standard.bool(forKey: "RexHeaderHarness")
            || UserDefaults.standard.bool(forKey: "RexPlaceHarness") {
            window?.rootViewController = UIHostingController(rootView: HeaderHarness())
            window?.overrideUserInterfaceStyle = .light
            window?.makeKeyAndVisible()
            return
        }
        if UserDefaults.standard.bool(forKey: "RexShelfHarness") {
            window?.rootViewController = UIHostingController(rootView: ShelfTileHarness())
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
      "photo_urls": ["https://image.tmdb.org/t/p/w500/20i4nShZZg1g1VFHSB8xpaYM4r7.jpg","https://image.tmdb.org/t/p/w500/20i4nShZZg1g1VFHSB8xpaYM4r7.jpg"],
      "tags": ["galettes", "cidre"],
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
        "subtitle": "2021 · Crêperie",
        "image_url": null,
        "genre": "Crêperie",
        "address": "Paris",
        "lat": 51.5136,
        "lng": -0.1365
      },
      "profiles": {
        "username": "phoebe",
        "display_name": "Phoebe",
        "avatar_url": null
      },
      "creators": null
    }
    """


    private static let bookJson = """
    {
      "id": "harness-2",
      "rating": 9,
      "note": "Furiously funny and then, without warning, very sad. I read it in two sittings and immediately made Gemma buy it.",
      "created_at": "2026-11-21T19:00:00Z",
      "photo_url": null,
      "photo_urls": null,
      "tags": null,
      "user_id": "harness-user",
      "item_id": "harness-book",
      "trip_section": null,
      "is_anonymous": false,
      "list_section": null,
      "show_in_feed": true,
      "recommendation_tags": null,
      "items": {
        "id": "harness-book",
        "type": "book",
        "title": "Fundamentally",
        "subtitle": "Nussaibah Younis · 2025",
        "image_url": "https://covers.openlibrary.org/b/id/15195855-M.jpg",
        "genre": "Fiction",
        "address": null
      },
      "profiles": {
        "username": "katy_finnis",
        "display_name": "Kathryn",
        "avatar_url": null
      },
      "creators": null
    }
    """

    private var book: FeedRecommendation? {
        try? JSONDecoder().decode(FeedRecommendation.self, from: Data(Self.bookJson.utf8))
    }

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
                    RecommendationCardView(
                        rec: rec, rexCount: 3, isOnMyList: false, wanters: []
                    )
                    if let book {
                        // A book is the other half of the rule: stock art, so
                        // it keeps its thumbnail and gets no hero.
                        RecommendationCardView(
                            rec: book, rexCount: 1, isOnMyList: false, wanters: []
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

/// TEMPORARY, same deal as CardLayoutHarness above — `-RexShelfHarness 1`.
///
/// Explore's shelves are behind sign-in too, so the thumbnail options could
/// not be looked at either. These are real rows from trending_items_weekly,
/// pasted rather than fetched so the tile is the only thing under test.
struct ShelfTileHarness: View {
    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let type: String
        let image: String?
        let source: String?
        let why: String
    }

    private let rows: [Row] = [
        Row(title: "Adolescence", type: "tv",
            image: "https://image.tmdb.org/t/p/w200/20i4nShZZg1g1VFHSB8xpaYM4r7.jpg",
            source: "tmdb", why: "catalogue art — kept"),
        Row(title: "Hay Barro Bowl set", type: "other",
            image: "https://prod.nordicnest.dev/assets/blobs/hay-barro-bowl-light-blue-20-cm-2-pack/595308-01_1_ProductImageMain-23b5c1f930.png",
            source: nil, why: "shop's own photo — kept"),
        Row(title: "TYCOZ - Crêperie & Oyster Bar", type: "place",
            image: "https://uhpzkbkwxcgqfxmlyktj.supabase.co/storage/v1/object/sign/rec-photos/x/y.jpg",
            source: "google", why: "Google photo in our bucket — kept"),
        Row(title: "Operation Mincemeat", type: "event",
            image: "https://uhpzkbkwxcgqfxmlyktj.supabase.co/storage/v1/object/sign/rec-photos/x/z.jpg",
            source: nil, why: "camera roll — replaced"),
        Row(title: "Car Seat Bag", type: "other",
            image: "https://uhpzkbkwxcgqfxmlyktj.supabase.co/storage/v1/object/sign/rec-photos/x/w.jpg",
            source: nil, why: "camera roll — replaced"),
        Row(title: "Cartagena, Columbia", type: "trip",
            image: nil, source: nil, why: "no picture at all"),
        Row(title: "Corfu", type: "trip", image: nil, source: nil, why: "no picture at all"),
        Row(title: "Glassette Reversible Stripe Cushion", type: "other",
            image: nil, source: nil, why: "no picture at all"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                Text("Explore tiles")
                    .font(RexFont.display(22))
                    .padding(.top, RexSpacing.xxl)
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: RexSpacing.md) {
                        ShelfTileArt(
                            art: ShelfArt.trusted(imageURL: row.image, externalSource: row.source,
                                                  title: row.title, type: row.type),
                            symbol: RexCategory(rawType: row.type).symbol
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(RexFont.text(12.5, weight: .medium))
                                .lineLimit(2)
                            Text(row.why)
                                .font(RexFont.text(11))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Text("Mosaic — several people")
                    .font(RexFont.text(13, weight: .medium))
                    .padding(.top, RexSpacing.md)
                ShelfTileArt(art: .mosaic([
                    "https://image.tmdb.org/t/p/w200/20i4nShZZg1g1VFHSB8xpaYM4r7.jpg",
                    "https://prod.nordicnest.dev/assets/blobs/hay-barro-bowl-light-blue-20-cm-2-pack/595308-01_1_ProductImageMain-23b5c1f930.png",
                    "https://image.tmdb.org/t/p/w200/20i4nShZZg1g1VFHSB8xpaYM4r7.jpg",
                    "https://prod.nordicnest.dev/assets/blobs/hay-barro-bowl-light-blue-20-cm-2-pack/595308-01_1_ProductImageMain-23b5c1f930.png",
                ]))
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.bottom, RexSpacing.xxl)
        }
        .background(RexColor.background)
    }
}

/// TEMPORARY — `-RexHeaderHarness 1`. The Rex page's header alone, which is
/// the part of it that needs no session: band, wave and cover, at whatever
/// RexHeaderMetrics currently says. Nov 22, to check the tightened band still
/// holds the cover the way the old one did.
struct HeaderHarness: View {
    /// -RexHeaderHarness 2 shows a place instead of a book: a photograph
    /// somebody took across the band, the listing photo in the card on it.
    private var isPlace: Bool { UserDefaults.standard.bool(forKey: "RexPlaceHarness") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isPlace {
                    ZStack(alignment: .topTrailing) {
                        RexPhotoBand(url: "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=900")
                        RexHeaderThumbnail(
                            url: "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=400",
                            category: .place
                        )
                        .padding(.trailing, RexHeaderMetrics.thumbTrailing)
                        .padding(.top, RexHeaderMetrics.photoThumbTop)
                    }
                    .frame(height: RexHeaderMetrics.photoBandHeight, alignment: .top)
                    .padding(.horizontal, -16)
                    .padding(.top, -16)
                } else {
                ZStack(alignment: .topTrailing) {
                    RexBannerBand(category: .book)
                    RexHeaderThumbnail(
                        url: "https://covers.openlibrary.org/b/id/15195855-M.jpg",
                        category: .book
                    )
                    .padding(.trailing, RexHeaderMetrics.thumbTrailing)
                    .padding(.top, RexHeaderMetrics.thumbTop)
                }
                .frame(height: RexHeaderMetrics.bandHeight, alignment: .top)
                .padding(.horizontal, -16)
                .padding(.top, -16)
                }

                VStack(alignment: .leading, spacing: 0) {
                    RexCategoryPill(category: isPlace ? .place : .book)
                    Text(isPlace ? "TYCOZ - Crêperie & Oyster Bar" : "Fundamentally")
                        .font(RexFont.display(28))
                        .lineSpacing(-4)
                        .padding(.top, 12)
                    // One font, one size, with the address below it.
                    Text(isPlace ? "Crêperie · 11th arrondissement" : "Nussaibah Younis")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.top, 8)
                    if isPlace {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "mappin").font(.system(size: 12))
                            Text("8 Rue de la Roquette, 75011 Paris")
                                .font(RexFont.text(14))
                        }
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.top, 9)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)

                Text(isPlace
                     ? "A tiny crêperie off the Bastille end of Roquette, open late and almost always full. The galettes are the reason to come\u{2026}"
                     : "Nadia is an academic who's been disowned by her puritanical mother and dumped by her lover, Rosy. She de\u{2026}")
                    .font(RexFont.text(13.5))
                    .lineLimit(2)
                // Rex'd by, in the order people Rex'd it, with each person's
                // own ranking on their face where they have one. Untouched by
                // any of today's changes — it was missing from the mock, not
                // from the page.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rex\u{2019}d by 3 people")
                        .font(RexFont.text(12, weight: .semibold))
                        .foregroundStyle(RexColor.mutedForeground)
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array([("kathryn", "1"), ("Danny", ""), ("Menaal", "")].enumerated()),
                                id: \.offset) { _, person in
                            VStack(spacing: 4) {
                                Circle().fill(RexColor.muted).frame(width: 44, height: 44)
                                    .overlay(Text(String(person.0.prefix(1)).uppercased())
                                        .font(RexFont.text(16, weight: .semibold))
                                        .foregroundStyle(RexColor.mutedForeground))
                                    .overlay(alignment: .topLeading) {
                                        if !person.1.isEmpty {
                                            Text(person.1)
                                                .font(RexFont.text(10, weight: .bold))
                                                .foregroundStyle(RexColor.primaryForeground)
                                                .padding(4)
                                                .background(RexColor.primary, in: Circle())
                                                .offset(x: -4, y: -4)
                                        }
                                    }
                                Text(person.0)
                                    .font(RexFont.text(11))
                                    .foregroundStyle(RexColor.mutedForeground)
                            }
                        }
                    }
                }
                .padding(.top, 14)
                Text("What friends say")
                    .font(RexFont.display(20))
                    .padding(.top, 14)

                // The commentary itself — the thing the page is for.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(RexColor.muted).frame(width: 24, height: 24)
                                .overlay(Text("M").font(RexFont.text(11, weight: .semibold))
                                    .foregroundStyle(RexColor.mutedForeground))
                            Text("Menaal").font(.system(size: 14, weight: .semibold))
                        }
                        Spacer()
                        Text("\u{1F44C} Rex").font(RexFont.text(12, weight: .semibold))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                    Text("\u{201C}Go for the galettes, stay for the cidre. We went twice in a weekend and I would happily have gone a third time.\u{201D}")
                        .font(RexFont.text(15))
                        .foregroundStyle(RexColor.foreground.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
                .padding(.top, 10)

                // The bottom of the page as it is now: a button, not a form.
                HStack(spacing: RexSpacing.sm) {
                    Text("Rex it")
                        .font(RexFont.text(15, weight: .semibold))
                        .foregroundStyle(RexColor.primaryForeground)
                        .padding(.horizontal, RexSpacing.lg)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(RexColor.primary)
                        .clipShape(Capsule())
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark")
                        Text("Want to try")
                    }
                    .font(RexFont.text(14, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.horizontal, RexSpacing.md)
                    .frame(minHeight: 44)
                    .overlay(Capsule().stroke(RexColor.border, lineWidth: 1))
                }
                .padding(.top, 24)
            }
            .padding(16)
        }
        .background(RexColor.background)
    }
}
#endif
