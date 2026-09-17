import SwiftUI

/// Own profile: header + all-time stats + own Rex, filterable by category.
/// Folds in the backlog request for profile-page filtering (task #20), built as a single
/// scrollable row of chips rather than a dropdown — same pattern requested for the feed's
/// filters (task #17), so this establishes the look we'll reuse there later.
struct ProfileView: View {
    /// Optional so the tab-bar Profile can own sign-out while other entry
    /// points (e.g. the feed toolbar) just view the profile.
    var onSignedOut: (() -> Void)? = nil
    /// #133 "view on map" — MainTabView switches to the Map tab and jumps
    /// to this item's pin.
    var onViewOnMap: ((String) -> Void)? = nil
    /// Trip id and title — see MainTabView.focusMap(onTrip:title:).
    var onViewTripOnMap: ((String, String) -> Void)? = nil
    /// "Can we make the friends and collections boxes here both buttons
    /// that take you to your respective pages?"
    @Environment(\.goToFriends) private var goToFriends
    @Environment(\.goToCollections) private var goToCollections
    /// A no-op when Profile isn't actually a presented sheet (e.g. reached
    /// as MainTabView's own tag(5) directly) — only closes anything when
    /// there's really a presentation to close.
    @Environment(\.dismiss) private var dismissSelf

    /// "I would prefer the profile to always be a new screen. not a pop
    /// up. in an existing screen." — used to own its own NavigationStack
    /// specifically so it could work both as a sheet (no bound path to
    /// push onto) and as MainTabView's own tag(5) tab root. Dropping the
    /// sheet entirely removes that need: this now takes whichever
    /// NavigationStack's path it's pushed onto — FeedView's own, when
    /// reached from the avatar button, or a dedicated one MainTabView
    /// wraps around tag(5) — so a nested NavigationStack (unsupported,
    /// blank-screen-and-dead-back-button territory, a real bug this
    /// session already hit once) never happens.
    @Binding var path: NavigationPath

    @State private var profile: RexProfileDetail?
    @State private var recommendations: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedFilter: RexCategory?
    /// Sept 9 — one sheet modifier, not four; see FeedView.ActiveSheet for
    /// the fault this fixes.
    private enum ActiveSheet: Identifiable {
        case editProfile
        case edit(FeedRecommendation)
        case collection(FeedRecommendation)
        case trip(FeedRecommendation)
        case comments(FeedRecommendation)
        case addRex
        var id: String {
            switch self {
            case .addRex: return "addRex"
            case .comments(let rec): return "comments-\(rec.id)"
            case .editProfile: return "editProfile"
            case .edit(let rec): return "edit-\(rec.id)"
            case .collection(let rec): return "collection-\(rec.id)"
            case .trip(let rec): return "trip-\(rec.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var selecting = false
    @State private var selectedIds: Set<String> = []
    @State private var confirmBulkDelete = false
    @State private var isDeleting = false
    @State private var rexCounts: [String: Int] = [:]
    /// #147: the old Lovable web profile led with a row of stat cards
    /// (Rex count / average rating / friends / collections) rather than the
    /// single compact line this had — friends and collections aren't part
    /// of `recommendations` at all, so they need their own small fetches.
    @State private var friendCount = 0
    @State private var collectionCount = 0

    private var availableCategories: [RexCategory] {
        let present = Set(recommendations.compactMap { RexCategory(rawValue: $0.items?.type ?? "") })
        // Sept 7 — "need lists as a filter on profile". List was the one
        // category missing from this row, so a profile full of lists had no
        // way to show just them.
        return [.place, .trip, .list, .book, .movie, .tv, .podcast, .recipe, .event, .other].filter { present.contains($0) }
    }

    private var filteredRecommendations: [FeedRecommendation] {
        guard let selectedFilter else { return recommendations }
        return recommendations.filter { $0.items?.type == selectedFilter.rawValue }
    }


    var body: some View {
        // No wrapping NavigationStack here — takes the `path` binding its
        // caller passes in instead. See the doc comment on `path` above.
        ScrollView {
            if isLoading {
                ProgressView().padding(.top, 80)
            } else if let errorMessage {
                errorState(errorMessage)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if !availableCategories.isEmpty {
                        filterRow
                    }
                    recList
                    // Sept 15 — "no longer works to have them at the bottom
                    // as the page is too long". Privacy and Log out moved to
                    // Settings (the gear beside the bell).
                }
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        // Sept 15 — no title: the name is already the first thing on the
        // page, large, and repeating it in the bar just above read as a
        // mistake ("remove the repeat of the profile name").
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    path.append(DraftsRoute())
                } label: {
                    Image(systemName: "doc.text")
                }
                .foregroundStyle(RexColor.primary)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    path.append(NotificationPreferencesRoute())
                } label: {
                    Image(systemName: "bell")
                }
                .foregroundStyle(RexColor.primary)
            }
            // Sept 15 — "can we add a settings button next to the Bell".
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    path.append(SettingsRoute())
                } label: {
                    Image(systemName: "gearshape")
                }
                .foregroundStyle(RexColor.primary)
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !recommendations.isEmpty {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        selectedIds.removeAll()
                    }
                    .font(RexFont.text(14, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && !selectedIds.isEmpty {
                Button {
                    confirmBulkDelete = true
                } label: {
                    if isDeleting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Delete \(selectedIds.count) Rex")
                    }
                }
                .font(RexFont.text(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RexColor.destructive)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.button, style: .continuous))
                .padding(.horizontal, RexSpacing.page)
                .padding(.bottom, RexSpacing.sm)
                .disabled(isDeleting)
            }
        }
        .alert("Delete \(selectedIds.count) Rex?", isPresented: $confirmBulkDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await bulkDelete() } }
        } message: {
            Text("This can't be undone.")
        }
        .task { await load() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addRex:
                AddRexView(onDone: { activeSheet = nil; Task { await load() } })
            case .comments(let rec):
                CommentsSheet(rec: rec)
            case .editProfile:
                EditProfileView(profile: profile, onSaved: { Task { await load() } })
            case .collection(let rec):
                AddToCollectionView(rec: rec) { activeSheet = nil }
            case .trip(let rec):
                AddToTripView(itemId: rec.item_id, itemTitle: rec.items?.title ?? "This place", onDone: {})
            case .edit(let rec):
                // Same branch as FeedView's — a trip edits in the Add-a-trip
                // form, everything else in EditRexView.
                if RexCategory(rawType: rec.items?.type) == .trip {
                    TripEditorLoader(trip: rec) {
                        activeSheet = nil
                        Task { await load() }
                    }
                } else if RexCategory(rawType: rec.items?.type) == .list {
                    ListEditorLoader(list: rec) {
                        activeSheet = nil
                        Task { await load() }
                    }
                } else {
                    EditRexView(
                        rec: rec,
                        onSaved: { Task { await load() } },
                        onDeleted: { Task { await load() } }
                    )
                }
            }
        }
        .navigationDestination(for: String.self) { ItemDetailView(itemId: $0) }
        .navigationDestination(for: UserProfileRoute.self) { UserProfileView(route: $0) }
        .navigationDestination(for: AuthorRoute.self) { AuthorBooksView(route: $0) }
        .navigationDestination(for: DraftsRoute.self) { _ in DraftsView() }
        .navigationDestination(for: NotificationPreferencesRoute.self) { _ in NotificationPreferencesView() }
        .navigationDestination(for: PrivacyRoute.self) { _ in PrivacyDataView(onSignedOut: { onSignedOut?() }) }
        .navigationDestination(for: SettingsRoute.self) { _ in
            SettingsView(
                onEditProfile: { activeSheet = .editProfile },
                onSignedOut: onSignedOut.map { signOut in { RexAPI.shared.signOut(); signOut() } }
            )
        }
        // Sept 1 — "when you go to a trip on your profile ... it doesn't
        // come up with the list of things on the trip. It comes up with
        // the update your take page only": tapping a card here always
        // pushed rec.item_id (plain ItemDetailView), same as tapping a
        // trip's own take/rating page — FeedView's open(_:) already knew
        // to route a trip/list to its own stop-list screen instead; this
        // screen just never got the same branching, so these two
        // destinations were unregistered here even though open(_:) below
        // could push them.
        .navigationDestination(for: TripRoute.self) { TripDetailView(route: $0) }
        .navigationDestination(for: ListRoute.self) { ListDetailView(route: $0) }
    }

    /// Same category branching as FeedView's own open(_:) — a trip or list
    /// opens its stop-list screen, everything else opens the plain item
    /// screen. Profile's own rows are always real recommendations (never a
    /// want or blast), so there's no need for open(_:)'s isBlast branch.
    private func open(_ rec: FeedRecommendation) {
        switch RexCategory(rawType: rec.items?.type) {
        case .trip:
            path.append(TripRoute(recommendationId: rec.id, title: rec.items?.title ?? "Trip"))
        case .list:
            path.append(ListRoute(recommendationId: rec.id, title: rec.items?.title ?? "List"))
        default:
            path.append(rec.item_id)
        }
    }

    private func delete(_ rec: FeedRecommendation) async {
        recommendations.removeAll { $0.id == rec.id }
        do {
            try await RexAPI.shared.deleteRecommendation(id: rec.id)
        } catch {
            // Put it back rather than pretending it's gone.
            await load()
        }
    }

    private func bulkDelete() async {
        isDeleting = true
        // Sequential rather than parallel — a handful of deletes, and this
        // keeps the error case simple if one fails partway.
        for id in selectedIds {
            try? await RexAPI.shared.deleteRecommendation(id: id)
        }
        selectedIds.removeAll()
        selecting = false
        isDeleting = false
        await load()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        // "The profile takes ages to load" — this used to run almost
        // entirely in series: await your profile, only then start
        // recommendations, only then start rexCounts, and only
        // friendships/lists at the very end (in parallel with each other,
        // but after everything above had already finished) — four network
        // round trips back to back where two would do. currentUserId
        // decodes locally from the stored JWT (no request of its own — see
        // its doc comment), so recommendations/friendships/lists never
        // actually needed to wait on fetchMyProfile() finishing; only
        // rexCounts genuinely depends on recommendations, since it needs
        // their item_ids.
        guard let userId = RexAPI.shared.currentUserId else {
            errorMessage = "Not signed in."
            isLoading = false
            return
        }
        do {
            async let profileTask = RexAPI.shared.fetchMyProfile()
            async let recommendationsTask = RexAPI.shared.fetchRecommendations(forUser: userId)
            // Best-effort, same as rexCounts below — a stat card reading 0
            // because one of these failed is better than the whole profile
            // failing to load over it.
            async let friendshipsTask = RexAPI.shared.fetchFriendships()
            async let listsTask = RexAPI.shared.fetchLists()

            profile = try await profileTask
            recommendations = try await recommendationsTask
            // "Who else has Rex'd this" was missing on your own profile —
            // it's the same social proof the feed already shows.
            let itemIds = Array(Set(recommendations.map { $0.item_id }))
            async let rexCountsTask = RexAPI.shared.fetchRexCounts(itemIds: itemIds)

            let friendships = (try? await friendshipsTask) ?? []
            friendCount = friendships.filter { $0.status == "accepted" }.count
            collectionCount = (try? await listsTask)?.count ?? 0
            rexCounts = (try? await rexCountsTask) ?? [:]
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                UserAvatarView(
                    url: profile?.avatar_url,
                    name: profile?.display_name ?? profile?.username ?? "?",
                    size: 64
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile?.display_name ?? profile?.username ?? "")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(RexColor.foreground)
                    if let username = profile?.username {
                        Text("@\(username)").font(.system(size: 13)).foregroundStyle(RexColor.mutedForeground)
                    }
                }
                Spacer()
                Button {
                    activeSheet = .editProfile
                } label: {
                    Text("Edit")
                        .font(RexFont.text(13, weight: .semibold))
                        .foregroundStyle(RexColor.primary)
                        .padding(.horizontal, RexSpacing.md)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(RexColor.primary, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // #147: the old Lovable web profile's own header led with this
            // stat-card row (Rex / avg rating / friends / collections)
            // before going straight into the feed of your own Rex — same
            // shape, kept here rather than the "Your activity" grid and
            // "What you Rex" bars the web profile also had below it, which
            // Kathryn asked to drop in favour of going straight to the feed.
            HStack(spacing: RexSpacing.sm) {
                statCard(value: "\(recommendations.count)", label: "REX")
                statCard(value: averageRatingText, label: "AVG RATING")
                statCard(value: "\(friendCount)", label: "FRIENDS") {
                    // Pushed onto the same stack now that Friends isn't a
                    // tab — see MainTabView.
                    path.append(FriendsRoute())
                }
                statCard(value: "\(collectionCount)", label: "COLLECTIONS") {
                    goToCollections?()
                    dismissSelf()
                }
            }
            .padding(.top, RexSpacing.md)
        }
        .padding(16)
    }

    private var averageRatingText: String {
        guard let avg = RexRatingTier.averageTier(ratings: recommendations.map { $0.rating }) else { return "–" }
        return String(format: "%.1f", avg)
    }

    private func statCard(value: String, label: String, action: (() -> Void)? = nil) -> some View {
        let card = VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(RexColor.foreground)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(RexColor.mutedForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RexSpacing.sm)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
        return Group {
            if let action {
                Button(action: action) { card }.buttonStyle(.plain)
            } else {
                card
            }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", isSelected: selectedFilter == nil) { selectedFilter = nil }
                ForEach(availableCategories, id: \.self) { cat in
                    filterChip(cat.pluralLabel, isSelected: selectedFilter == cat) { selectedFilter = cat }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(isSelected ? RexColor.primary : RexColor.card)
                .foregroundStyle(isSelected ? RexColor.primaryForeground : RexColor.foreground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(RexColor.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var recList: some View {
        if filteredRecommendations.isEmpty {
            // Sept 17 — "make the profile page when someone hasn't Rex'd
            // anything yet more interesting (currently blank) maybe a Rex
            // Dino of some kind". A new account's profile was one grey
            // sentence on an empty screen — the first thing anyone sees of
            // Rex after signing up.
            VStack(spacing: RexSpacing.md) {
                Image(recommendations.isEmpty ? "RexPlaceholderList" : "RexPlaceholderOther")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                    .accessibilityHidden(true)
                Text(recommendations.isEmpty ? "Your Rex live here" : "Nothing in this category yet")
                    .font(RexFont.display(20, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Text(recommendations.isEmpty
                     ? "Rex a place you loved, a book you couldn\u{2019}t put down, a trip worth copying \u{2014} your friends see it in their feed."
                     : "Try another category, or add one.")
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    activeSheet = .addRex
                } label: {
                    Label("Add your first Rex", systemImage: "plus")
                        .font(RexFont.text(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RexColor.primary)
                        .foregroundStyle(RexColor.primaryForeground)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, RexSpacing.xs)
                .padding(.horizontal, RexSpacing.xxl)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, RexSpacing.xl)
            .padding(.bottom, RexSpacing.xxl)
        } else {
            // Live report: "profile loading really really slowly and often
            // crashing when you try and scroll." This was a plain VStack —
            // every Rex you've ever posted, photos and all, got fully
            // instantiated up front instead of lazily as you scroll to it.
            // FeedView and UserProfileView already use LazyVStack for the
            // same row shape; this was the one screen that didn't.
            LazyVStack(spacing: RexSpacing.betweenCards) {
                ForEach(filteredRecommendations) { rec in
                    Group {
                        if selecting {
                            Button {
                                if selectedIds.contains(rec.id) { selectedIds.remove(rec.id) }
                                else { selectedIds.insert(rec.id) }
                            } label: {
                                RecommendationCardView(rec: rec, rexCount: rexCounts[rec.item_id] ?? 0)
                                    .overlay(alignment: .topLeading) {
                                        Image(systemName: selectedIds.contains(rec.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 22))
                                            .foregroundStyle(selectedIds.contains(rec.id) ? RexColor.primary : RexColor.border)
                                            .background(Circle().fill(RexColor.card).padding(2))
                                            .padding(10)
                                    }
                                    .opacity(selectedIds.contains(rec.id) ? 1 : 0.75)
                            }
                            .buttonStyle(.plain)
                        } else {
                            // These are all your own Rex, so every one is
                            // swipeable — this was never wired here, only on
                            // the feed, hence "swipe doesn't work on my
                            // profile". Same tap-callback pattern as the
                            // feed: SwipeToRemove's content can't be a
                            // NavigationLink (its own gesture would win),
                            // so the push happens through onTap instead.
                            SwipeToRemove(
                                label: "Delete",
                                systemImage: "trash",
                                confirmMessage: "Delete this Rex? It'll disappear from your friends' feeds too.",
                                onTap: { open(rec) },
                                action: { await delete(rec) }
                            ) {
                                RecommendationCardView(
                                    rec: rec,
                                    rexCount: rexCounts[rec.item_id] ?? 0,
                                    onBookAuthorTap: { author in
                                        path.append(AuthorRoute(author: author))
                                    },
                                    onCommentTap: { activeSheet = .comments(rec) },
                                    onViewOnMap: onViewOnMap,
                                        onViewTripOnMap: onViewTripOnMap
                                )
                            }
                        }
                    }
                    // These are all your own Rex, so every one is editable —
                    // plus the same "add to collection" the feed offers,
                    // requested here separately three times.
                    .contextMenu {
                        Button {
                            activeSheet = .collection(rec)
                        } label: {
                            Label("Add to collection", systemImage: "folder.badge.plus")
                        }
                        // Places only (#104), same as the feed's own card
                        // menu — a trip is a sequence of places. This menu
                        // just never got the option added at all here.
                        if RexCategory(rawType: rec.items?.type) == .place {
                            Button {
                                activeSheet = .trip(rec)
                            } label: {
                                Label("Add to trip", systemImage: "bag.badge.plus")
                            }
                        }
                        Button {
                            activeSheet = .edit(rec)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            activeSheet = .edit(rec)
                        } label: {
                            // Sept 7 — same 44pt hit area as the feed's copy
                            // of this button; see EditableIfMine in FeedView.
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(RexColor.mutedForeground)
                                .padding(8)
                                .background(RexColor.card)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(RexColor.border, lineWidth: 1))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(2)
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(.footnote).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.footnote.weight(.semibold)).foregroundStyle(RexColor.primary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}
