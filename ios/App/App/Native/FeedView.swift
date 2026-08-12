import SwiftUI

struct NotificationsRoute: Hashable {}
struct ProfileRoute: Hashable {}

struct FeedView: View {
    var onSignedOut: () -> Void
    /// Incremented by the tab bar when Feed is tapped while already active.
    var popToRootSignal: Int = 0

    @State private var path = NavigationPath()

    @State private var recommendations: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingAddRex = false
    @State private var filter: RexCategory?
    @State private var subFilter: String?
    @State private var query = ""
    @State private var myProfile: RexProfileDetail?
    @State private var editing: FeedRecommendation?
    @State private var addingToCollection: FeedRecommendation?

    /// Categories that actually appear in the feed, so we don't show filters
    /// that would return nothing.
    private var availableCategories: [RexCategory] {
        let present = Set(recommendations.compactMap { RexCategory(rawType: $0.items?.type) })
        return rexAllCategories.filter { present.contains($0) }
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
        let rows = matching
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
        recommendations.filter { rec in
            if let filter, RexCategory(rawType: rec.items?.type) != filter { return false }
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

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                RexColor.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: RexSpacing.betweenCards) {
                        header

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
                                        isOnMyList: myWantItemIds.contains(rec.item_id)
                                    )
                                }
                                .modifier(EditableIfMine(rec: rec, editing: $editing))
                                // Drag a card over to Collections and drop it on
                                // a list. Dropping copies, so the Rex stays here.
                                .draggable(rec.id)
                                // One menu only — a second `.contextMenu` replaces
                                // the first rather than adding to it.
                                .contextMenu {
                                    Button {
                                        addingToCollection = rec
                                    } label: {
                                        Label("Add to collection", systemImage: "folder.badge.plus")
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
                .refreshable { await loadFeed() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { itemId in
                ItemDetailView(itemId: itemId)
            }
            .navigationDestination(for: TripRoute.self) { route in
                TripDetailView(route: route)
            }
            .navigationDestination(for: UserProfileRoute.self) { r in
                UserProfileView(route: r)
            }
            .navigationDestination(for: NotificationsRoute.self) { _ in
                NotificationsView()
            }
            .navigationDestination(for: ProfileRoute.self) { _ in
                ProfileView(onSignedOut: onSignedOut)
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

                        // Your own picture, not a generic glyph.
                        NavigationLink(value: ProfileRoute()) {
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
        }
        .task {
            await loadFeed()
            myProfile = try? await RexAPI.shared.fetchMyProfile()
        }
        .sheet(isPresented: $showingAddRex, onDismiss: { Task { await loadFeed() } }) {
            AddRexView(onDone: { showingAddRex = false })
        }
        .sheet(item: $editing) { rec in
            EditRexView(
                rec: rec,
                onSaved: { Task { await loadFeed() } },
                onDeleted: { Task { await loadFeed() } }
            )
        }
        .sheet(item: $addingToCollection) { rec in
            AddToCollectionView(rec: rec, onDone: {})
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            // No "Your feed" heading — the feed is the home screen, so naming
            // it just eats vertical space above the content.
            searchField

            if !availableCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        filterChip(title: "All", isActive: filter == nil) {
                            filter = nil; subFilter = nil
                        }
                        ForEach(availableCategories, id: \.self) { category in
                            filterChip(title: category.label, isActive: filter == category) {
                                filter = (filter == category) ? nil : category
                                subFilter = nil
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

    private var searchField: some View {
        HStack(spacing: RexSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(RexColor.placeholder)
            TextField("Search Rex, people, places…", text: $query)
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.foreground)
                .autocorrectionDisabled()
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
        if RexCategory(rawType: rec.items?.type) == .trip {
            path.append(TripRoute(recommendationId: rec.id, title: rec.items?.title ?? "Trip"))
        } else {
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

    private func loadFeed() async {
        isLoading = recommendations.isEmpty
        errorMessage = nil
        do {
            // Friends' wants sit in the feed alongside Rex, newest first, so
            // "I want to try this" is something people can answer.
            async let rex = RexAPI.shared.fetchFeed()
            async let wantsFeed = RexAPI.shared.fetchWantsFeed()
            let merged = (try await rex) + ((try? await wantsFeed) ?? [])
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
