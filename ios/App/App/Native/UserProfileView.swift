import SwiftUI

/// Route to someone else's profile. Carries the name so the screen has a
/// title before the fetch lands.
struct UserProfileRoute: Hashable {
    let userId: String
    let name: String
}

/// Someone else's profile: who they are, what they've Rex'd, filterable by
/// category — the read-only counterpart to ProfileView.
struct UserProfileView: View {
    let route: UserProfileRoute

    @State private var profile: RexProfileDetail?
    @State private var recommendations: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var showingAsk = false
    @State private var errorMessage: String?
    @State private var filter: RexCategory?
    @State private var theirLists: [RexList] = []
    @State private var myFollowedListIds: Set<String> = []
    @State private var followBusyIds: Set<String> = []
    @State private var addingToCollection: FeedRecommendation?
    @State private var rexCounts: [String: Int] = [:]
    /// Sept 14 — "look at your friends' friends as another way to find
    /// users". Only ever filled for someone you're friends with; the
    /// database returns nothing for anyone else, and then there's no row.
    @State private var theirFriends: [FoundPerson] = []
    @State private var showingTheirFriends = false
    /// Sept 15 — "Really tricky to add friends. No option on Phoebe's page
    /// to add her" (Danny). Your relationship with this person: nil while
    /// loading, then "none", "requested", "requested_you", "friend", "you".
    @State private var connection: String?
    /// Oct 7 — joined date and counts, for a profile you aren't connected to.
    @State private var stats: RexProfileStats?
    @State private var connectionFriendshipId: String?
    @State private var isChangingConnection = false
    /// Sept 17 — reporting or blocking this person.
    @Environment(\.dismiss) private var dismissSelf
    @State private var reporting: ReportSubject?
    @State private var confirmingBlock = false
    /// #148 — this shelf showed a plain emoji square per collection; the
    /// same shelf on your own Collections page (and Explore's friend-
    /// collections cards) shows a 2x2 grid of the collection's own content
    /// thumbnails instead (ThumbnailGridView, #131). Same fetch pattern as
    /// ExploreView: one fetchCollectionItems call per list, in parallel.
    @State private var listThumbnails: [String: [String]] = [:]
    @State private var listItemCounts: [String: Int] = [:]

    private var availableCategories: [RexCategory] {
        let present = Set(recommendations.compactMap { RexCategory(rawType: $0.items?.type) })
        return rexAllCategories.filter { present.contains($0) }
    }

    /// A friend of yours who has posted nothing — as distinct from someone
    /// you can't see yet, whose Rex are hidden rather than absent.
    /// "Send Phoebe a Rex" rather than "Send phoebebragg a Rex".
    /// Their name, as best we know it. The route carries one so the page has
    /// a title the instant it opens; a push notification carries only a user
    /// id and passes none, and then the only honest thing to say until the
    /// profile lands is nothing in particular.
    private var displayName: String {
        if let loaded = profile?.display_name, !loaded.isEmpty { return loaded }
        if !route.name.isEmpty { return route.name }
        return "This person"
    }

    private var firstName: String {
        let name = displayName
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private var isEmptyFriend: Bool {
        recommendations.isEmpty && connection == "friend"
    }

    private var visible: [FeedRecommendation] {
        guard let filter else { return recommendations }
        return recommendations.filter { RexCategory(rawType: $0.items?.type) == filter }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                header

                if !theirFriends.isEmpty {
                    theirFriendsRow
                }

                if !theirLists.isEmpty {
                    collectionsShelf
                }

                if !availableCategories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: RexSpacing.sm) {
                            chip("All", active: filter == nil) { filter = nil }
                            ForEach(availableCategories, id: \.self) { c in
                                chip(c.pluralLabel, active: filter == c) {
                                    filter = (filter == c) ? nil : c
                                }
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 120)
                    }
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if visible.isEmpty {
                    // A stranger's Rex are friends-only, so "Nothing Rex'd
                    // yet" was untrue on Phoebe's page — she has hundreds.
                    //
                    // Sept 29 — "friends homepage, if they haven't Rex'd
                    // anything, what do we want to see here?" A friend with an
                    // empty page is the one case where there's something
                    // useful to do about it: ask them for something. The
                    // hard-hat Rex says the page is waiting rather than
                    // broken, and the button turns a dead end into a blast.
                    VStack(spacing: RexSpacing.md) {
                        Image(isEmptyFriend ? "RexUnderConstruction" : "RexPlaceholderList")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                            .opacity(0.9)
                            .accessibilityHidden(true)
                        Text(recommendations.isEmpty
                             ? (connection == "none" || connection == "requested" || connection == "requested_you"
                                ? "Add \(displayName) as a friend to see their Rex."
                                : "\(displayName) hasn’t Rex’d anything yet.")
                             : "Nothing in this category.")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.mutedForeground)
                            .multilineTextAlignment(.center)

                        if isEmptyFriend {
                            Text("Tag them in something you'd recommend — it lands in their notifications, and it's a better nudge than an empty page.")
                                .font(RexFont.text(13))
                                .foregroundStyle(RexColor.mutedForeground)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, RexSpacing.lg)
                            Button {
                                showingAsk = true
                            } label: {
                                Label("Send \(firstName) a Rex", systemImage: "paperplane")
                                    .font(RexFont.text(15, weight: .semibold))
                            }
                            .buttonStyle(RexPrimaryButtonStyle())
                            .padding(.top, RexSpacing.xs)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RexSpacing.xxl)
                } else {
                    LazyVStack(spacing: RexSpacing.betweenCards) {
                        ForEach(visible) { rec in
                            Group {
                                if RexCategory(rawType: rec.items?.type) == .trip {
                                    NavigationLink(value: TripRoute(
                                        recommendationId: rec.id,
                                        title: rec.items?.title ?? "Trip",
                                    )) {
                                        RecommendationCardView(rec: rec, rexCount: rexCounts[rec.item_id] ?? 0)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink(value: rec.item_id) {
                                        RecommendationCardView(rec: rec, rexCount: rexCounts[rec.item_id] ?? 0)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .contextMenu {
                                Button {
                                    addingToCollection = rec
                                } label: {
                                    Label("Add to collection", systemImage: "folder.badge.plus")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.bottom, RexSpacing.xxxl)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if route.userId != RexAPI.shared.currentUserId {
                    Menu {
                        Button {
                            reporting = .person(route.userId, name: displayName)
                        } label: {
                            Label("Report", systemImage: "flag")
                        }
                        Button(role: .destructive) {
                            confirmingBlock = true
                        } label: {
                            Label("Block", systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAsk) {
            AddRexView(onDone: { showingAsk = false }, taggingFriend: route.userId)
        }
        .sheet(item: $reporting) { subject in
            ReportSheet(subject: subject, onBlocked: { dismissSelf() })
        }
        .alert("Block \(displayName)?", isPresented: $confirmingBlock) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) { Task { await block() } }
        } message: {
            Text("You won't see each other's Rex, and any friendship between you ends. They aren't told.")
        }
        .navigationDestination(isPresented: $showingTheirFriends) {
            FriendsOfView(userId: route.userId, name: displayName)
        }
        .sheet(item: $addingToCollection) { rec in
            AddToCollectionView(rec: rec) { addingToCollection = nil }
        }
        .task {
            await load()
            await loadConnection()
        }
    }

    /// A row of their friends' faces and a count — tap through for the full
    /// list, with an Add button beside anyone you don't know yet.
    private var theirFriendsRow: some View {
        let others = theirFriends.filter { $0.connection == "none" }.count
        return Button {
            showingTheirFriends = true
        } label: {
            HStack(spacing: RexSpacing.md) {
                HStack(spacing: -10) {
                    ForEach(theirFriends.prefix(4)) { person in
                        UserAvatarView(url: person.avatar_url, name: person.name, size: 30)
                            .overlay(Circle().stroke(RexColor.card, lineWidth: 2))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(theirFriends.count) \(theirFriends.count == 1 ? "friend" : "friends")")
                        .font(RexFont.text(14, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    if others > 0 {
                        Text("\(others) you\u{2019}re not friends with yet")
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RexColor.placeholder)
            }
            .padding(RexSpacing.md)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous).stroke(RexColor.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: RexSpacing.lg) {
            UserAvatarView(
                url: profile?.avatar_url,
                name: displayName,
                size: 64
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(RexFont.display(22, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                if let username = profile?.username {
                    Text("@\(username)")
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                }
                // No count for someone you're not friends with — their Rex
                // are friends-only, so it would always say a misleading 0.
                if !recommendations.isEmpty || connection == "friend" || connection == "you" {
                HStack(spacing: RexSpacing.md) {
                    Text("\(recommendations.count) Rex")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                    RexRatingAverageBadge(ratings: recommendations.map { $0.rating })
                }
                .padding(.top, 2)
                } else {
                    // Oct 7 — "have her name at the top! And then maybe the
                    // date joined, how many Rexes etc."
                    //
                    // For a stranger the page was a name and an Add friend
                    // button with nothing to go on. These counts come from
                    // profile_basics rather than from their Rex, which are
                    // friends-only and so read as 0 from out here — the
                    // reason the line above is hidden for a stranger at all.
                    strangerStatsRow
                }
                connectionButton
                    .padding(.top, RexSpacing.xs)
            }
            Spacer()
        }
        .padding(.top, RexSpacing.sm)
    }

    /// What we can honestly say about somebody we aren't connected to: how
    /// long they've been here and how much they've done. Not what they Rex'd
    /// — that's what being friends is for.
    @ViewBuilder
    private var strangerStatsRow: some View {
        if let stats {
            HStack(spacing: RexSpacing.md) {
                if let count = stats.rex_count, count > 0 {
                    Text("\(count) Rex")
                }
                if let friends = stats.friend_count, friends > 0 {
                    Text("\(friends) \(friends == 1 ? "friend" : "friends")")
                }
                if let joined = stats.joinedDate {
                    Text("Joined \(joined.formatted(.dateTime.month(.abbreviated).year()))")
                }
            }
            .font(RexFont.text(12))
            .foregroundStyle(RexColor.mutedForeground)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var connectionButton: some View {
        switch connection {
        case "none":
            Button {
                Task { await addFriend() }
            } label: {
                Label("Add friend", systemImage: "person.badge.plus")
                    .font(RexFont.text(13, weight: .semibold))
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(RexColor.primary)
                    .foregroundStyle(RexColor.primaryForeground)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isChangingConnection)
        case "requested":
            Label("Request sent", systemImage: "clock")
                .font(RexFont.text(13, weight: .medium))
                .foregroundStyle(RexColor.mutedForeground)
        case "requested_you":
            Button {
                Task { await acceptFriend() }
            } label: {
                Label("Accept friend request", systemImage: "checkmark")
                    .font(RexFont.text(13, weight: .semibold))
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(RexColor.primary)
                    .foregroundStyle(RexColor.primaryForeground)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isChangingConnection)
        case "friend":
            Label("Friends", systemImage: "checkmark")
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        default:
            EmptyView()
        }
    }

    private func block() async {
        isChangingConnection = true
        if (try? await RexAPI.shared.blockUser(id: route.userId)) != nil {
            dismissSelf()
        }
        isChangingConnection = false
    }

    private func loadConnection() async {
        guard let me = RexAPI.shared.currentUserId else { return }
        if route.userId == me { connection = "you"; return }
        guard let friendships = try? await RexAPI.shared.fetchFriendships() else { return }
        let match = friendships.first {
            ($0.requester_id == me && $0.addressee_id == route.userId)
                || ($0.addressee_id == me && $0.requester_id == route.userId)
        }
        connectionFriendshipId = match?.id
        switch (match?.status, match?.requester_id == me) {
        case ("accepted", _): connection = "friend"
        case ("pending", true): connection = "requested"
        case ("pending", false): connection = "requested_you"
        default: connection = "none"
        }
    }

    private func addFriend() async {
        isChangingConnection = true
        if (try? await RexAPI.shared.sendFriendRequest(addresseeId: route.userId)) != nil {
            connection = "requested"
        }
        isChangingConnection = false
    }

    private func acceptFriend() async {
        guard let id = connectionFriendshipId else { return }
        isChangingConnection = true
        if (try? await RexAPI.shared.respondToFriendRequest(id: id, accept: true)) != nil {
            connection = "friend"
            await load()
        }
        isChangingConnection = false
    }

    /// Their public and friends-visible collections — never `draft`, those
    /// aren't yours to see. Save one and it shows up in your own "Friends'
    /// Collections" shelf.
    private var collectionsShelf: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            HStack(spacing: RexSpacing.sm) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(RexColor.primary)
                Text("Collections")
                    .font(RexFont.display(17, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: RexSpacing.md) {
                    ForEach(theirLists) { list in
                        collectionTile(list)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func collectionTile(_ list: RexList) -> some View {
        let saved = myFollowedListIds.contains(list.id)
        let busy = followBusyIds.contains(list.id)
        let thumbnails = listThumbnails[list.id] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: CollectionRoute(listId: list.id, name: list.name, isMine: false)) {
                ZStack {
                    if thumbnails.isEmpty {
                        RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                            .fill(RexColor.badgeBackground)
                        Text(list.emoji ?? "\u{1F4D2}").font(.system(size: 28))
                    } else {
                        // #148 — matches the 2x2 content-thumbnail grid your
                        // own Collections page and Explore's friend-
                        // collection cards already use (ThumbnailGridView,
                        // #131), instead of a plain emoji placeholder.
                        ThumbnailGridView(urls: thumbnails)
                    }
                }
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)

            // Same #127 fix applied here too — one more spot with the same
            // truncated-title complaint.
            Text(list.name)
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 112, alignment: .leading)

            if let count = listItemCounts[list.id] {
                Text(count == 1 ? "1 item" : "\(count) items")
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            // Press-and-hold to save, not a tap — this tile sits inside a
            // horizontal scroll row, where a quick tap is often really a
            // swipe that missed.
            if busy {
                ProgressView().controlSize(.mini).frame(height: 24)
            } else if saved {
                Button {
                    Task { await toggleFollow(list) }
                } label: {
                    Text("Saved")
                        .font(RexFont.text(11, weight: .semibold))
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 4)
                        .background(RexColor.card)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(RexColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                PressAndHoldButton(label: "Hold to save") {
                    Task { await toggleFollow(list) }
                }
            }
        }
        .frame(width: 112, alignment: .leading)
    }

    private func toggleFollow(_ list: RexList) async {
        followBusyIds.insert(list.id)
        let wasSaved = myFollowedListIds.contains(list.id)
        do {
            if wasSaved {
                try await RexAPI.shared.unfollowList(listId: list.id)
                myFollowedListIds.remove(list.id)
            } else {
                try await RexAPI.shared.followList(listId: list.id)
                myFollowedListIds.insert(list.id)
            }
        } catch {
            // Leave the toggle where it was — the button just reverts.
        }
        followBusyIds.remove(list.id)
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RexFont.text(13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? RexColor.primaryForeground : RexColor.mutedForeground)
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, 7)
                .background(active ? RexColor.primary : RexColor.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? RexColor.primary : RexColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        // Oct 5 — "why would this be the page for trying to request a new
        // friend": a stranger's profile opened with no name, no avatar, no
        // username — just the word "Profile" and an Add friend button.
        //
        // All four of these used to be awaited together inside the do block
        // below, so when one threw, none of them landed. A stranger's Rex and
        // lists are hidden by design, so for exactly the person you most need
        // this page for — someone you aren't friends with yet — the throw took
        // their name down with it. Who they are is fetched on its own now and
        // survives whatever the rest does, because deciding whether to send a
        // friend request means seeing who you'd be sending it to.
        profile = (try? await RexAPI.shared.fetchProfiles(ids: [route.userId]))?.first
        stats = await RexAPI.shared.fetchProfileStats(userId: route.userId)

        do {
            async let recsTask = RexAPI.shared.fetchRecommendations(forUser: route.userId)
            async let listsTask = RexAPI.shared.fetchLists(forUser: route.userId)
            async let followedTask = RexAPI.shared.fetchFollowedLists()
            let (recs, lists, followedLists) = try await (recsTask, listsTask, followedTask)
            recommendations = RexAPI.shared.filterHidden(recs)
            theirLists = lists
            myFollowedListIds = Set(followedLists.map { $0.id })
            let itemIds = Array(Set(recs.map { $0.item_id }))
            rexCounts = (try? await RexAPI.shared.fetchRexCounts(itemIds: itemIds)) ?? [:]
            // Best-effort: before the 14 Sept migration the function doesn't
            // exist, and a stranger's list comes back empty by design.
            theirFriends = (try? await RexAPI.shared.fetchFriendsOf(userId: route.userId)) ?? []

            // #148 — same per-list thumbnail fetch as ExploreView's friend-
            // collection cards, so this shelf matches the one on your own
            // Collections page instead of a plain emoji square.
            await withTaskGroup(of: (String, [SavedPost]).self) { group in
                for list in lists {
                    group.addTask {
                        let items = (try? await RexAPI.shared.fetchCollectionItems(listId: list.id)) ?? []
                        return (list.id, items)
                    }
                }
                for await (listId, items) in group {
                    listThumbnails[listId] = items.prefix(4).compactMap { $0.recommendations?.items?.image_url }
                    listItemCounts[listId] = items.count
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
}
