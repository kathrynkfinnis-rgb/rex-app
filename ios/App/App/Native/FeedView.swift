import SwiftUI

struct NotificationsRoute: Hashable {}

struct FeedView: View {
    var onSignedOut: () -> Void
    /// Incremented by the tab bar when Feed is tapped while already active.
    var popToRootSignal: Int = 0
    /// Friends moved up here from the bottom tab bar, per Kathryn's ask —
    /// Friends is still a real tab (MainTabView keeps it alive so its own
    /// scroll position/state survive), this just switches `selection` to
    /// it instead of being reachable from the bottom bar directly.
    var onFriendsTap: () -> Void = {}
    /// Bumped by MainTabView's raised "+" button (Add-a-Rex moved back
    /// there, per Kathryn's ask) whenever that sheet dismisses, so the feed
    /// picks up whatever was just posted the same way it always has.
    var addRexRefreshSignal: Int = 0
    /// #133 "view on map" — MainTabView switches to the Map tab and jumps
    /// to this item's pin.
    var onViewOnMap: ((String) -> Void)? = nil

    @State private var path = NavigationPath()

    @State private var recommendations: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// A sheet, not a NavigationLink push — see the comment on the avatar
    /// button for why.
    @State private var showingProfile = false
    @State private var filter: RexCategory?
    @State private var subFilter: String?
    @State private var blastsOnly = false
    /// Independent of category/genre — "Loved places" and "Loved books" are
    /// both valid, so this doesn't get cleared when the category changes.
    @State private var ratingFilter: RexRatingTier?
    private enum SortMode { case recent, mostLiked }
    @State private var sortMode: SortMode = .recent
    @State private var likeCounts: [String: Int] = [:]
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var noInspirationFor: RexCategory?
    @State private var myProfile: RexProfileDetail?
    @State private var editing: FeedRecommendation?
    @State private var addingToCollection: FeedRecommendation?
    @State private var addingToTrip: FeedRecommendation?

    /// #129/live report — a category filter or search query used to just
    /// re-slice `recommendations`, which fetchFeed() caps at 50 unfiltered
    /// rows. Filtering to a rare category ("only 1 film") or searching for
    /// anything older than the last 50 posts ("recent Rex's also don't
    /// come up") came back near-empty even though the content exists. When
    /// this is non-nil, it's a dedicated wider server-side fetch for the
    /// active filter/search, and takes over from `recommendations` as
    /// `matching`'s base; nil means no filter/search is active, so the
    /// normal capped feed is exactly what should show.
    @State private var filteredRecommendations: [FeedRecommendation]?
    @State private var isLoadingFiltered = false
    @State private var filterFetchTask: Task<Void, Never>?

    /// Every category, always offered — not just the ones present in the
    /// currently-loaded page.
    ///
    /// This used to filter down to Set(recommendations...) so we wouldn't
    /// show a filter that would return nothing. That reasoning held when
    /// the feed loaded in full, but fetchFeed() caps at 50 rows (see
    /// RexAPI.fetchFeed) — so a category with real posts just outside that
    /// window would silently lose its chip. TestFlight caught this
    /// directly: "The filter has lost some of the filters including movie
    /// tv show podcast recipe stuff etc." A tapped category with nothing
    /// in the current page now lands on the existing noMatchesState
    /// ("Nothing matches") instead of the chip vanishing, which is the
    /// same honest outcome without the disappearing-button confusion.
    private var availableCategories: [RexCategory] { rexAllCategories }

    /// Only the tiers actually represented, same reasoning as
    /// availableCategories — no point offering a filter that would empty
    /// the feed.
    private var availableRatingTiers: [RexRatingTier] {
        let present = Set(recommendations.filter { $0.rating > 0 }.map { RexRatingTier.tier(forRaw: $0.rating) })
        return RexRatingTier.allCases.filter { present.contains($0) }
    }

    /// Subcategories (genres) within the selected category, mirroring the web.
    private var availableSubcategories: [String] {
        guard let filter else { return [] }
        var set = Set<String>()
        for rec in recommendations where RexCategory(rawType: rec.items?.type) == filter {
            for genre in splitGenres(rec.items?.genre) { set.insert(genre) }
        }
        return set.sorted()
    }

    /// Bursts the reader has chosen to see in full.
    @State private var expandedBursts: Set<String> = []
    /// How many people have Rex'd each item, and what's already on your list.
    @State private var rexCounts: [String: Int] = [:]
    @State private var myWantItemIds: Set<String> = []

    /// A mass import — someone's whole Goodreads or IMDb history in one go —
    /// otherwise buries everyone else. More than five in a row from the same
    /// person in the same minute collapses to five plus a "show the rest".
    private var visible: [FeedRow] {
        let rows = sorted
        var out: [FeedRow] = []
        var index = 0
        while index < rows.count {
            let key = burstKey(rows[index])
            var run = index
            while run < rows.count, burstKey(rows[run]) == key { run += 1 }
            let burst = Array(rows[index..<run])
            if burst.count > 5, !expandedBursts.contains(key) {
                out.append(contentsOf: burst.prefix(5).map { FeedRow.rex($0) })
                let who = burst[0].profiles?.display_name ?? burst[0].profiles?.username
                out.append(.more(key: key, count: burst.count - 5, by: who ?? "They"))
            } else {
                out.append(contentsOf: burst.map { FeedRow.rex($0) })
            }
            index = run
        }
        return out
    }

    /// Same person, same minute — close enough to call one import.
    private func burstKey(_ rec: FeedRecommendation) -> String {
        "\(rec.user_id)|\(rec.created_at.prefix(16))"
    }

    private var matching: [FeedRecommendation] {
        (filteredRecommendations ?? recommendations).filter { rec in
            if blastsOnly { return rec.isBlast }
            if rec.isBlast { return filter == nil } // never in a category filter
            if let filter, RexCategory(rawType: rec.items?.type) != filter { return false }
            if let subFilter, !splitGenres(rec.items?.genre).contains(subFilter) { return false }
            // Wants and blasts have no rating to bucket into a tier, so a
            // rating filter naturally hides them rather than matching by
            // accident on the zero sentinel.
            if let ratingFilter {
                guard rec.rating > 0, RexRatingTier.tier(forRaw: rec.rating) == ratingFilter else { return false }
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                let q = query.lowercased()
                let haystack = [
                    rec.items?.title, rec.items?.subtitle, rec.note,
                    rec.profiles?.username, rec.profiles?.display_name,
                ].compactMap { $0 }.joined(separator: " ").lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
    }

    /// Newest-first is already how loadFeed merges everything, so only
    /// "Most liked" needs an actual re-sort here.
    private var sorted: [FeedRecommendation] {
        guard sortMode == .mostLiked else { return matching }
        return matching.sorted { a, b in
            let la = likeCounts[a.id] ?? 0, lb = likeCounts[b.id] ?? 0
            if la != lb { return la > lb }
            return a.created_at > b.created_at // tie-break: newest first
        }
    }

    /// Like counts are fetched on demand, not on every feed load — most
    /// visits never touch "Most liked", so there's no reason to pay for a
    /// second network round trip they'll never see.
    private func loadLikeCountsIfNeeded() async {
        guard likeCounts.isEmpty else { return }
        let ids = recommendations.filter { !$0.isWant && !$0.isBlast }.map { $0.id }
        let state = (try? await RexAPI.shared.fetchLikeState(recommendationIds: ids)) ?? [:]
        likeCounts = state.mapValues { $0.count }
    }

    /// Explicit scroll-position tracking rather than relying on SwiftUI to
    /// infer it — tapping into a Rex and pressing back was landing you at
    /// the top of the feed instead of where you'd scrolled to.
    @State private var scrolledRowID: String?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                RexColor.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: RexSpacing.betweenCards) {
                        header
                            .id("top")

                        if isLoading {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: RexRadius.card)
                                    .fill(RexColor.muted)
                                    .frame(height: 130)
                            }
                        } else if let errorMessage {
                            errorState(errorMessage)
                        } else if recommendations.isEmpty {
                            emptyState
                        } else if isLoadingFiltered {
                            // Filtering/searching just triggered a fresh,
                            // wider server fetch (see filteredRecommendations) —
                            // without this, the old capped page's client-side
                            // filter result flashes "Nothing matches" for a
                            // moment before the real answer arrives.
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: RexRadius.card)
                                    .fill(RexColor.muted)
                                    .frame(height: 130)
                            }
                        } else if visible.isEmpty {
                            noMatchesState
                        } else {
                            if filter == nil && subFilter == nil && query.isEmpty {
                                askForRexCard
                            }
                            ForEach(visible) { row in
                              switch row {
                              case .more(let key, let count, let by):
                                Button {
                                    expandedBursts.insert(key)
                                } label: {
                                    HStack(spacing: RexSpacing.sm) {
                                        Image(systemName: "square.stack")
                                            .font(.system(size: 13))
                                        Text("\(by) added \(count) more at once")
                                            .font(RexFont.text(14, weight: .medium))
                                        Spacer()
                                        Text("Show all")
                                            .font(RexFont.text(13, weight: .semibold))
                                    }
                                    .foregroundStyle(RexColor.mutedForeground)
                                    .padding(RexSpacing.md)
                                    .contentShape(Rectangle())
                                    .rexCard()
                                }
                                .buttonStyle(.plain)

                              case .rex(let rec):
                              // Swiping only offers to delete your own Rex.
                              // There's nothing sensible to remove on someone
                              // else's, so those don't swipe at all.
                              SwipeIfMine(
                                rec: rec,
                                onTap: { open(rec) },
                                onDelete: { await deleteRex(rec) }
                              ) {
                                Group {
                                    RecommendationCardView(
                                        rec: rec,
                                        rexCount: rexCounts[rec.item_id] ?? 0,
                                        isOnMyList: myWantItemIds.contains(rec.item_id),
                                        onAuthorTap: { userId, name in
                                            path.append(UserProfileRoute(userId: userId, name: name))
                                        },
                                        onBookAuthorTap: { author in
                                            path.append(AuthorRoute(author: author))
                                        },
                                        onCommentTap: { open(rec) },
                                        onViewOnMap: onViewOnMap
                                    )
                                }
                                .modifier(EditableIfMine(rec: rec, editing: $editing))
                                // No .draggable() here: Collections isn't
                                // visible at the same time as the feed (they're
                                // different tabs), so there's never a drop
                                // target on screen to drag onto — it did
                                // nothing useful except win the gesture
                                // conflict against SwipeToRemove's plain
                                // DragGesture and silently break swiping.
                                // One menu only — a second `.contextMenu` replaces
                                // the first rather than adding to it.
                                .contextMenu {
                                    // A want has no recommendation row, so
                                    // there's nothing for saved_posts to
                                    // reference — this silently 404'd before.
                                    // Your own wants get the real thing from
                                    // WishListCategoryView instead.
                                    if !rec.isWant {
                                        Button {
                                            addingToCollection = rec
                                        } label: {
                                            Label("Add to collection", systemImage: "folder.badge.plus")
                                        }
                                    }
                                    // Places only (#104) — a trip is a
                                    // sequence of places, so "add this to a
                                    // trip" only makes sense for the same
                                    // category TripStopsBuilderView deals in.
                                    if !rec.isWant, RexCategory(rawType: rec.items?.type) == .place {
                                        Button {
                                            addingToTrip = rec
                                        } label: {
                                            Label("Add to trip", systemImage: "bag.badge.plus")
                                        }
                                    }
                                    if rec.user_id == RexAPI.shared.currentUserId {
                                        Button { editing = rec } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                    }
                                }
                              }
                              }
                            }
                        }
                    }
                    .padding(.horizontal, RexSpacing.page)
                    .padding(.bottom, RexSpacing.xxl)
                }
                .scrollPosition(id: $scrolledRowID)
                .refreshable { await loadFeed() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { itemId in
                ItemDetailView(itemId: itemId)
            }
            .navigationDestination(for: TripRoute.self) { route in
                TripDetailView(route: route)
            }
            .navigationDestination(for: ListRoute.self) { route in
                ListDetailView(route: route)
            }
            .navigationDestination(for: BlastRoute.self) { route in
                BlastDetailView(route: route)
            }
            .navigationDestination(for: UserProfileRoute.self) { r in
                UserProfileView(route: r)
            }
            .navigationDestination(for: NotificationsRoute.self) { _ in
                NotificationsView()
            }
            .navigationDestination(for: AuthorRoute.self) { r in
                AuthorBooksView(route: r)
            }
            .navigationDestination(for: FriendsRoute.self) { _ in
                FriendsView()
            }
            .navigationDestination(for: FeedbackRoute.self) { _ in
                FeedbackView()
            }
            .navigationDestination(for: AskRoute.self) { _ in
                AskForRexView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Non-interactive — Explore has its own tab now (see
                    // MainTabView), so the logo doesn't need to do anything.
                    // The supplied wordmark artwork, used without distortion
                    // per the brand guidelines.
                    Image("RexWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                        .accessibilityLabel("REX")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: RexSpacing.lg) {
                        // + is back on the bottom tab bar's raised centre
                        // button, per Kathryn's ask — see MainTabView.
                        // Friends moved up here in its place.
                        Button {
                            onFriendsTap()
                        } label: {
                            Image(systemName: "person.2")
                                .font(.system(size: 18))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                        .accessibilityLabel("Friends")

                        NavigationLink(value: FeedbackRoute()) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.system(size: 18))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                        .accessibilityLabel("Send feedback")

                        NavigationLink(value: NotificationsRoute()) {
                            Image(systemName: "bell")
                                .font(.system(size: 18))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                        .accessibilityLabel("Notifications")

                        // Your own picture, not a generic glyph. A sheet
                        // rather than a NavigationLink push deliberately —
                        // ProfileView owns its own NavigationStack (needed
                        // so a swiped row can push onto a real bound path
                        // when Profile is the tab root), and pushing it
                        // inside Feed's NavigationStack nested one
                        // NavigationStack inside another. That's explicitly
                        // unsupported in SwiftUI and rendered as a blank
                        // screen with a dead back button — a real bug this
                        // session caught, not a hypothetical. A sheet is its
                        // own presentation context, so there's no nesting.
                        Button {
                            showingProfile = true
                        } label: {
                            UserAvatarView(
                                url: myProfile?.avatar_url,
                                name: myProfile?.display_name ?? myProfile?.username ?? "?",
                                size: 28
                            )
                        }
                        .accessibilityLabel("Your profile")
                    }
                }
            }
        }
        .tint(RexColor.primary)
        .onChange(of: popToRootSignal) { _, _ in
            path = NavigationPath()
            withAnimation { scrolledRowID = "top" }
        }
        .onChange(of: filter) { _, _ in scheduleFilteredFetch() }
        .onChange(of: query) { _, _ in scheduleFilteredFetch(debounced: true) }
        .onChange(of: addRexRefreshSignal) { _, _ in Task { await loadFeed() } }
        .task {
            await loadFeed()
            myProfile = try? await RexAPI.shared.fetchMyProfile()
        }
        .sheet(item: $editing) { rec in
            EditRexView(
                rec: rec,
                onSaved: { Task { await refreshOneRex(id: rec.id) } },
                onDeleted: { Task { await loadFeed() } }
            )
        }
        .sheet(item: $addingToCollection) { rec in
            AddToCollectionView(rec: rec, onDone: {})
        }
        .sheet(item: $addingToTrip) { rec in
            AddToTripView(itemId: rec.item_id, itemTitle: rec.items?.title ?? "This place", onDone: {})
        }
        .sheet(isPresented: $showingProfile, onDismiss: { Task { await loadFeed() } }) {
            ProfileView(onSignedOut: onSignedOut)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            // No "Your feed" heading — the feed is the home screen, so naming
            // it just eats vertical space above the content.
            HStack(spacing: RexSpacing.sm) {
                searchField
                Menu {
                    Button {
                        sortMode = .recent
                    } label: {
                        Label("Most recent", systemImage: sortMode == .recent ? "checkmark" : "")
                    }
                    Button {
                        sortMode = .mostLiked
                        Task { await loadLikeCountsIfNeeded() }
                    } label: {
                        Label("Most liked", systemImage: sortMode == .mostLiked ? "checkmark" : "")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                        .frame(width: 46, height: 46)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                }
            }

            // Tapping the empty search bar offers a shortcut past "type the
            // exact thing you want" — pick a category, get handed a random
            // Rex from it instead.
            if searchFocused && query.isEmpty {
                inspirationPanel
            }

            if !availableCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        filterChip(title: "All", isActive: filter == nil && !blastsOnly && ratingFilter == nil) {
                            filter = nil; subFilter = nil; blastsOnly = false; ratingFilter = nil
                        }
                        if recommendations.contains(where: \.isBlast) {
                            filterChip(title: "Blasts", isActive: blastsOnly) {
                                blastsOnly.toggle()
                                filter = nil; subFilter = nil
                            }
                        }
                        ForEach(availableCategories, id: \.self) { category in
                            filterChip(title: category.label, isActive: filter == category) {
                                filter = (filter == category) ? nil : category
                                subFilter = nil; blastsOnly = false
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            if !availableRatingTiers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        ForEach(availableRatingTiers) { tier in
                            filterChip(title: "\(tier.emoji) \(tier.label)", isActive: ratingFilter == tier, small: true) {
                                ratingFilter = (ratingFilter == tier) ? nil : tier
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            if !availableSubcategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        ForEach(availableSubcategories, id: \.self) { genre in
                            filterChip(title: genre, isActive: subFilter == genre, small: true) {
                                subFilter = (subFilter == genre) ? nil : genre
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(.top, RexSpacing.sm)
    }

    private var askForRexCard: some View {
        NavigationLink(value: AskRoute()) {
            HStack(spacing: RexSpacing.md) {
                ZStack {
                    Circle().fill(RexColor.badgeBackground)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15))
                        .foregroundStyle(RexColor.primary)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask friends for a Rex")
                        .font(RexFont.text(15, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    Text("Put out a blast — friends can chime in.")
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
            }
            .padding(RexSpacing.cardPadding)
            .rexCard()
        }
        .buttonStyle(.plain)
    }

    /// "Need Inspiration Fast?" — a shortcut for when you know the vibe you
    /// want but not the specific thing, picking a random already-Rex'd item
    /// from a category rather than making you scroll or type anything.
    private var inspirationPanel: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text("Need Inspiration Fast?")
                .font(RexFont.text(15, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Pick a category and we'll hand you a random Rex.")
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    ForEach(availableCategories, id: \.self) { category in
                        filterChip(title: category.label, isActive: noInspirationFor == category) {
                            surpriseMe(in: category)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            if noInspirationFor != nil {
                Text("Nothing left to surprise you with there yet.")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        }
        .padding(RexSpacing.cardPadding)
        .rexCard()
    }

    /// A random non-blast, non-want Rex from the given category. Drawn from
    /// what's already loaded in the feed rather than a fresh query — this is
    /// meant to feel instant, and everything it could surface is already in
    /// memory.
    private func surpriseMe(in category: RexCategory) {
        let candidates = recommendations.filter {
            !$0.isBlast && !$0.isWant && RexCategory(rawType: $0.items?.type) == category
        }
        guard let pick = candidates.randomElement() else {
            noInspirationFor = category
            return
        }
        noInspirationFor = nil
        searchFocused = false
        open(pick)
    }

    private var searchField: some View {
        HStack(spacing: RexSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(RexColor.placeholder)
            TextField("Search Rex, people, places…", text: $query)
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.foreground)
                .autocorrectionDisabled()
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(RexColor.placeholder)
                }
            }
        }
        .padding(.horizontal, RexSpacing.lg)
        .frame(height: 46)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
    }

    private func filterChip(
        title: String,
        isActive: Bool,
        small: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(RexFont.text(small ? 12 : 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? RexColor.primaryForeground : RexColor.mutedForeground)
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, small ? 5 : 7)
                .background(isActive ? RexColor.primary : RexColor.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isActive ? RexColor.primary : RexColor.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// Trips open their itinerary; everything else opens the item screen.
    private func open(_ rec: FeedRecommendation) {
        // #132 — a blast has no item, but it does now have somewhere to go:
        // its own screen, to read and add responses.
        if rec.isBlast {
            let requestId = String(rec.id.dropFirst("blast-".count))
            path.append(BlastRoute(requestId: requestId, title: rec.items?.title ?? "Blast"))
            return
        }
        // A want isn't backed by a real item either, and has no responses
        // mechanism of its own — nowhere to push to.
        guard !rec.isWant else { return }
        switch RexCategory(rawType: rec.items?.type) {
        case .trip:
            path.append(TripRoute(recommendationId: rec.id, title: rec.items?.title ?? "Trip"))
        case .list:
            path.append(ListRoute(recommendationId: rec.id, title: rec.items?.title ?? "List"))
        default:
            path.append(rec.item_id)
        }
    }

    private func deleteRex(_ rec: FeedRecommendation) async {
        recommendations.removeAll { $0.id == rec.id }
        do {
            try await RexAPI.shared.deleteRecommendation(id: rec.id)
        } catch {
            // Put it back rather than pretending it's gone.
            await loadFeed()
        }
    }

    /// #129/live report — see filteredRecommendations' doc comment. Runs a
    /// dedicated, wider server-side fetch whenever a category filter or
    /// search query is active; clears back to the normal capped feed when
    /// both are off. Debounced for search so it isn't firing on every
    /// keystroke, immediate for a category chip tap.
    private func scheduleFilteredFetch(debounced: Bool = false) {
        filterFetchTask?.cancel()
        let category = filter?.rawValue
        let text = query.trimmingCharacters(in: .whitespaces)
        guard category != nil || !text.isEmpty else {
            filteredRecommendations = nil
            isLoadingFiltered = false
            return
        }
        filterFetchTask = Task {
            if debounced {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
            }
            isLoadingFiltered = true
            let result = try? await RexAPI.shared.fetchFeed(
                category: category,
                searchText: text.isEmpty ? nil : text
            )
            if Task.isCancelled { return }
            filteredRecommendations = result ?? []
            // Regression from this fix itself: a filtered/searched card can
            // surface an item never in the original unfiltered 50-row page,
            // so rexCounts had nothing for it — "Also Rex'd by" silently
            // never showed on any filtered or searched result. Merge in
            // counts for whatever just loaded rather than replacing
            // rexCounts outright, so the unfiltered feed's own counts
            // (already showing) aren't lost switching back to it.
            let itemIds = Array(Set((result ?? []).map { $0.item_id }))
            if let newCounts = try? await RexAPI.shared.fetchRexCounts(itemIds: itemIds) {
                for (id, count) in newCounts { rexCounts[id] = count }
            }
            isLoadingFiltered = false
        }
    }

    private func loadFeed() async {
        isLoading = recommendations.isEmpty
        errorMessage = nil
        do {
            // Friends' wants sit in the feed alongside Rex, newest first, so
            // "I want to try this" is something people can answer.
            async let rex = RexAPI.shared.fetchFeed()
            async let wantsFeed = RexAPI.shared.fetchWantsFeed()
            async let blastsFeed = RexAPI.shared.fetchBlastsFeed()
            let merged = (try await rex)
                + ((try? await wantsFeed) ?? [])
                + ((try? await blastsFeed) ?? [])
            recommendations = merged.sorted { $0.created_at > $1.created_at }

            let itemIds = Array(Set(recommendations.map { $0.item_id }))
            async let counts = RexAPI.shared.fetchRexCounts(itemIds: itemIds)
            async let wants = RexAPI.shared.fetchWants()
            rexCounts = (try? await counts) ?? [:]
            myWantItemIds = Set(((try? await wants) ?? []).compactMap { $0.items?.id })
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// #138 — splice one refreshed row back into the existing array instead
    /// of calling loadFeed(), which replaces the whole thing and reset
    /// scroll to the top even though the edited row's id and sort position
    /// hadn't moved. Falls back to a full reload if the targeted fetch
    /// fails for any reason (e.g. the edit also changed something that
    /// affects what should be visible) rather than leaving the feed stale.
    private func refreshOneRex(id: String) async {
        do {
            let updated = try await RexAPI.shared.fetchRecommendation(id: id)
            if let index = recommendations.firstIndex(where: { $0.id == id }) {
                recommendations[index] = updated
            } else {
                await loadFeed()
            }
        } catch {
            await loadFeed()
        }
    }

    private var emptyState: some View {
        VStack(spacing: RexSpacing.md) {
            Text("Your feed is empty")
                .font(RexFont.display(22, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Add friends or follow a creator — their picks will land here.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
        .padding(.top, RexSpacing.xxl)
    }

    private var noMatchesState: some View {
        VStack(spacing: RexSpacing.sm) {
            Text("Nothing matches")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Try a different filter or search.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(RexColor.destructive)
            Text(message)
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadFeed() } }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
        .padding(.top, RexSpacing.xxl)
    }
}

/// Genres are stored comma-separated on items, same as the web splitGenres().
func splitGenres(_ raw: String?) -> [String] {
    (raw ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

/// A feed row is either a Rex or the tail of a collapsed mass import.
enum FeedRow: Identifiable {
    case rex(FeedRecommendation)
    case more(key: String, count: Int, by: String)

    var id: String {
        switch self {
        case .rex(let r): return r.id
        case .more(let key, _, _): return "more-\(key)"
        }
    }
}

/// Swipe-to-delete, but only on your own Rex — other people's cards scroll
/// normally rather than offering an action that would do nothing.
struct SwipeIfMine<Content: View>: View {
    let rec: FeedRecommendation
    let onTap: () -> Void
    let onDelete: () async -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        if rec.user_id == RexAPI.shared.currentUserId {
            SwipeToRemove(
                label: "Delete",
                systemImage: "trash",
                confirmMessage: "Delete this Rex? It'll disappear from your friends' feeds too.",
                onTap: onTap,
                action: onDelete,
                content: content
            )
        } else {
            content()
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        }
    }
}

/// Adds an edit affordance to a card, but only on your own Rex.
struct EditableIfMine: ViewModifier {
    let rec: FeedRecommendation
    @Binding var editing: FeedRecommendation?

    private var isMine: Bool { rec.user_id == RexAPI.shared.currentUserId }

    func body(content: Content) -> some View {
        if isMine {
            content
                .overlay(alignment: .topTrailing) {
                    Button { editing = rec } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(RexColor.mutedForeground)
                            .padding(7)
                            .background(RexColor.card)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(RexColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
        } else {
            content
        }
    }
}
