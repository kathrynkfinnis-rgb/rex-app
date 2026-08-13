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
    @State private var errorMessage: String?
    @State private var filter: RexCategory?
    @State private var theirLists: [RexList] = []
    @State private var myFollowedListIds: Set<String> = []
    @State private var followBusyIds: Set<String> = []

    private var availableCategories: [RexCategory] {
        let present = Set(recommendations.compactMap { RexCategory(rawType: $0.items?.type) })
        return rexAllCategories.filter { present.contains($0) }
    }

    private var visible: [FeedRecommendation] {
        guard let filter else { return recommendations }
        return recommendations.filter { RexCategory(rawType: $0.items?.type) == filter }
    }

    private var averageRating: Double? {
        let rated = recommendations.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return nil }
        return rated.reduce(0) { $0 + $1.rating } / Double(rated.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                header

                if !theirLists.isEmpty {
                    collectionsShelf
                }

                if !availableCategories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: RexSpacing.sm) {
                            chip("All", active: filter == nil) { filter = nil }
                            ForEach(availableCategories, id: \.self) { c in
                                chip(c.label, active: filter == c) {
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
                    Text(recommendations.isEmpty ? "Nothing Rex'd yet." : "Nothing in this category.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, RexSpacing.xxl)
                } else {
                    LazyVStack(spacing: RexSpacing.betweenCards) {
                        ForEach(visible) { rec in
                            if RexCategory(rawType: rec.items?.type) == .trip {
                                NavigationLink(value: TripRoute(
                                    recommendationId: rec.id,
                                    title: rec.items?.title ?? "Trip",
                                )) {
                                    RecommendationCardView(rec: rec)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(value: rec.item_id) {
                                    RecommendationCardView(rec: rec)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.bottom, RexSpacing.xxxl)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(profile?.display_name ?? route.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: RexSpacing.lg) {
            UserAvatarView(
                url: profile?.avatar_url,
                name: profile?.display_name ?? route.name,
                size: 64
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.display_name ?? route.name)
                    .font(RexFont.display(22, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                if let username = profile?.username {
                    Text("@\(username)")
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                }
                HStack(spacing: RexSpacing.md) {
                    Text("\(recommendations.count) Rex")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                    if let averageRating {
                        HStack(spacing: 3) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(RexColor.primary)
                            Text("avg \(String(format: "%.1f", averageRating))")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                }
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(.top, RexSpacing.sm)
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
        return VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: CollectionRoute(listId: list.id, name: list.name, isMine: false)) {
                ZStack {
                    RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                        .fill(RexColor.badgeBackground)
                    Text(list.emoji ?? "\u{1F4D2}").font(.system(size: 28))
                }
                .frame(width: 112, height: 112)
            }
            .buttonStyle(.plain)

            Text(list.name)
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)

            Button {
                Task { await toggleFollow(list) }
            } label: {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(saved ? "Saved" : "Save")
                        .font(RexFont.text(11, weight: .semibold))
                        .foregroundStyle(saved ? RexColor.mutedForeground : RexColor.primaryForeground)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 4)
                        .background(saved ? RexColor.card : RexColor.primary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(saved ? RexColor.border : .clear, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)
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
        do {
            async let profileTask = RexAPI.shared.fetchProfiles(ids: [route.userId])
            async let recsTask = RexAPI.shared.fetchRecommendations(forUser: route.userId)
            async let listsTask = RexAPI.shared.fetchLists(forUser: route.userId)
            async let followedTask = RexAPI.shared.fetchFollowedLists()
            let (profiles, recs, lists, followedLists) = try await (profileTask, recsTask, listsTask, followedTask)
            profile = profiles.first
            recommendations = recs
            theirLists = lists
            myFollowedListIds = Set(followedLists.map { $0.id })
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
