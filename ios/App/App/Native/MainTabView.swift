import SwiftUI

/// "View on map function via a button" (item detail page — RecommendationCardView's
/// feed/profile cards already had one, per #133, but the full item page
/// never did). focusMap lives on MainTabView (it switches tabs), while
/// ItemDetailView is reached from a good half-dozen different navigation
/// stacks (Feed, Profile, Trip, List, Explore, search…) via the same
/// generic `.navigationDestination(for: String.self)` — threading a
/// closure through every one of those call sites individually would be a
/// lot of surface area for one button. An environment value instead: set
/// once here, read wherever ItemDetailView happens to be reached from.
private struct ViewOnMapKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
extension EnvironmentValues {
    var viewOnMap: ((String) -> Void)? {
        get { self[ViewOnMapKey.self] }
        set { self[ViewOnMapKey.self] = newValue }
    }
}

/// "Can we make the friends and collections boxes here both buttons that
/// take you to your respective pages?" (Profile's stat row). Same
/// environment-value shape as viewOnMap above, for the same reason:
/// ProfileView is reached both as MainTabView's own tag(5) and pushed from
/// inside FeedView's own stack, and this way it doesn't matter which —
/// the closure is set once, here.
private struct GoToFriendsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
private struct GoToCollectionsKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var goToFriends: (() -> Void)? {
        get { self[GoToFriendsKey.self] }
        set { self[GoToFriendsKey.self] = newValue }
    }
    var goToCollections: (() -> Void)? {
        get { self[GoToCollectionsKey.self] }
        set { self[GoToCollectionsKey.self] = newValue }
    }
}

/// Bottom navigation with a raised centre "+" button, mirroring the web's
/// BottomNav. White surface, thin top border, forest green only on the
/// active tab and the add button. + was trialed up in the feed's top bar
/// for a while (freeing this bar's centre slot for the new Explore tab),
/// but Kathryn asked for it back down here — Friends moved up to the top
/// bar in its place instead, next to the profile avatar.
struct MainTabView: View {
    var onSignedOut: () -> Void

    @State private var selection = 0
    @State private var showingAddRex = false
    /// Bumped when the add-a-Rex sheet dismisses, so Feed picks up
    /// whatever was just posted — same purpose as feedPopSignal/
    /// mapRefreshSignal below, just for this one.
    @State private var addRexRefreshSignal = 0
    /// Bumped when Feed is tapped while already selected — FeedView watches it
    /// and pops back to the top, so "home" always means the feed rather than
    /// whatever Rex you were last looking at.
    @State private var feedPopSignal = 0
    /// Bumped every time the Map tab becomes active. TabView keeps every tab
    /// alive rather than recreating it, so RexMapView's own .task only ever
    /// runs once per app launch — delete a Rex from Feed or Profile, and its
    /// pin just sat there on the map until the app was relaunched. This
    /// gives it a reason to reload without needing pull-to-refresh (which
    /// would fight the map's own pan gesture).
    @State private var mapRefreshSignal = 0
    /// #133 "view on map" — set from a card's map icon (Feed or Profile),
    /// read by RexMapView to jump straight to that pin. The nonce lives
    /// alongside it so tapping the same card's icon twice in a row still
    /// re-centres rather than a same-value change being ignored.
    @State private var mapFocusRequest: MapFocusRequest?
    @State private var mapFocusNonce = 0

    private func focusMap(onItemId itemId: String) {
        mapFocusNonce += 1
        mapFocusRequest = MapFocusRequest(itemId: itemId, nonce: mapFocusNonce)
        selection = 1
    }

    /// Sept 10 — a trip card's map tile opens the Map tab following that
    /// trip: only its pins, framed so all of them are on screen.
    private func focusMap(onTrip tripId: String, title: String) {
        mapFocusNonce += 1
        mapFocusRequest = MapFocusRequest(itemId: "", nonce: mapFocusNonce, tripId: tripId, tripTitle: title)
        selection = 1
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                FeedView(
                    onSignedOut: onSignedOut,
                    popToRootSignal: feedPopSignal,
                    addRexRefreshSignal: addRexRefreshSignal,
                    onViewOnMap: { focusMap(onItemId: $0) },
                    onViewTripOnMap: { focusMap(onTrip: $0, title: $1) }
                ).tag(0)

                NavigationStack {
                    RexMapView(refreshSignal: mapRefreshSignal, focusRequest: mapFocusRequest)
                        .navigationDestination(for: String.self) { ItemDetailView(itemId: $0) }
                        .navigationDestination(for: UserProfileRoute.self) { UserProfileView(route: $0) }
                }
                .tag(1)

                NavigationStack {
                    CollectionsView()
                        .navigationDestination(for: String.self) { ItemDetailView(itemId: $0) }
                        .navigationDestination(for: UserProfileRoute.self) { UserProfileView(route: $0) }
                        .navigationDestination(for: CollectionRoute.self) { CollectionDetailView(route: $0) }
                        .navigationDestination(for: CollectionsSectionRoute.self) { CollectionsSectionListView(route: $0) }
                        .navigationDestination(for: WishListRoute.self) { WishListCategoryView(route: $0) }
                }
                .tag(2)

                NavigationStack {
                    ExploreView()
                }
                .tag(3)

                // Sept 15 — Danny's "2 back arrows": Friends and Profile used to
                // be tabs 4 and 5 here. An iPhone tab bar holds five at most,
                // and UIKit quietly moves anything past that into a system
                // "More" tab with its own navigation controller — so Friends
                // and everything pushed from it sat inside TWO navigation
                // bars. The top back arrow was More's, and led to its blank
                // list (blank because our tab bar is hidden, so the tabs have
                // no labels). Neither needed to be a tab: Profile was already
                // pushed onto the feed, and Friends now is too.
            }
            // Deliberately NOT .page style. That style pages on a horizontal
            // swipe ANYWHERE on screen, not just via the tab bar — which is
            // exactly what was eating SwipeToRemove's DragGesture on the feed
            // and profile the whole time. Confirmed directly: after making
            // SwipeToRemove's drag a .highPriorityGesture (so it would beat a
            // ScrollView's own pan), a swipe on a card started paging straight
            // to the Map tab instead of revealing Delete. Default style
            // doesn't respond to swipe at all — only to `selection` changes —
            // so it's driven purely by tapping bottomBar's own buttons, same
            // as before, just without silently hijacking every other
            // horizontal gesture in the app.
            .toolbar(.hidden, for: .tabBar)

            bottomBar
        }
        .ignoresSafeArea(.keyboard)
        .tint(RexColor.primary)
        .environment(\.viewOnMap, { focusMap(onItemId: $0) })
        .environment(\.goToCollections, { selection = 2 })
        .sheet(isPresented: $showingAddRex, onDismiss: { addRexRefreshSignal += 1 }) {
            AddRexView(onDone: { showingAddRex = false })
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, title: "Feed", icon: "house")
            tabButton(index: 1, title: "Map", icon: "map")

            // Raised centre action, the way the web app does it — and the
            // way this bar looked before the Explore-tab trial moved it up
            // to the feed's top bar.
            Button {
                showingAddRex = true
            } label: {
                ZStack {
                    Circle()
                        .fill(RexColor.primary)
                        .frame(width: 52, height: 52)
                        .shadow(color: RexColor.primary.opacity(0.25), radius: 8, y: 3)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(RexColor.primaryForeground)
                }
                .offset(y: -14)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Add a Rex")

            tabButton(index: 2, title: "Collections", icon: "bookmark")
            // Friends is reached from the feed's top bar now; Explore keeps
            // this slot instead.
            tabButton(index: 3, title: "Explore", icon: "sparkle.magnifyingglass")
        }
        .padding(.top, RexSpacing.sm)
        .padding(.horizontal, RexSpacing.sm)
        .background(
            RexColor.card
                .overlay(alignment: .top) {
                    Rectangle().fill(RexColor.border).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(index: Int, title: String, icon: String) -> some View {
        Button {
            // Tapping the tab you're already on returns you to its root.
            if selection == index && index == 0 { feedPopSignal += 1 }
            // Switching onto the Map tab reloads it, so anything deleted
            // elsewhere doesn't linger as a stale pin (see mapRefreshSignal).
            if selection != index && index == 1 { mapRefreshSignal += 1 }
            selection = index
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                Text(title)
                    .font(.system(size: 10, weight: selection == index ? .semibold : .regular))
            }
            .foregroundStyle(selection == index ? RexColor.primary : RexColor.mutedForeground)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
