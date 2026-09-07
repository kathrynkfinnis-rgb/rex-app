import SwiftUI

struct NotificationsRoute: Hashable {}
/// "I would prefer the profile to always be a new screen. not a pop up. in
/// an existing screen." — was a `.sheet`; pushed onto this stack now
/// instead, same as everywhere else Feed navigates to.
struct ProfileRoute: Hashable {}

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
    /// Was a single optional category — "filter two things at once, ie if
    /// you're only interested in books and films" needed real multi-select,
    /// not a picker that replaces itself on every tap.
    @State private var selectedCategories: Set<RexCategory> = []
    @State private var subFilter: String?
    @State private var blastsOnly = false
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

    /// Paging for the unfiltered feed — see loadMore().
    private let feedPageSize = 50
    @State private var feedOffset = 0
    @State private var hasMoreFeed = true
    @State private var isLoadingMore = false

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

    /// Subcategories (genres) within the selected category, mirroring the
    /// web. Only offered for a single selected category — genre doesn't
    /// mean the same thing across, say, Books and Films at once, so this
    /// stays out of the way once more than one category is picked.
    private var availableSubcategories: [String] {
        guard selectedCategories.count == 1, let filter = selectedCategories.first else { return [] }
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
    ///
    /// #152 — this used to run unconditionally, even over an active search
    /// or filter. A search for a specific title that happened to land
    /// inside someone's >5-item import burst (e.g. their note field is the
    /// same "Imported from Goodreads" boilerplate on every book, which the
    /// search also matches on) got folded into "+N more" instead of shown
    /// directly — indistinguishable from not matching at all unless you
    /// happened to tap through. A search/filter already narrows results
    /// down to what you're looking for on purpose; collapsing them again
    /// on top of that just hides the thing you searched for.
    private var visible: [FeedRow] {
        let rows = sorted
        guard selectedCategories.isEmpty, subFilter == nil, !blastsOnly,
              query.trimmingCharacters(in: .whitespaces).isEmpty
        else { return rows.map { FeedRow.rex($0) } }
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
            if rec.isBlast { return selectedCategories.isEmpty } // never in a category filter
            if !selectedCategories.isEmpty, !selectedCategories.contains(RexCategory(rawType: rec.items?.type)) { return false }
            if let subFilter, !splitGenres(rec.items?.genre).contains(subFilter) { return false }
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

    /// #165 — the same item Rex'd by more than one person (or once
    /// standalone and again as a trip stop) showed as a separate feed card
    /// per row, back to back, saying the same thing twice. One card per
    /// item now: your own take if you have one, else whichever is most
    /// recent — everyone else still surfaces via the "Also Rex'd by"
    /// footer (rexCounts), so nothing's actually lost, just not repeated.
    /// Blasts are left alone — a question isn't a duplicate of anything.
    ///
    /// Wants used to be left alone too, on the reasoning that "wants to
    /// try" and "actually Rex'd it" are different facts. Sept 1 — "if
    /// someone makes a card as a want to try, it shouldn't appear the feed
    /// twice (mine or theirs)": in practice a want sitting right next to a
    /// real Rex of the same item (anyone's, not just the same person's)
    /// just reads as the same thing posted twice, not two facts worth
    /// separate cards. A real Rex is strictly more informative than "wants
    /// to try" it, so once one exists for an item, every want for that
    /// same item folds away — same "nothing's lost, just not repeated"
    /// reasoning as above, since isOnMyList/rexCounts already carry the
    /// want signal for your own card.
    private func collapseDuplicateItems(_ rows: [FeedRecommendation]) -> [FeedRecommendation] {
        let myId = RexAPI.shared.currentUserId
        var primaryIdByItem: [String: String] = [:]
        for rec in rows where !rec.isWant && !rec.isBlast {
            guard let existingId = primaryIdByItem[rec.item_id],
                  let existing = rows.first(where: { $0.id == existingId })
            else {
                primaryIdByItem[rec.item_id] = rec.id
                continue
            }
            let recIsMine = rec.user_id == myId
            let existingIsMine = existing.user_id == myId
            if recIsMine && !existingIsMine {
                primaryIdByItem[rec.item_id] = rec.id
            } else if recIsMine == existingIsMine, rec.created_at > existing.created_at {
                primaryIdByItem[rec.item_id] = rec.id
            }
        }
        let itemsWithARealRex = Set(primaryIdByItem.keys)
        return rows.filter { rec in
            if rec.isBlast { return true }
            if rec.isWant { return !itemsWithARealRex.contains(rec.item_id) }
            return primaryIdByItem[rec.item_id] == rec.id
        }
    }

    /// #171 — a Rex you're tagged on ("went here with Phoebe") is worth
    /// surfacing even if strict chronological (or most-liked) order would
    /// bury it a few posts back. Bounded to a few days so an old tag
    /// doesn't permanently outrank new content once it's had its moment —
    /// this is a boost, not a pin.
    private var taggedBoostThreshold: Date {
        Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? .distantPast
    }

    private func isRecentlyTaggedMe(_ rec: FeedRecommendation) -> Bool {
        guard let myId = RexAPI.shared.currentUserId,
              rec.taggedFriends.contains(where: { $0.id == myId }),
              let created = rec.createdDate
        else { return false }
        return created > taggedBoostThreshold
    }

    /// Newest-first is already how loadFeed merges everything, so only
    /// "Most liked" needs an actual re-sort here.
    private var sorted: [FeedRecommendation] {
        let base: [FeedRecommendation]
        if sortMode == .mostLiked {
            base = matching.sorted { a, b in
                let la = likeCounts[a.id] ?? 0, lb = likeCounts[b.id] ?? 0
                if la != lb { return la > lb }
                return a.created_at > b.created_at // tie-break: newest first
            }
        } else {
            base = matching
        }
        // Same reasoning as visible()'s own guard: once a filter/search has
        // deliberately narrowed things down, collapsing duplicates again on
        // top of that risks reading as "my search lost the result" even
        // though the match is technically still folded into the footer.
        let noActiveFilter = selectedCategories.isEmpty && subFilter == nil && !blastsOnly
            && query.trimmingCharacters(in: .whitespaces).isEmpty
        let deduped = noActiveFilter ? collapseDuplicateItems(base) : base

        // Sept 5 — "see friends' recent blasts at the top of the feed". A
        // blast is a question someone's waiting on an answer to, so it goes
        // stale in a way a Rex doesn't: useful today, pointless by the time
        // it's scrolled past. Same bounded-boost shape as the tagged-me one
        // above rather than a permanent pin — after a few days it drops
        // back into chronological order with everything else.
        var blasts: [FeedRecommendation] = []
        var tagged: [FeedRecommendation] = []
        var rest: [FeedRecommendation] = []
        for rec in deduped {
            if rec.isBlast, isRecent(rec) {
                blasts.append(rec)
            } else if isRecentlyTaggedMe(rec) {
                tagged.append(rec)
            } else {
                rest.append(rec)
            }
        }
        return blasts + tagged + rest
    }

    /// Within the same few days the tagged-me boost uses.
    private func isRecent(_ rec: FeedRecommendation) -> Bool {
        guard let created = rec.createdDate else { return false }
        return created > taggedBoostThreshold
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
    /// #176 — badge dot on the bell icon. Refreshed alongside the feed
    /// itself (loadFeed) rather than its own separate polling loop.
    @State private var unreadNotificationCount = 0

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                RexColor.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: RexSpacing.betweenCards, pinnedViews: [.sectionHeaders]) {
                        topBar
                            .id("top")

                        Section {
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
                            if selectedCategories.isEmpty && subFilter == nil && query.isEmpty {
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
                        } header: {
                            filterChipsBar
                        }

                        // Sept 5 — infinite scroll. Reaching this marker is
                        // what asks for the next page; it only exists while
                        // there's more to fetch and no filter/search is
                        // active (those already pull a much wider set in
                        // one go, so there's nothing to page through).
                        if hasMoreFeed, filteredRecommendations == nil, !visible.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView().controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, RexSpacing.lg)
                            .onAppear { Task { await loadMore() } }
                        }
                    }
                    .padding(.horizontal, RexSpacing.page)
                    .padding(.bottom, RexSpacing.xxl)
                }
                .scrollPosition(id: $scrolledRowID)
                .refreshable { await loadFeed() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .rexDismissableKeyboard()
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
            .navigationDestination(for: NotificationPreferencesRoute.self) { _ in
                NotificationPreferencesView()
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
            // Aug 30 — the Profile blank-warning-triangle bug: this one
            // used to sit after the .sheet modifiers below, OUTSIDE this
            // NavigationStack's own content closure — every other
            // navigationDestination here is inside it. A
            // navigationDestination declared after a .sheet in the same
            // modifier chain silently fails to register (a known SwiftUI
            // gotcha), so pushing ProfileRoute had no matching destination
            // to find; SwiftUI's fallback for that is exactly the bare
            // yellow warning-triangle glyph this bug reports. Moving it up
            // here, alongside its siblings, is the fix.
            .navigationDestination(for: ProfileRoute.self) { _ in
                ProfileView(onSignedOut: onSignedOut, path: $path)
            }
            .toolbar { feedToolbarContent }
        }
        .tint(RexColor.primary)
        .onChange(of: popToRootSignal) { _, _ in
            path = NavigationPath()
            withAnimation { scrolledRowID = "top" }
        }
        .onChange(of: selectedCategories) { _, _ in scheduleFilteredFetch() }
        .onChange(of: query) { _, _ in scheduleFilteredFetch(debounced: true) }
        .onChange(of: addRexRefreshSignal) { _, _ in Task { await loadFeed() } }
        // Popping back to the feed root (e.g. from Notifications, after
        // marking things read) is the moment the badge count is stalest —
        // cheap enough to just refetch rather than plumb a callback through.
        .onChange(of: path) { _, newValue in
            if newValue.isEmpty {
                // Was Profile's own sheet onDismiss — now that it's pushed
                // onto this same path instead, popping back to root is the
                // equivalent moment (also covers returning from Notifications,
                // Drafts, etc., which is a fine superset of the old behavior).
                Task {
                    unreadNotificationCount = await RexAPI.shared.fetchUnreadNotificationCount()
                    await loadFeed()
                }
            }
        }
        .task {
            await loadFeed()
            myProfile = try? await RexAPI.shared.fetchMyProfile()
        }
        .sheet(item: $editing) { rec in
            // Sept 5 — "the edit button on the feed takes you to the old
            // edit page". A trip is edited in the Add-a-trip form now, not
            // EditRexView (which can only touch a single Rex's own fields
            // and knows nothing about an itinerary). Branching here rather
            // than at each pencil/context-menu call site so every route
            // into editing gets it.
            if RexCategory(rawType: rec.items?.type) == .trip {
                TripEditorLoader(trip: rec) {
                    editing = nil
                    Task { await loadFeed() }
                }
            } else {
                EditRexView(
                    rec: rec,
                    onSaved: { Task { await refreshOneRex(id: rec.id) } },
                    onDeleted: { Task { await loadFeed() } }
                )
            }
        }
        .sheet(item: $addingToCollection) { rec in
            AddToCollectionView(rec: rec, onDone: {})
        }
        .sheet(item: $addingToTrip) { rec in
            AddToTripView(itemId: rec.item_id, itemTitle: rec.items?.title ?? "This place", onDone: {})
        }
    }

    /// Non-interactive — Explore has its own tab now (see MainTabView), so
    /// the logo doesn't need to do anything. The supplied wordmark artwork,
    /// used without distortion per the brand guidelines. Wrapped in a
    /// disabled plain Button rather than a bare Image: iOS 26's toolbar
    /// otherwise auto-wraps a bare leading-item Image in its own circular
    /// "Liquid Glass" badge, which is exactly the "REX in a circle" Kathryn
    /// asked to remove — the plain button style plus hiding the shared
    /// background opts out of that chrome. Pulled into its own property
    /// (rather than inline in .toolbar) because the compiler choked trying
    /// to type-check it as part of this view's already-large body.
    private var wordmarkToolbarItem: some View {
        Button {} label: {
            HStack(spacing: 6) {
                // Explicit width, not just height — once the text next to
                // it went .fixedSize(), the toolbar's tight width proposal
                // started giving this image whatever was left over, which
                // was nothing (it disappeared entirely). Both siblings now
                // demand their own space instead of one starving the other.
                Image("RexDinoLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 36)
                // Real Text rather than the wordmark image — the image's
                // .frame(height:) was getting clamped to the toolbar's own
                // fixed ~44pt height no matter what value we gave it; text
                // isn't bound by that the same way, so this actually reads
                // bigger.
                Text("REX")
                    .font(RexFont.display(24, weight: .bold))
                    .foregroundStyle(RexColor.primary)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel("REX")
    }

    /// Pulled out of body for the same reason as wordmarkToolbarItem above —
    /// the compiler choked type-checking this inline. .sharedBackgroundVisibility
    /// on the leading item is what actually suppresses iOS 26's automatic
    /// circular "Liquid Glass" badge around it; the plain button style alone
    /// wasn't enough once the leading item held two images instead of one.
    @ToolbarContentBuilder
    private var feedToolbarContent: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                wordmarkToolbarItem
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                wordmarkToolbarItem
            }
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
                        .overlay(alignment: .topTrailing) {
                            if unreadNotificationCount > 0 {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 3, y: -2)
                            }
                        }
                }
                .accessibilityLabel(unreadNotificationCount > 0 ? "Notifications, unread" : "Notifications")

                // Your own picture, not a generic glyph. Pushed onto
                // this same stack now — "I would prefer the profile
                // to always be a new screen. not a pop up." Used to
                // be a sheet specifically because ProfileView owned
                // its own separate NavigationStack (nesting one
                // NavigationStack inside another is unsupported in
                // SwiftUI, a real blank-screen-and-dead-back-button
                // bug this session already hit once) — ProfileView
                // no longer does that (see its `path` doc comment),
                // so pushing it here is safe now.
                Button {
                    path.append(ProfileRoute())
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

    private var topBar: some View {
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
        }
        .padding(.top, RexSpacing.sm)
    }

    /// Split out of what used to be one `header` view — "the filter bar
    /// [should] pop back up when you scroll up so that you can filter
    /// without having to go right back to the top of your feed". Pinned
    /// as a Section header (see body) instead: rather than a hide-on-
    /// scroll-down/reveal-on-scroll-up animation, which needs its own
    /// scroll-offset tracking to get right, this just stays put once
    /// you've scrolled to it, the same way a table's section headers do —
    /// solves the same "don't lose access to the filters" complaint with
    /// a much simpler, sturdier mechanism.
    private var filterChipsBar: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            if !availableCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        filterChip(title: "All", isActive: selectedCategories.isEmpty && !blastsOnly) {
                            selectedCategories = []; subFilter = nil; blastsOnly = false
                        }
                        if recommendations.contains(where: \.isBlast) {
                            filterChip(title: "Blasts", isActive: blastsOnly) {
                                blastsOnly.toggle()
                                selectedCategories = []; subFilter = nil
                            }
                        }
                        // Toggles membership rather than replacing the
                        // selection — "should be able to filter two things
                        // at once, ie books and films".
                        ForEach(availableCategories, id: \.self) { category in
                            filterChip(title: category.pluralLabel, isActive: selectedCategories.contains(category)) {
                                if selectedCategories.contains(category) {
                                    selectedCategories.remove(category)
                                } else {
                                    selectedCategories.insert(category)
                                }
                                subFilter = nil; blastsOnly = false
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
        .padding(.vertical, RexSpacing.sm)
        // Opaque, not just a color fill with default blending — this sits
        // pinned above cards scrolling underneath it once you're past the
        // top, so it needs to actually hide them, not let them show through.
        .background(RexColor.background)
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
        print("DEBUG open() called for rec.id=\(rec.id) isBlast=\(rec.isBlast)")
        // #132 — a blast has no item, but it does now have somewhere to go:
        // its own screen, to read and add responses.
        if rec.isBlast {
            let requestId = String(rec.id.dropFirst("blast-".count))
            path.append(BlastRoute(requestId: requestId, title: rec.items?.title ?? "Blast"))
            return
        }
        // "also can't click on a 'want to try'" — a want has no responses
        // mechanism of its own, but it does point at a real catalogue item
        // (the place/book/etc. someone wants to try), so there's a real
        // item screen to show — friends' actual Rex of it, if any, same as
        // tapping through from any other card. This guard predates wants
        // reliably showing in the feed at all (see #184's fetchWantsFeed
        // fix), written back when the question of "what happens when you
        // tap one" barely came up in practice.
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
        // One category string per selected chip — fetchFeed/fetchWantsFeed
        // only ever take one category each (a plain items.type=eq. filter
        // server-side), so multi-select fans out one fetch per category
        // and merges, the same shape the search path already uses to fan
        // out one request per matched field. `[nil]` (no categories) still
        // runs a single pass so search-only filtering keeps working.
        let categories: [String?] = selectedCategories.isEmpty ? [nil] : selectedCategories.map { $0.rawValue }
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !selectedCategories.isEmpty || !text.isEmpty else {
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
            // #184 — this used to be fetchFeed() alone, which only ever
            // queries recommendations: a want-to-try has no row there at
            // all, so the moment a category chip or search query went
            // active, every want vanished outright — reproduced concretely
            // by adding one and then searching for it. fetchWantsFeed now
            // takes the same category/searchText fetchFeed does, merged in
            // here the same way loadFeed() merges wants into the unfiltered
            // feed.
            async let rexPages: [FeedRecommendation] = withTaskGroup(of: [FeedRecommendation].self) { group in
                for category in categories {
                    group.addTask { (try? await RexAPI.shared.fetchFeed(category: category, searchText: text.isEmpty ? nil : text)) ?? [] }
                }
                var all: [FeedRecommendation] = []
                for await page in group { all.append(contentsOf: page) }
                return all
            }
            async let wantsPages: [FeedRecommendation] = withTaskGroup(of: [FeedRecommendation].self) { group in
                for category in categories {
                    group.addTask { (try? await RexAPI.shared.fetchWantsFeed(category: category, searchText: text.isEmpty ? nil : text)) ?? [] }
                }
                var all: [FeedRecommendation] = []
                for await page in group { all.append(contentsOf: page) }
                return all
            }
            let rexResult = await rexPages
            let wants = await wantsPages
            if Task.isCancelled { return }
            var seen = Set<String>()
            var merged: [FeedRecommendation] = []
            for rec in (rexResult + wants) where !seen.contains(rec.id) {
                seen.insert(rec.id)
                merged.append(rec)
            }
            filteredRecommendations = merged.sorted { $0.created_at > $1.created_at }
            // Regression from this fix itself: a filtered/searched card can
            // surface an item never in the original unfiltered 50-row page,
            // so rexCounts had nothing for it — "Also Rex'd by" silently
            // never showed on any filtered or searched result. Merge in
            // counts for whatever just loaded rather than replacing
            // rexCounts outright, so the unfiltered feed's own counts
            // (already showing) aren't lost switching back to it.
            let itemIds = Array(Set(merged.map { $0.item_id }))
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
            // A fresh load resets paging; a full page back means there's
            // probably more behind it (see loadMore).
            let rexRows = try await rex
            feedOffset = rexRows.count
            hasMoreFeed = rexRows.count >= feedPageSize

            let itemIds = Array(Set(recommendations.map { $0.item_id }))
            async let counts = RexAPI.shared.fetchRexCounts(itemIds: itemIds)
            async let wants = RexAPI.shared.fetchWants()
            rexCounts = (try? await counts) ?? [:]
            myWantItemIds = Set(((try? await wants) ?? []).compactMap { $0.items?.id })
            unreadNotificationCount = await RexAPI.shared.fetchUnreadNotificationCount()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Sept 5 — "if you get to the bottom of the feed, you should be able to
    /// keep loading more content". The feed loads 50 at a time and simply
    /// stopped there; anything older than your last 50 was unreachable
    /// except through search.
    ///
    /// Only the Rex query pages. Wants and blasts are both far smaller sets
    /// that already load in full, so paging them too would mean three
    /// cursors to keep in step for no practical gain.
    private func loadMore() async {
        guard hasMoreFeed, !isLoadingMore, filteredRecommendations == nil else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let older = try? await RexAPI.shared.fetchFeed(offset: feedOffset) else {
            hasMoreFeed = false
            return
        }
        feedOffset += older.count
        hasMoreFeed = older.count >= feedPageSize
        guard !older.isEmpty else { return }

        var seen = Set(recommendations.map { $0.id })
        let fresh = older.filter { seen.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        recommendations = (recommendations + fresh).sorted { $0.created_at > $1.created_at }

        // Same two follow-up fetches loadFeed does, for the new rows only.
        let newItemIds = Array(Set(fresh.map { $0.item_id }))
        if let counts = try? await RexAPI.shared.fetchRexCounts(itemIds: newItemIds) {
            for (id, count) in counts { rexCounts[id] = count }
        }
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
            // Kathryn's dejected-Rex illustration, standard for any error
            // state across the app, rather than a plain SF Symbol triangle.
            Image("RexErrorState")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
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
