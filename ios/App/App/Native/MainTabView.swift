import SwiftUI

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

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                FeedView(
                    onSignedOut: onSignedOut,
                    popToRootSignal: feedPopSignal,
                    onFriendsTap: { selection = 4 },
                    addRexRefreshSignal: addRexRefreshSignal,
                    onViewOnMap: { focusMap(onItemId: $0) }
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

                NavigationStack {
                    FriendsView()
                        .navigationDestination(for: UserProfileRoute.self) { UserProfileView(route: $0) }
                }
                .tag(4)

                // No wrapping NavigationStack here — ProfileView owns its
                // own now, so a swiped row can push onto a real bound path.
                ProfileView(onSignedOut: onSignedOut, onViewOnMap: { focusMap(onItemId: $0) })
                    .tag(5)
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
