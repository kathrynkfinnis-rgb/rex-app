import SwiftUI

/// Deliveroo-homepage-style discovery surface: category pills up top,
/// horizontally-swipeable shelves stacked underneath. Three sources mixed
/// together — friends' collections you haven't followed yet, REX-team
/// curated picks (and anything credited to an outside source, both typed
/// in by the same three people), and what's trending across the app this
/// week. Reached from the Explore tab, not the logo — see FeedView/
/// MainTabView for the nav rework that made room for a dedicated tab.
struct ExploreView: View {
    @State private var filter: RexCategory?
    @State private var friendsCollections: [RexList] = []
    @State private var collectionOwners: [String: RexProfileDetail] = [:]
    @State private var trending: [TrendingItem] = []
    @State private var editorial: [EditorialCollection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pushedItemId: String?
    @State private var pushedCollection: CollectionRoute?

    private let filterOptions: [RexCategory] = [
        .place, .trip, .book, .movie, .tv, .podcast, .recipe, .event,
    ]

    private func matches(_ category: String?) -> Bool {
        guard let filter else { return true }
        return category == filter.rawValue
    }

    private var visibleFriendsCollections: [RexList] {
        friendsCollections.filter { matches($0.item_type) }
    }
    private var visibleTrending: [TrendingItem] {
        trending.filter { matches($0.type) }
    }
    private var visibleEditorial: [EditorialCollection] {
        // A shelf with no category is general-interest — only hide it once
        // a specific filter is chosen and it plainly doesn't match.
        editorial.filter { $0.category == nil || matches($0.category) }
    }

    // No self-wrapping NavigationStack — MainTabView provides one, the same
    // way it does for the Map/Collections/Friends tabs. ProfileView is the
    // one exception (it also needs to work when pushed from the feed
    // avatar, not just as a tab root) and nesting one NavigationStack
    // inside another is what caused #114's blank-screen bug — don't repeat
    // that here.
    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    filterRow

                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: RexRadius.card)
                                .fill(RexColor.muted)
                                .frame(height: 150)
                                .padding(.horizontal, RexSpacing.page)
                                .padding(.bottom, RexSpacing.lg)
                        }
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else if visibleFriendsCollections.isEmpty && visibleTrending.isEmpty && visibleEditorial.isEmpty {
                        emptyState
                    } else {
                        if !visibleFriendsCollections.isEmpty {
                            shelf(title: "Missed from your friends", tag: "FRIENDS") {
                                ForEach(visibleFriendsCollections) { list in
                                    friendCollectionCard(list)
                                }
                            }
                        }
                        ForEach(visibleEditorial) { collection in
                            if !collection.items.isEmpty {
                                shelf(title: collection.title, tag: collection.source_label.uppercased()) {
                                    ForEach(collection.items) { item in
                                        editorialCard(item)
                                    }
                                }
                            }
                        }
                        if !visibleTrending.isEmpty {
                            shelf(title: "Trending this week", tag: "POPULAR") {
                                ForEach(visibleTrending) { item in
                                    trendingCard(item)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, RexSpacing.xxl)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $pushedItemId) { ItemDetailView(itemId: $0) }
            .navigationDestination(item: $pushedCollection) { CollectionDetailView(route: $0) }
            .refreshable { await load() }
            .task { await load() }
        }
        .tint(RexColor.primary)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RexSpacing.sm) {
                filterChip("All", isSelected: filter == nil) { filter = nil }
                ForEach(filterOptions, id: \.self) { category in
                    filterChip(category.label, isSelected: filter == category) { filter = category }
                }
            }
            .padding(.horizontal, RexSpacing.page)
        }
        .padding(.vertical, RexSpacing.md)
    }

    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(RexFont.text(13, weight: .medium))
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, 7)
                .background(isSelected ? RexColor.primary : RexColor.card)
                .foregroundStyle(isSelected ? RexColor.primaryForeground : RexColor.foreground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(RexColor.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func shelf<Content: View>(title: String, tag: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: RexSpacing.sm) {
                Text(title)
                    .font(RexFont.text(16, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Text(tag)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(RexColor.badgeForeground)
                    .padding(.horizontal, RexSpacing.sm)
                    .padding(.vertical, 2)
                    .background(RexColor.badgeBackground)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, RexSpacing.page)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: RexSpacing.md) {
                    content()
                }
                .padding(.horizontal, RexSpacing.page)
            }
        }
        .padding(.bottom, RexSpacing.xl)
    }

    private func shelfThumbnail(url: String?, symbol: String) -> some View {
        Group {
            if let url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RexColor.muted
                    }
                }
            } else {
                RexColor.muted.overlay(
                    Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(RexColor.mutedForeground)
                )
            }
        }
        .frame(width: 132, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
    }

    private func friendCollectionCard(_ list: RexList) -> some View {
        let owner = list.user_id.flatMap { collectionOwners[$0] }
        return Button {
            pushedCollection = CollectionRoute(listId: list.id, name: list.name, isMine: false)
        } label: {
            VStack(alignment: .leading, spacing: RexSpacing.xs) {
                ZStack {
                    RexColor.badgeBackground
                    Text(list.emoji ?? "\u{1F4D2}").font(.system(size: 30))
                }
                .frame(width: 132, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )

                Text(list.name)
                    .font(RexFont.text(12.5, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let owner {
                    Text("by \(owner.display_name ?? owner.username)")
                        .font(RexFont.text(11))
                        .foregroundStyle(RexColor.mutedForeground)
                        .lineLimit(1)
                }
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func trendingCard(_ item: TrendingItem) -> some View {
        Button {
            pushedItemId = item.item_id
        } label: {
            VStack(alignment: .leading, spacing: RexSpacing.xs) {
                shelfThumbnail(url: item.image_url, symbol: RexCategory(rawType: item.type).symbol)
                Text(item.title)
                    .font(RexFont.text(12.5, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("Rex'd \(item.rex_count) time\(item.rex_count == 1 ? "" : "s") this week")
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func editorialCard(_ item: EditorialCollectionItem) -> some View {
        Group {
            if let itemId = item.item_id {
                Button { pushedItemId = itemId } label: { editorialCardBody(item) }
                    .buttonStyle(.plain)
            } else if let linkString = item.link_url, let url = URL(string: linkString) {
                Link(destination: url) { editorialCardBody(item) }
            } else {
                editorialCardBody(item)
            }
        }
    }

    private func editorialCardBody(_ item: EditorialCollectionItem) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.xs) {
            shelfThumbnail(url: item.image_url, symbol: "sparkles")
            Text(item.title)
                .font(RexFont.text(12.5, weight: .medium))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(1)
            }
        }
        .frame(width: 132, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "sparkle.magnifyingglass").font(.system(size: 28)).foregroundStyle(RexColor.mutedForeground)
            Text("Nothing to explore here yet")
                .font(RexFont.display(18, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Try a different filter, or check back once there's more activity.")
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, RexSpacing.xxl)
        .padding(.horizontal, RexSpacing.xxl)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(RexFont.text(13)).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = friendsCollections.isEmpty && trending.isEmpty && editorial.isEmpty
        errorMessage = nil
        async let friendsTask = RexAPI.shared.fetchFriendsCollectionsToExplore()
        async let trendingTask = RexAPI.shared.fetchTrendingItems()
        async let editorialTask = RexAPI.shared.fetchEditorialCollections()
        friendsCollections = (try? await friendsTask) ?? []
        trending = (try? await trendingTask) ?? []
        editorial = (try? await editorialTask) ?? []

        let ownerIds = Array(Set(friendsCollections.compactMap(\.user_id)))
        if !ownerIds.isEmpty {
            let profiles = (try? await RexAPI.shared.fetchProfiles(ids: ownerIds)) ?? []
            collectionOwners = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        }
        isLoading = false
    }
}
