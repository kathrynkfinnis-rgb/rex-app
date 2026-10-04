import SwiftUI

/// Deliveroo-homepage-style discovery surface: category pills up top,
/// horizontally-swipeable shelves stacked underneath. Three sources mixed
/// together — friends' collections you haven't followed yet, REX-team
/// curated picks (and anything credited to an outside source, both typed
/// in by the same three people), and what's trending across the app this
/// week. Reached from the Explore tab, not the logo — see FeedView/
/// MainTabView for the nav rework that made room for a dedicated tab.
struct ExploreView: View {
    /// Sept 21 — "two buttons at the top: 'Rex from Friends' and 'Rex from
    /// Rexperts'". Friends is the default, and is a condensed version of the
    /// feed: what your friends have Rex'd most, and where they've been.
    /// Rexperts is the curated and app-wide material that used to be mixed
    /// in with it — which was most of why this page looked empty.
    enum ExploreSource: String, CaseIterable {
        case friends, rexperts
        var label: String { self == .friends ? "Rex from friends" : "Rex from Rexperts" }
    }
    @State private var source: ExploreSource = .friends
    @State private var filter: RexCategory?
    @State private var friendsCollections: [RexList] = []
    @State private var collectionOwners: [String: RexProfileDetail] = [:]
    @State private var friendCollectionThumbnails: [String: [String]] = [:]
    @State private var trending: [TrendingItem] = []
    @State private var editorial: [EditorialCollection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pushedItemId: String?
    @State private var showingTalkToRex = false
    /// Oct 1 — the three curators get a way in to the shelves they own.
    @State private var isCurator = false
    @State private var pushedCollection: CollectionRoute?
    @State private var pushedTrip: TripRoute?
    @State private var pushedList: ListRoute?
    /// #169 — moved here from the main feed (#17's "trial"); this is where
    /// Deliveroo-style category browsing belongs, alongside every other
    /// horizontal discovery shelf, rather than sitting above the vertical
    /// feed competing with it for the same screen.
    @State private var recentRex: [FeedRecommendation] = []

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
    /// "Under 'trending this week' separate list between places, books,
    /// etc" — one combined shelf mixed every category together; this
    /// mirrors recentByCategory's own per-category grouping just below it
    /// on the same screen, same idea applied to trending instead of recent.
    private var trendingByCategory: [(category: RexCategory, items: [TrendingItem])] {
        var byCategory: [RexCategory: [TrendingItem]] = [:]
        for item in visibleTrending {
            byCategory[RexCategory(rawType: item.type), default: []].append(item)
        }
        return rexAllCategories.compactMap { category in
            guard let items = byCategory[category], !items.isEmpty else { return nil }
            return (category, items)
        }
    }
    private var visibleEditorial: [EditorialCollection] {
        // A shelf with no category is general-interest — only hide it once
        // a specific filter is chosen and it plainly doesn't match.
        editorial.filter { $0.category == nil || matches($0.category) }
    }

    /// One shelf per category, same grouping FeedView's own categoryShelves
    /// used before #169 moved it here. Respects the same filter row every
    /// other shelf on this screen already does.
    /// The same thing Rex'd by more than one friend, most first — the
    /// closest honest answer to "most Rex'd" from the rows this tab already
    /// has. One card per thing, not one per friend.
    private var mostRexdByCategory: [(category: RexCategory, recs: [(rec: FeedRecommendation, count: Int)])] {
        var byItem: [String: [FeedRecommendation]] = [:]
        for rec in recentRex where !rec.isWant && !rec.isBlast && RexCategory(rawType: rec.items?.type) != .trip {
            byItem[rec.item_id, default: []].append(rec)
        }
        var byCategory: [RexCategory: [(rec: FeedRecommendation, count: Int)]] = [:]
        for (_, recs) in byItem {
            guard let first = recs.first, recs.count > 1 else { continue }
            byCategory[RexCategory(rawType: first.items?.type), default: []].append((first, recs.count))
        }
        return rexAllCategories
            .filter { filter == nil || $0 == filter }
            .compactMap { category in
                guard let recs = byCategory[category], !recs.isEmpty else { return nil }
                return (category, recs.sorted { $0.count > $1.count }.prefix(10).map { $0 })
            }
    }

    /// Where your friends have been lately — trips get their own shelf
    /// rather than sitting in the per-category rows, because a trip is the
    /// thing people most want to borrow whole.
    private var recentTrips: [FeedRecommendation] {
        recentRex
            .filter { RexCategory(rawType: $0.items?.type) == .trip && !$0.isWant && !$0.isBlast }
            .prefix(10)
            .map { $0 }
    }

    private var recentByCategory: [(category: RexCategory, recs: [FeedRecommendation])] {
        var byCategory: [RexCategory: [FeedRecommendation]] = [:]
        for rec in recentRex where !rec.isWant && !rec.isBlast {
            byCategory[RexCategory(rawType: rec.items?.type), default: []].append(rec)
        }
        // This used to need two before a category earned a shelf, which on a
        // young app meant most of them were thrown away and the page read as
        // empty. One is enough — one real recommendation from a friend beats
        // a blank screen.
        return rexAllCategories
            .filter { filter == nil || $0 == filter }
            .compactMap { category in
                guard let recs = byCategory[category], !recs.isEmpty else { return nil }
                return (category, Array(recs.prefix(10)))
            }
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
                    talkToRexBar
                    sourceToggle
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
                    } else if source == .friends {
                        friendsSections
                    } else {
                        rexpertsSections
                    }
                }
                .padding(.bottom, RexSpacing.xxl)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $pushedItemId) { ItemDetailView(itemId: $0) }
            .navigationDestination(item: $pushedCollection) { CollectionDetailView(route: $0) }
            .navigationDestination(item: $pushedTrip) { TripDetailView(route: $0) }
            .navigationDestination(item: $pushedList) { ListDetailView(route: $0) }
            .navigationDestination(isPresented: $showingTalkToRex) {
                TalkToRexView(onOpenItem: { pushedItemId = $0 })
            }
            .navigationDestination(for: CuratorShelvesRoute.self) { _ in CuratorShelvesView() }
            .refreshable { await load() }
            .task { await load() }
            .task { isCurator = await RexAPI.shared.isAdmin() }
        }
        .tint(RexColor.primary)
    }

    private var sourceToggle: some View {
        HStack(spacing: RexSpacing.sm) {
            ForEach(ExploreSource.allCases, id: \.self) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { source = option }
                } label: {
                    Text(option.label)
                        .font(RexFont.text(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(source == option ? RexColor.primary : RexColor.card)
                        .foregroundStyle(source == option ? RexColor.primaryForeground : RexColor.foreground)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(source == option ? Color.clear : RexColor.border, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, RexSpacing.page)
        .padding(.top, RexSpacing.md)
    }

    /// A condensed version of the feed: what more than one friend has Rex'd,
    /// Sept 29 — "we'd like to make the Explore page more conversational and
    /// AI-led", with "still want the ability to scroll through most Rex'd
    /// and/or external experts' ideas".
    ///
    /// So this sits above everything and takes nothing away. Browsing is still
    /// what you land on; talking is what you reach for. It's a bar rather than
    /// the screen itself because an empty box is a worse first impression than
    /// a shelf of your friends' recommendations.
    private var talkToRexBar: some View {
        Button {
            showingTalkToRex = true
        } label: {
            HStack(spacing: RexSpacing.sm) {
                // Oct 3 — "should be 'ask Rex' and should have the dino
                // icon." The name changed and the icon didn't follow; a
                // sparkle is the generic mark every app uses for a model,
                // which is precisely what this isn't — the answers come from
                // people you know.
                Image("RexDinoLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                Text("Ask Rex — ask for anything")
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.mutedForeground)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
            }
            .padding(.horizontal, RexSpacing.md)
            .frame(height: 46)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, RexSpacing.page)
        .padding(.bottom, RexSpacing.md)
    }

    /// where they've been, what they've collected, then the rest by category.
    @ViewBuilder
    private var friendsSections: some View {
        if mostRexdByCategory.isEmpty && recentTrips.isEmpty
            && visibleFriendsCollections.isEmpty && recentByCategory.isEmpty {
            emptyState
        } else {
            ForEach(mostRexdByCategory, id: \.category) { group in
                shelf(title: "Most Rex'd \(group.category.pluralLabel.lowercased())", tag: "AGREED ON") {
                    ForEach(group.recs, id: \.rec.id) { entry in
                        Button { openRex(entry.rec) } label: { recentRexCard(entry.rec) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if !recentTrips.isEmpty, filter == nil || filter == .trip {
                shelf(title: "Recent trips", tag: "FRIENDS") {
                    ForEach(recentTrips) { rec in
                        Button { openRex(rec) } label: { recentRexCard(rec) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if !visibleFriendsCollections.isEmpty {
                shelf(title: "Collections you haven't followed", tag: "FRIENDS") {
                    ForEach(visibleFriendsCollections) { list in
                        friendCollectionCard(list)
                    }
                }
            }
            ForEach(recentByCategory, id: \.category) { group in
                shelf(title: group.category.label, tag: "RECENT") {
                    ForEach(group.recs) { rec in
                        Button { openRex(rec) } label: { recentRexCard(rec) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Curated by the REX team, plus what the whole app is Rexing this week.
    /// Only the three named curators see this, and only on the Rexperts tab —
    /// it's the page the shelves appear on, so it's where editing them
    /// belongs. is_rex_curator() is the real gate; this is just the door.
    @ViewBuilder
    private var curatorBar: some View {
        if isCurator {
            NavigationLink(value: CuratorShelvesRoute()) {
                HStack(spacing: RexSpacing.sm) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 13))
                    Text("Manage Rexperts shelves")
                        .font(RexFont.text(14, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(RexColor.primary)
                .padding(.horizontal, RexSpacing.md)
                .frame(height: 44)
                .background(RexColor.badgeBackground)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, RexSpacing.page)
            .padding(.bottom, RexSpacing.md)
        }
    }

    @ViewBuilder
    private var rexpertsSections: some View {
        curatorBar
        if visibleEditorial.isEmpty && visibleTrending.isEmpty {
            rexpertsEmptyState
        } else {
            ForEach(visibleEditorial) { collection in
                if !collection.items.isEmpty {
                    shelf(title: collection.title, tag: collection.source_label.uppercased()) {
                        ForEach(collection.items) { item in
                            editorialCard(item)
                        }
                    }
                }
            }
            ForEach(trendingByCategory, id: \.category) { group in
                shelf(title: group.category.pluralLabel, tag: "POPULAR") {
                    ForEach(group.items) { item in
                        trendingCard(item)
                    }
                }
            }
        }
    }

    private var rexpertsEmptyState: some View {
        VStack(spacing: RexSpacing.sm) {
            // Kathryn's hard-hat Rex — this shelf genuinely is under
            // construction rather than empty, and the difference matters.
            Image("RexUnderConstruction").resizable().scaledToFit().frame(width: 120, height: 120)
            Text("Nothing from the Rexperts yet")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("This is where REX's own picks will live. In the meantime, Rex from friends is the good stuff.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
            Button("See Rex from friends") {
                withAnimation(.easeOut(duration: 0.15)) { source = .friends }
            }
            .font(RexFont.text(14, weight: .semibold))
            .foregroundStyle(RexColor.primary)
            .padding(.top, RexSpacing.xs)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RexSpacing.sm) {
                filterChip("All", isSelected: filter == nil) { filter = nil }
                ForEach(filterOptions, id: \.self) { category in
                    filterChip(category.pluralLabel, isSelected: filter == category) { filter = category }
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
                GoogleSafeAsyncImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RexColor.muted
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
                Group {
                    if let thumbs = friendCollectionThumbnails[list.id], !thumbs.isEmpty {
                        ThumbnailGridView(urls: thumbs)
                    } else {
                        ZStack {
                            RexColor.badgeBackground
                            Text(list.emoji ?? "\u{1F4D2}").font(.system(size: 30))
                        }
                    }
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

    /// Same 3-way routing as FeedView.open(), minus the blast/want branches
    /// — recentByCategory already excludes both.
    private func openRex(_ rec: FeedRecommendation) {
        switch RexCategory(rawType: rec.items?.type) {
        case .trip:
            pushedTrip = TripRoute(recommendationId: rec.id, title: rec.items?.title ?? "Trip")
        case .list:
            pushedList = ListRoute(recommendationId: rec.id, title: rec.items?.title ?? "List")
        default:
            pushedItemId = rec.item_id
        }
    }

    private func recentRexCard(_ rec: FeedRecommendation) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.xs) {
            shelfThumbnail(url: rec.items?.image_url, symbol: RexCategory(rawType: rec.items?.type).symbol)
            Text(rec.items?.title ?? "")
                .font(RexFont.text(12.5, weight: .medium))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let who = rec.profiles?.display_name ?? rec.profiles?.username {
                Text(who)
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(1)
            }
        }
        .frame(width: 132, alignment: .leading)
    }

    @ViewBuilder
    private func editorialCard(_ item: EditorialCollectionItem) -> some View {
        Group {
            if let itemId = item.item_id {
                Button {
                    // Oct 3 — a trip on a shelf opens its itinerary, not the
                    // bare item page, which showed the overview and none of
                    // the stops. TripDetailView is addressed by the trip's
                    // recommendation, so that's looked up on tap rather than
                    // fetched for every card on the shelf.
                    if item.isTrip {
                        Task { await openTrip(itemId: itemId, title: item.title) }
                    } else {
                        pushedItemId = itemId
                    }
                } label: { editorialCardBody(item) }
                    .buttonStyle(.plain)
            } else if let linkString = item.link_url, let url = URL(string: linkString) {
                RexOutboundLinkButton(url: url) { editorialCardBody(item) }
            } else {
                editorialCardBody(item)
            }
        }
    }

    /// Finds the recommendation behind a trip item so its itinerary can open.
    /// Falls back to the item page rather than doing nothing: a shelf trip
    /// whose Rex has since been deleted should still open something.
    private func openTrip(itemId: String, title: String) async {
        if let recs = try? await RexAPI.shared.fetchRecommendations(forItem: itemId),
           let trip = recs.first {
            pushedTrip = TripRoute(recommendationId: trip.id, title: title)
        } else {
            pushedItemId = itemId
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
        // TestFlight feedback (Aug 27): "We should show 10 for each
        // 'recent' category" — recentByCategory already takes prefix(10)
        // per category, but the single plain fetchFeed() call this used to
        // draw from is itself capped at 50 rows total across every
        // category combined. A quiet week for, say, films meant that
        // shelf could end up with 2 recent items even though 30 exist
        // further back, just because they'd aged out of the shared top-50
        // sample. Fetching one page per category (each already
        // server-filtered and ordered newest-first) guarantees every
        // shelf gets its own up-to-10, independent of how active the
        // other categories have been.
        async let recentTask: [FeedRecommendation] = withTaskGroup(of: [FeedRecommendation].self) { group in
            for category in rexAllCategories {
                group.addTask { (try? await RexAPI.shared.fetchFeed(category: category.rawValue)) ?? [] }
            }
            var all: [FeedRecommendation] = []
            for await page in group { all.append(contentsOf: page) }
            return all
        }
        friendsCollections = (try? await friendsTask) ?? []
        trending = (try? await trendingTask) ?? []
        editorial = (try? await editorialTask) ?? []
        recentRex = await recentTask

        let ownerIds = Array(Set(friendsCollections.compactMap(\.user_id)))
        if !ownerIds.isEmpty {
            let profiles = (try? await RexAPI.shared.fetchProfiles(ids: ownerIds)) ?? []
            collectionOwners = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        }

        // #131 — a friend-collection card was just an emoji placeholder,
        // giving the shelf no colour of its own. Same fetch-per-list
        // pattern CollectionsView already uses for its own shelf tiles.
        friendCollectionThumbnails = await withTaskGroup(of: (String, [String]).self) { group in
            for list in friendsCollections {
                group.addTask {
                    let items = (try? await RexAPI.shared.fetchCollectionItems(listId: list.id)) ?? []
                    return (list.id, items.compactMap { $0.recommendations?.items?.image_url })
                }
            }
            var result: [String: [String]] = [:]
            for await (id, urls) in group { result[id] = urls }
            return result
        }

        isLoading = false
    }
}
