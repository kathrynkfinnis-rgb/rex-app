import SwiftUI
import CoreLocation

/// Deliveroo-homepage-style discovery surface: category pills up top,
/// horizontally-swipeable shelves stacked underneath. Three sources mixed
/// together — friends' collections you haven't followed yet, Rex-team
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
    /// Oct 9 — the places-with-no-pin entry, moved here off the map. Reuses
    /// the admin answer this screen already asks for rather than a second
    /// round trip for the same question.
    @State private var isAdmin = false
    @State private var pinlessCount = 0
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
        // Oct 8 — "can we populate these with stuff even if not Rex'd that
        // much." A shelf used to require two people to have Rex'd the same
        // thing, which is a fair definition of "most Rex'd" and a poor one
        // for an app this size: with a few dozen users almost everything has
        // exactly one Rex, so the recipes shelf held one recipe and the
        // events shelf one event. A shelf with a single card in it reads as
        // though the app is empty, which is worse than a looser claim.
        //
        // Everything qualifies now, still ordered by how many people agree,
        // so the genuinely-agreed ones keep the front of the shelf and the
        // rest fill it out behind them. The badge below tells the truth about
        // which of those two a given shelf actually is.
        var byCategory: [RexCategory: [(rec: FeedRecommendation, count: Int)]] = [:]
        for (_, recs) in byItem {
            guard let first = recs.first else { continue }
            byCategory[RexCategory(rawType: first.items?.type), default: []].append((first, recs.count))
        }
        return rexAllCategories
            .filter { filter == nil || $0 == filter }
            .compactMap { category in
                guard let recs = byCategory[category], !recs.isEmpty else { return nil }
                return (category, recs.sorted { $0.count > $1.count }.prefix(shelfLimit).map { $0 })
            }
    }

    /// Oct 3 — "can we increase the limit on the scroll here to 20 items?"
    /// Ten was a guess from when there was barely anything to show; a shelf
    /// that runs out after ten reads as though the app has nothing more.
    private let shelfLimit = 20

    /// Where your friends have been lately — trips get their own shelf
    /// rather than sitting in the per-category rows, because a trip is the
    /// thing people most want to borrow whole.
    private var recentTrips: [FeedRecommendation] {
        recentRex
            .filter { RexCategory(rawType: $0.items?.type) == .trip && !$0.isWant && !$0.isBlast }
            .prefix(shelfLimit)
            .map { $0 }
    }

    /// Oct 12 — "this is duplicative in Explore — it should only come up once
    /// and then say Rex'd by two people." MobLand appeared twice on the TV
    /// shelf because Liv and Ollie had both Rex'd it, and this shelf was built
    /// one tile per row. The shelf above it has grouped by item since it was
    /// written; this one never did, so the same screen answered the same
    /// question two different ways.
    ///
    /// One tile per thing, keeping the most recent Rex of it — the shelf is
    /// ordered by recency, so the newest is the row that earned its place.
    /// The count rides along for the caption.
    private var recentByCategory: [(category: RexCategory, recs: [(rec: FeedRecommendation, count: Int)])] {
        var byItem: [String: [FeedRecommendation]] = [:]
        var order: [String] = []
        for rec in recentRex where !rec.isWant && !rec.isBlast {
            if byItem[rec.item_id] == nil { order.append(rec.item_id) }
            byItem[rec.item_id, default: []].append(rec)
        }
        var byCategory: [RexCategory: [(rec: FeedRecommendation, count: Int)]] = [:]
        for itemId in order {
            guard let recs = byItem[itemId], let first = recs.first else { continue }
            byCategory[RexCategory(rawType: first.items?.type), default: []].append((first, recs.count))
        }
        // This used to need two before a category earned a shelf, which on a
        // young app meant most of them were thrown away and the page read as
        // empty. One is enough — one real recommendation from a friend beats
        // a blank screen.
        return rexAllCategories
            .filter { filter == nil || $0 == filter }
            .compactMap { category in
                guard let recs = byCategory[category], !recs.isEmpty else { return nil }
                return (category, Array(recs.prefix(shelfLimit)))
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
                        hotSection
                        friendsSections
                    } else {
                        hotSection
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
            .task {
                isCurator = await RexAPI.shared.isAdmin()
                isAdmin = isCurator
                if isAdmin {
                    pinlessCount = await RexAPI.shared.fetchUnpinnedPlaces().count
                }
            }
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
    @ViewBuilder
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

        // Oct 9 — the places-with-no-pin screen moved off the map, where it
        // had become a permanent row on the screen you use most once the
        // backlog was down to eighteen. It lives here instead: admin only,
        // quiet, and findable when you want to chip away at the tail.
        if isAdmin, pinlessCount > 0 {
            NavigationLink(value: PlacesWithoutPinRoute()) {
                HStack(spacing: RexSpacing.sm) {
                    Image(systemName: "mappin.slash").font(.system(size: 13))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    Text("\(pinlessCount) \(pinlessCount == 1 ? "place isn't" : "places aren't") on the map")
                        .font(RexFont.text(14))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(RexColor.mutedForeground)
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
    }

    /// where they've been, what they've collected, then the rest by category.
    @ViewBuilder
    private var friendsSections: some View {
        if mostRexdByCategory.isEmpty && recentTrips.isEmpty
            && visibleFriendsCollections.isEmpty && recentByCategory.isEmpty {
            emptyState
        } else {
            ForEach(mostRexdByCategory, id: \.category) { group in
                // "Agreed on" only when somebody actually agreed — otherwise
                // the shelf is simply what your friends have Rex'd, and
                // saying so is better than a badge that isn't true.
                let agreed = group.recs.first?.count ?? 0 > 1
                shelf(
                    title: agreed
                        ? "Most Rex'd \(group.category.pluralLabel.lowercased())"
                        : "\(group.category.pluralLabel) your friends rate",
                    tag: agreed ? "AGREED ON" : "FRIENDS"
                ) {
                    ForEach(group.recs, id: \.rec.id) { entry in
                        Button { openRex(entry.rec) } label: {
                            recentRexCard(entry.rec, rexdBy: entry.count)
                        }
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
                    ForEach(group.recs, id: \.rec.id) { entry in
                        Button { openRex(entry.rec) } label: {
                            recentRexCard(entry.rec, rexdBy: entry.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Curated by the Rex team, plus what the whole app is Rexing this week.
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
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
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
            Text("This is where Rex's own picks will live. In the meantime, Rex from friends is the good stuff.")
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



    /// The shelf tile, deciding what to show rather than being handed a URL.
    ///
    /// Nov 22, from the Explore mock-ups: option B (a designed fallback
    /// rather than a bad photo) and option C (only trust catalogue art).
    ///
    /// The three faults this answers all came from one fact — the shelves
    /// showed `items.image_url` and nothing else. A film has a poster behind
    /// it and a book has a jacket, but products, events and "other" have no
    /// catalogue at all, so whatever somebody uploaded became the item's
    /// official picture. That is how Operation Mincemeat ended up a
    /// screenshot with app UI in it, and how two different car seat products
    /// came to share one photograph of a Volvo seat.
    private func shelfThumbnail(_ art: ShelfArt, symbol: String) -> some View {
        ShelfTileArt(art: art, symbol: symbol)
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

    /// Oct 15 — "can we please have a hot section on the Explore?"
    ///
    /// Trending already existed, but split one shelf per category and filed
    /// under the Rexperts tab, which is where Rex's own picks live — so what
    /// everybody is actually Rexing this week was three taps from the top and
    /// read as editorial. Hot is a different claim from a curated shelf: it
    /// is nobody's opinion, just what is moving.
    ///
    /// One row, every category together, busiest first, above both tabs —
    /// because what's hot is a fact about the app rather than about which
    /// half of it you are looking at. The per-category trending shelves stay
    /// where they are for browsing a kind of thing.
    @ViewBuilder
    private var hotSection: some View {
        let hot = visibleTrending
            .sorted { $0.rex_count > $1.rex_count }
            .prefix(12)
        // Two people Rexing the same thing in a week is a coincidence; the
        // shelf should only claim heat when there is some.
        if hot.contains(where: { $0.rex_count >= 3 }) {
            shelf(title: "Hot right now", tag: "THIS WEEK") {
                ForEach(Array(hot)) { item in
                    hotCard(item)
                }
            }
        }
    }

    private func hotCard(_ item: TrendingItem) -> some View {
        Button {
            pushedItemId = item.item_id
        } label: {
            VStack(alignment: .leading, spacing: RexSpacing.xs) {
                ZStack(alignment: .topLeading) {
                    shelfThumbnail(ShelfArt.forTrending(item),
                                   symbol: RexCategory(rawType: item.type).symbol)
                    // The same flame a card gets when enough people pile on.
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(RexColor.primary, in: Circle())
                        .padding(6)
                }
                Text(item.title)
                    .font(RexFont.text(12.5, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(item.rex_count) Rex this week")
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.primary)
                    .lineLimit(1)
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
                shelfThumbnail(ShelfArt.forTrending(item),
                                   symbol: RexCategory(rawType: item.type).symbol)
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

    /// `rexdBy` is how many people Rex'd this thing, not how many rows the
    /// shelf collapsed: a name is the better caption when there is one person
    /// to name, and a count is the only honest one when there are more.
    private func recentRexCard(_ rec: FeedRecommendation, rexdBy count: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.xs) {
            shelfThumbnail(ShelfArt.forRecent(rec),
                           symbol: RexCategory(rawType: rec.items?.type).symbol)
            Text(rec.items?.title ?? "")
                .font(RexFont.text(12.5, weight: .medium))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let caption = count > 1
                ? "Rex\u{2019}d by \(count) people"
                : rec.profiles?.display_name ?? rec.profiles?.username {
                Text(caption)
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
                    // Oct 14 — "when I click on a list it should take me to
                    // the list with the component Rexes." A list is the same
                    // shape of thing as a trip: a page whose point is what is
                    // inside it. On 3 October the trip got its own route here
                    // and the list did not, so a curated list opened its bare
                    // item page — the title, the Rex account, a review, and
                    // none of the podcasts it was recommending.
                    if item.isTrip {
                        Task { await openTrip(itemId: itemId, title: item.title) }
                    } else if item.isList {
                        Task { await openList(itemId: itemId, title: item.title) }
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

    /// Same lookup openTrip does: the page is addressed by the recommendation
    /// rather than the item, and a shelf holds item ids.
    private func openList(itemId: String, title: String) async {
        if let recs = try? await RexAPI.shared.fetchRecommendations(forItem: itemId),
           let list = recs.first {
            pushedList = ListRoute(recommendationId: list.id, title: title)
        } else {
            pushedItemId = itemId
        }
    }

    private func editorialCardBody(_ item: EditorialCollectionItem) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.xs) {
            // A curated shelf is the one place option C has nothing to say:
            // a person on the Rex team chose this picture, so it is trusted
            // whatever its source. The fallback still improves — a title on
            // the category's colour rather than a generic sparkle.
            shelfThumbnail(
                {
                    let category = RexCategory(rawType: item.items?.type)
                    if let url = item.image_url, !url.isEmpty {
                        return ShelfArt.photo(url, titleFallback: item.title, category: category)
                    }
                    return ShelfArt.titled(item.title, category)
                }(),
                symbol: "sparkles"
            )
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

/// What a shelf tile should actually show. Decided once, at the call site
/// that has the facts, rather than inside the view.
enum ShelfArt {
    /// A picture we are prepared to vouch for, and the cover to show while
    /// it loads and if it never arrives. A signed URL whose file has been
    /// deleted 404s, and the tile used to sit there as an empty grey box
    /// with no title and no glyph on it — found by actually looking at one.
    case photo(String, titleFallback: String, category: RexCategory)
    /// Several people's photos of the same thing — Explore's shelf is called
    /// "most Rex'd", and one person's picture undersells that.
    case mosaic([String])
    /// A trip with no photographs on any of its stops: a map of where it
    /// went, which is the one thing a trip can always say about itself.
    case map([CLLocationCoordinate2D], titleFallback: String)
    /// No picture worth showing: set the title on the category's colour.
    case titled(String, RexCategory)
}

extension ShelfArt {
    /// Option C, in one place: is this image the thing it claims to be?
    ///
    /// The obvious test — "is it hosted on our own storage?" — does not work,
    /// and the reason is worth keeping written down. repairPlacePhotoIfNeeded
    /// copies a Google Place photo into our bucket through the same
    /// uploadPhoto() a person's own camera roll goes through, landing at the
    /// same rec-photos/<user-id>/<uuid>.jpg. A Google photo and a snapshot
    /// are indistinguishable by URL.
    ///
    /// `external_source` is the signal that survives. It is set when the item
    /// came from a lookup (Google for a place, TMDB for a film, Open Library
    /// for a book) and null when somebody typed the thing in by hand — which
    /// is precisely the case that produces a bad thumbnail.
    ///
    /// An item with no lookup behind it can still have a good picture: the
    /// product shots scraped from a shop's own page (spacenk.com,
    /// balzac-paris.com, nordicnest) are photographs of the thing being sold.
    /// Those are kept. What is dropped is the narrow case of a hand-typed
    /// item whose image is an upload — a camera roll promoted to catalogue.
    static func trusted(
        imageURL: String?,
        externalSource: String?,
        title: String,
        type: String?
    ) -> ShelfArt {
        let category = RexCategory(rawType: type)
        guard let imageURL, !imageURL.isEmpty else {
            return .titled(title, category)
        }
        let hasLookup = !(externalSource ?? "").isEmpty
        let isOurUpload = imageURL.contains("/storage/v1/object/")
        if isOurUpload && !hasLookup {
            return .titled(title, category)
        }
        return .photo(imageURL, titleFallback: title, category: category)
    }
}

extension ShelfArt {
    /// The whole decision for one Explore tile, in the order the options
    /// were agreed: a trip's own pictures, then several people's pictures,
    /// then catalogue art, then a title.
    static func forTrending(_ item: TrendingItem) -> ShelfArt {
        let category = RexCategory(rawType: item.type)

        // (A) "For trips, default to a hero photo if there is one rather
        // than mini maps, but if none, then map." A trip carries no
        // catalogue picture, so both come from its stops.
        if category == .trip {
            let photos = (item.trip_photos ?? []).filter { !$0.isEmpty }
            if photos.count > 1 { return .mosaic(photos) }
            if let only = photos.first {
                return .photo(only, titleFallback: item.title, category: category)
            }
            let lats = item.trip_lats ?? []
            let lngs = item.trip_lngs ?? []
            let coords = zip(lats, lngs).map {
                CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1)
            }
            if !coords.isEmpty { return .map(coords, titleFallback: item.title) }
            return .titled(item.title, category)
        }

        // (D) A mosaic where several people have Rex'd the same thing —
        // but only where a personal photograph IS the picture of the thing.
        // A restaurant photographed by four friends is the shelf working;
        // four phone snaps of a car seat bag is the fault option C exists
        // to fix, four times over. So the catalogue categories keep their
        // jacket or poster, and so does anything C would not trust.
        if category.showsPeoplesOwnPhotos {
            let photos = (item.rex_photos ?? []).filter { !$0.isEmpty }
            if photos.count > 1 { return .mosaic(photos) }
        }

        // (C and B)
        return .trusted(imageURL: item.image_url, externalSource: item.external_source,
                        title: item.title, type: item.type)
    }
}

extension ShelfArt {
    /// The same decision for the "lately" shelves, which are built from
    /// recommendations rather than the trending RPC — so the photographs
    /// are already in hand and need no extra column.
    static func forRecent(_ rec: FeedRecommendation) -> ShelfArt {
        let category = RexCategory(rawType: rec.items?.type)
        let title = rec.items?.title ?? ""
        if category.showsPeoplesOwnPhotos {
            var photos = rec.photo_urls ?? []
            if photos.isEmpty, let single = rec.photo_url { photos = [single] }
            photos = photos.filter { !$0.isEmpty }
            if photos.count > 1 { return .mosaic(photos) }
            if let only = photos.first {
                return .photo(only, titleFallback: title, category: category)
            }
        }
        return .trusted(imageURL: rec.items?.image_url,
                        externalSource: rec.items?.external_source,
                        title: title, type: rec.items?.type)
    }
}

extension RexCategory {
    /// Categories where the thing has no jacket, poster or cover, so the
    /// picture people take of it IS its picture. Used to decide whether a
    /// mosaic of several people's photos is an improvement on one image or
    /// a pile of camera roll.
    var showsPeoplesOwnPhotos: Bool {
        switch self {
        case .place, .trip, .event, .recipe: return true
        case .book, .movie, .tv, .podcast, .list, .other: return false
        }
    }
}

/// One shelf tile's artwork, at the size Explore draws it.
///
/// `symbol` is the old SF Symbol fallback, kept only for the paths that have
/// no title to set (a curated shelf row whose item has been deleted). Where
/// there is a title, `.titled` is the better answer: it says what the thing
/// is, which a generic glyph never did, and it makes two pictureless tiles
/// look like two different things rather than the same grey square twice.
struct ShelfTileArt: View {
    let art: ShelfArt
    var symbol: String = "square"
    var width: CGFloat = 132
    var height: CGFloat = 96

    var body: some View {
        Group {
            switch art {
            case .photo(let url, let fallbackTitle, let category):
                if let parsed = URL(string: url) {
                    GoogleSafeAsyncImage(url: parsed) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        // Not RexColor.muted: this placeholder is shown
                        // while loading AND when the load fails, and a
                        // blank grey square is the worst of the three
                        // things this tile can be.
                        titled(fallbackTitle, category)
                    }
                } else {
                    titled(fallbackTitle, category)
                }
            case .mosaic(let urls):
                if urls.count > 1 {
                    ThumbnailGridView(urls: urls)
                } else if let only = urls.first, let parsed = URL(string: only) {
                    GoogleSafeAsyncImage(url: parsed) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RexColor.muted
                    }
                } else {
                    glyph
                }
            case .map(let coords, let fallbackTitle):
                if coords.isEmpty {
                    titled(fallbackTitle, .trip)
                } else {
                    RexMapSnapshotView(coordinates: coords, height: height)
                }
            case .titled(let title, let category):
                titled(title, category)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
    }

    private var glyph: some View {
        RexColor.muted.overlay(
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(RexColor.mutedForeground)
        )
    }

    /// Option B. A wash of the category's own colour, the title set on top,
    /// and the category's glyph sitting quietly in the corner so the tile
    /// still says what kind of thing this is.
    ///
    /// Set in the display face rather than the editorial one the mock-up
    /// used. Two reasons: Theme's editorial face is italic-only here and goes
    /// delicate at the size a 132pt tile allows, and the house rule on that
    /// face is that it is spent quickly — it reads as a voice, and a cover is
    /// a title. One line to change if the serif is wanted.
    private func titled(_ title: String, _ category: RexCategory) -> some View {
        let tint = category.tintColor
        return ZStack(alignment: .topLeading) {
            tint.opacity(0.14)
            Image(systemName: category.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint.opacity(0.75))
                .padding(7)
            Text(title)
                .font(RexFont.display(13))
                .foregroundStyle(tint)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }
}
