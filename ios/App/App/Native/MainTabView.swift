import SwiftUI

/// Bottom navigation. White surface, thin top border, forest green only on
/// the active tab. Trialing "+" moved up to the feed's top bar (next to the
/// profile avatar) instead of a raised centre button, freeing this bar's
/// centre slot for the new Explore tab.
struct MainTabView: View {
    var onSignedOut: () -> Void

    @State private var selection = 0
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

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                FeedView(onSignedOut: onSignedOut, popToRootSignal: feedPopSignal).tag(0)

                NavigationStack {
                    RexMapView(refreshSignal: mapRefreshSignal)
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
                ProfileView(onSignedOut: onSignedOut)
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
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, title: "Feed", icon: "house")
            tabButton(index: 1, title: "Map", icon: "map")
            tabButton(index: 2, title: "Collections", icon: "bookmark")
            // Trial: Explore takes the bottom bar's centre slot that the
            // raised "+" used to own; + moved up to the feed's top bar
            // instead (next to the profile avatar).
            tabButton(index: 3, title: "Explore", icon: "sparkle.magnifyingglass")
            // Profile is reached from the avatar in the feed's top bar.
            tabButton(index: 4, title: "Friends", icon: "person.2")
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
