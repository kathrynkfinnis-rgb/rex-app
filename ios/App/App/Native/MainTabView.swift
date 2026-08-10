import SwiftUI

/// Bottom navigation with a raised centre "+" button, mirroring the web's
/// BottomNav. White surface, thin top border, forest green only on the active
/// tab and the add button.
struct MainTabView: View {
    var onSignedOut: () -> Void

    @State private var selection = 0
    @State private var showingAddRex = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                FeedView(onSignedOut: onSignedOut).tag(0)

                NavigationStack {
                    RexMapView()
                        .navigationDestination(for: String.self) { ItemDetailView(itemId: $0) }
                }
                .tag(1)

                NavigationStack {
                    CollectionsView()
                        .navigationDestination(for: String.self) { ItemDetailView(itemId: $0) }
                }
                .tag(2)

                NavigationStack { FriendsView() }.tag(3)

                NavigationStack {
                    ProfileView(onSignedOut: onSignedOut)
                        .navigationDestination(for: String.self) { ItemDetailView(itemId: $0) }
                }
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomBar
        }
        .ignoresSafeArea(.keyboard)
        .tint(RexColor.primary)
        .sheet(isPresented: $showingAddRex) {
            AddRexView(onDone: { showingAddRex = false })
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, title: "Feed", icon: "house")
            tabButton(index: 1, title: "Map", icon: "map")

            // Raised centre action, the way the web app does it.
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

            // Matches the web BottomNav: Feed, Map, +, Collections, Friends.
            // Profile is reached from the avatar in the feed's top bar.
            tabButton(index: 2, title: "Collections", icon: "bookmark")
            tabButton(index: 3, title: "Friends", icon: "person.2")
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
