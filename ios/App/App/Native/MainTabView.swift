import SwiftUI

/// Real bottom tab bar (task #34), now including Map (task #35).
struct MainTabView: View {
    var onSignedOut: () -> Void

    var body: some View {
        TabView {
            FeedView(onSignedOut: onSignedOut)
                .tabItem { Label("Feed", systemImage: "house") }

            NavigationStack {
                RexMapView()
                    .navigationDestination(for: String.self) { itemId in
                        ItemDetailView(itemId: itemId)
                    }
            }
            .tabItem { Label("Map", systemImage: "map") }

            NavigationStack {
                CollectionsView()
                    .navigationDestination(for: String.self) { itemId in
                        ItemDetailView(itemId: itemId)
                    }
            }
            .tabItem { Label("Collections", systemImage: "bookmark") }

            NavigationStack {
                FriendsView()
            }
            .tabItem { Label("Friends", systemImage: "person.2") }

            NavigationStack {
                ProfileView()
                    .navigationDestination(for: String.self) { itemId in
                        ItemDetailView(itemId: itemId)
                    }
            }
            .tabItem { Label("Profile", systemImage: "person.circle") }
        }
        .tint(RexColor.primary)
    }
}
