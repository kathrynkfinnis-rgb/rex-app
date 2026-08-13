import SwiftUI

/// Collections home — three horizontal shelves, per Kathryn's sketch:
///   1. My Wish Lists — everything you've saved, one shelf per category
///   2. My Collections — lists you've made to share
///   3. Friends' Collections — collections you follow or co-edit
/// Each shelf ends in a "See all" tile that opens the full browsing feed
/// (CollectionsSectionListView). Individual collection tiles open straight
/// into that one collection (CollectionDetailView).
struct CollectionsView: View {
    @State private var wants: [WantRow] = []
    @State private var lists: [RexList] = []
    @State private var followed: [RexList] = []
    @State private var sharedWithMe: [RexList] = []
    @State private var owners: [String: RexProfileDetail] = [:]
    /// Contents of each collection, keyed by list id — drives the shelf
    /// thumbnails and the "x items" counts.
    @State private var contents: [String: [SavedPost]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var creatingCollection = false

    /// The "friends" shelf is followed + collaborating merged — both are
    /// someone else's collection you have access to, just with different
    /// permissions once you're inside it.
    private var friendsLists: [RexList] { followed + sharedWithMe }

    private var wantsByCategory: [(category: RexCategory, items: [WantRow])] {
        var buckets: [RexCategory: [WantRow]] = [:]
        for want in wants {
            let c = RexCategory(rawType: want.items?.type)
            buckets[c, default: []].append(want)
        }
        return rexAllCategories.compactMap { c in
            guard let items = buckets[c], !items.isEmpty else { return nil }
            return (category: c, items: items)
        }
    }

    var body: some View {
        ZStack {
            RexColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.xl) {
                    header

                    if let errorMessage, wants.isEmpty && lists.isEmpty {
                        errorState(errorMessage)
                    } else if let errorMessage {
                        HStack(spacing: RexSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(errorMessage)
                            Spacer()
                            Button("Retry") { Task { await load() } }
                                .font(RexFont.text(13, weight: .semibold))
                        }
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                    }

                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: RexRadius.card)
                                .fill(RexColor.muted)
                                .frame(height: 148)
                        }
                    } else {
                        wishListsShelf
                        myCollectionsShelf
                        friendsCollectionsShelf

                        if wants.isEmpty && lists.isEmpty && friendsLists.isEmpty {
                            empty("Nothing here yet",
                                  "Save a Rex with the bookmark button, or make your first collection.")
                        }
                    }
                }
                .padding(.bottom, RexSpacing.xxxl)
            }
            .refreshable { await load() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingCollection) {
            NewCollectionView { _ in Task { await load() } }
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Collections")
                    .font(RexFont.display(32, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Text("Organise and explore your recommendations")
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.mutedForeground)
            }
            Spacer()
            Button { creatingCollection = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 26))
                    Text("New").font(RexFont.text(11, weight: .semibold))
                }
                .foregroundStyle(RexColor.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, RexSpacing.page)
        .padding(.top, RexSpacing.sm)
    }

    // MARK: - Shelf 1: Wish Lists

    @ViewBuilder
    private var wishListsShelf: some View {
        // Every category with a want already gets its own tile here — there's
        // never a truncated set, so no "see all" tile to reach the rest.
        if !wantsByCategory.isEmpty {
            shelf(title: "Saved Rex", systemImage: "star.fill") {
                ForEach(wantsByCategory, id: \.category) { group in
                    NavigationLink(value: WishListRoute(category: group.category)) {
                        shelfTile(
                            title: headingFor(group.category),
                            count: group.items.count,
                            symbol: group.category.symbol,
                            thumbnails: group.items.prefix(4).compactMap { $0.items?.image_url }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Shelf 2: My Collections

    @ViewBuilder
    private var myCollectionsShelf: some View {
        shelf(title: "My Collections", systemImage: "folder.fill") {
            ForEach(lists.prefix(8)) { list in
                NavigationLink(value: CollectionRoute(listId: list.id, name: list.name, isMine: true)) {
                    shelfTile(
                        title: list.name,
                        count: (contents[list.id] ?? []).count,
                        emoji: list.emoji,
                        locked: list.visibility == "draft",
                        thumbnails: (contents[list.id] ?? []).compactMap { $0.recommendations?.items?.image_url }
                    )
                }
                .buttonStyle(.plain)
            }
            newCollectionTile
            if lists.count > 8 { seeAllTile(destination: .mine) }
        }
    }

    private var newCollectionTile: some View {
        Button { creatingCollection = true } label: {
            VStack(spacing: RexSpacing.sm) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                Text("New").font(RexFont.text(12, weight: .medium)).foregroundStyle(RexColor.mutedForeground)
            }
            .frame(width: 128, height: 128)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                    .stroke(RexColor.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shelf 3: Friends' Collections

    @ViewBuilder
    private var friendsCollectionsShelf: some View {
        if !friendsLists.isEmpty {
            shelf(title: "Friends' Collections", systemImage: "person.2.fill") {
                ForEach(friendsLists.prefix(8)) { list in
                    let isMine = sharedWithMe.contains(where: { $0.id == list.id })
                    NavigationLink(value: CollectionRoute(listId: list.id, name: list.name, isMine: isMine)) {
                        shelfTile(
                            title: list.name,
                            count: (contents[list.id] ?? []).count,
                            emoji: list.emoji,
                            authorInitial: list.user_id.flatMap { owners[$0] }.map { ($0.display_name ?? $0.username).prefix(1).uppercased() },
                            thumbnails: (contents[list.id] ?? []).compactMap { $0.recommendations?.items?.image_url }
                        )
                    }
                    .buttonStyle(.plain)
                }
                if friendsLists.count > 8 { seeAllTile(destination: .friends) }
            }
        }
    }

    // MARK: - Shelf scaffolding

    private func shelf<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            HStack(spacing: RexSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(RexColor.primary)
                Text(title)
                    .font(RexFont.display(19, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
            }
            .padding(.horizontal, RexSpacing.page)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: RexSpacing.md) {
                    content()
                }
                .padding(.horizontal, RexSpacing.page)
            }
        }
    }

    /// One square tile: title, count, and either a 2x2 grid of thumbnails or
    /// an emoji/symbol placeholder when there's nothing to show yet.
    private func shelfTile(
        title: String,
        count: Int,
        emoji: String? = nil,
        symbol: String? = nil,
        locked: Bool = false,
        authorInitial: String? = nil,
        thumbnails: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if thumbnails.isEmpty {
                    RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                        .fill(RexColor.badgeBackground)
                        .overlay(
                            Group {
                                if let emoji { Text(emoji).font(.system(size: 30)) }
                                else if let symbol {
                                    Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(RexColor.primary)
                                }
                            }
                        )
                } else {
                    thumbnailGrid(thumbnails)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.45))
                        .clipShape(Circle())
                        .padding(6)
                }
                if let authorInitial {
                    Text(authorInitial)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RexColor.primaryForeground)
                        .frame(width: 22, height: 22)
                        .background(RexColor.primary)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(RexColor.card, lineWidth: 2))
                        .padding(6)
                }
            }
            .frame(width: 128, height: 128)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))

            Text(title)
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(1)
            Text(count == 1 ? "1 item" : "\(count) items")
                .font(RexFont.text(11))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .frame(width: 128, alignment: .leading)
    }

    @ViewBuilder
    private func thumbnailGrid(_ urls: [String]) -> some View {
        let cells = Array(urls.prefix(4))
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                gridCell(cells.count > 0 ? cells[0] : nil)
                gridCell(cells.count > 1 ? cells[1] : nil)
            }
            GridRow {
                gridCell(cells.count > 2 ? cells[2] : nil)
                gridCell(cells.count > 3 ? cells[3] : nil)
            }
        }
        .background(RexColor.muted)
    }

    @ViewBuilder
    private func gridCell(_ url: String?) -> some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else { RexColor.muted }
                }
            } else {
                RexColor.muted
            }
        }
        .frame(width: 62, height: 62)
        .clipped()
    }

    private func seeAllTile(destination: CollectionsSectionRoute.Section) -> some View {
        NavigationLink(value: CollectionsSectionRoute(section: destination)) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                Text("See all").font(RexFont.text(11, weight: .medium)).foregroundStyle(RexColor.mutedForeground)
            }
            .frame(width: 60, height: 128)
            .frame(maxWidth: .infinity)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous).stroke(RexColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Human headings rather than bare category names.
    private func headingFor(_ c: RexCategory) -> String {
        switch c {
        case .place: return "Places to go"
        case .trip: return "Trips to take"
        case .book: return "Books to read"
        case .movie: return "Films to watch"
        case .tv: return "TV to watch"
        case .podcast: return "Podcasts to hear"
        case .recipe: return "Recipes to cook"
        case .event: return "Events to attend"
        case .other: return "Other"
        }
    }

    private func empty(_ title: String, _ body: String) -> some View {
        VStack(spacing: RexSpacing.sm) {
            Text(title)
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text(body)
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, RexSpacing.page)
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
        .padding(.horizontal, RexSpacing.page)
    }

    private func load() async {
        isLoading = wants.isEmpty && lists.isEmpty
        errorMessage = nil
        do {
            async let w = RexAPI.shared.fetchWants()
            async let l = RexAPI.shared.fetchLists()
            async let f = RexAPI.shared.fetchFollowedLists()
            async let c = RexAPI.shared.fetchCollaboratingLists()
            let (fw, fl, ff, fc) = try await (w, l, f, c)
            wants = fw
            lists = fl
            followed = ff
            sharedWithMe = fc

            // Credit whoever owns the collections you didn't make.
            let ownerIds = Array(Set((ff + fc).compactMap { $0.user_id }))
            if !ownerIds.isEmpty {
                let profiles = (try? await RexAPI.shared.fetchProfiles(ids: ownerIds)) ?? []
                owners = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            }

            await loadContents(for: fl + ff + fc)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Fetch every collection's contents at once so the shelf thumbnails and
    /// counts have something to work with.
    private func loadContents(for allLists: [RexList]) async {
        let fetched = await withTaskGroup(of: (String, [SavedPost]).self) { group in
            for list in allLists {
                group.addTask {
                    let rows = (try? await RexAPI.shared.fetchCollectionItems(listId: list.id)) ?? []
                    return (list.id, rows)
                }
            }
            var result: [String: [SavedPost]] = [:]
            for await (id, rows) in group { result[id] = rows }
            return result
        }
        contents = fetched
    }
}
