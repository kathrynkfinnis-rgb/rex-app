import SwiftUI

/// Collections, in four parts:
///   1. My list — everything you've saved, grouped by category
///   2. My collections — lists you've made to share
///   3. Saved from friends — collections you follow, read-only
///   4. Shared with me — collections you can co-edit
struct CollectionsView: View {
    private enum Tab: String, CaseIterable {
        case mine = "My list"
        case collections = "My collections"
        case followed = "Saved"
        case shared = "Shared with me"
    }

    @State private var tab: Tab = .mine
    @State private var wants: [WantRow] = []
    @State private var lists: [RexList] = []
    @State private var followed: [RexList] = []
    @State private var sharedWithMe: [RexList] = []
    @State private var owners: [String: RexProfileDetail] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    /// "My list" grouped by category — Places to eat, Trips to take, and so on.
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
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    header

                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: RexRadius.card)
                                .fill(RexColor.muted)
                                .frame(height: 80)
                        }
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else {
                        switch tab {
                        case .mine: myList
                        case .collections: collectionList(lists, emptyTitle: "No collections yet",
                                                          emptyBody: "Make a list to share — like \u{201C}My favourite pubs in London\u{201D}.")
                        case .followed: collectionList(followed, emptyTitle: "Nothing saved yet",
                                                       emptyBody: "Save a friend's collection and it'll live here.",
                                                       showOwner: true)
                        case .shared: collectionList(sharedWithMe, emptyTitle: "Nothing shared with you",
                                                     emptyBody: "Collections friends invite you to edit appear here.",
                                                     showOwner: true)
                        }
                    }
                }
                .padding(.horizontal, RexSpacing.page)
                .padding(.bottom, RexSpacing.xxxl)
            }
            .refreshable { await load() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            Text("Collections")
                .font(RexFont.display(32, weight: .semibold))
                .foregroundStyle(RexColor.foreground)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Button { tab = t } label: {
                            Text("\(t.rawValue)\(count(for: t))")
                                .font(RexFont.text(13, weight: tab == t ? .semibold : .regular))
                                .foregroundStyle(tab == t ? RexColor.primaryForeground : RexColor.mutedForeground)
                                .padding(.horizontal, RexSpacing.md)
                                .padding(.vertical, 7)
                                .background(tab == t ? RexColor.primary : RexColor.card)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(tab == t ? RexColor.primary : RexColor.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.top, RexSpacing.sm)
    }

    private func count(for t: Tab) -> String {
        let n: Int
        switch t {
        case .mine: n = wants.count
        case .collections: n = lists.count
        case .followed: n = followed.count
        case .shared: n = sharedWithMe.count
        }
        return n > 0 ? " \(n)" : ""
    }

    // MARK: - Sections

    @ViewBuilder
    private var myList: some View {
        if wants.isEmpty {
            empty("Nothing saved yet", "Tap the bookmark on any Rex and it'll land here.")
        } else {
            ForEach(wantsByCategory, id: \.category) { group in
                VStack(alignment: .leading, spacing: RexSpacing.sm) {
                    HStack(spacing: RexSpacing.sm) {
                        Image(systemName: group.category.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(RexColor.primary)
                        Text(headingFor(group.category))
                            .font(RexFont.display(18, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Spacer()
                        Text("\(group.items.count)")
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                    }

                    ForEach(group.items) { want in
                        if let item = want.items {
                            NavigationLink(value: item.id) {
                                HStack(spacing: RexSpacing.md) {
                                    thumb(item)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(RexFont.text(15, weight: .medium))
                                            .foregroundStyle(RexColor.foreground)
                                            .lineLimit(1)
                                        if let sub = item.subtitle ?? item.address, !sub.isEmpty {
                                            Text(sub)
                                                .font(RexFont.text(12))
                                                .foregroundStyle(RexColor.mutedForeground)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(RexSpacing.md)
                                .rexCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
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

    @ViewBuilder
    private func thumb(_ item: RexItem) -> some View {
        Group {
            if let s = item.image_url, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else { RexColor.muted }
                }
            } else {
                RexColor.muted.overlay(
                    Image(systemName: RexCategory(rawType: item.type).symbol)
                        .foregroundStyle(RexColor.mutedForeground)
                )
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
    }

    @ViewBuilder
    private func collectionList(
        _ items: [RexList],
        emptyTitle: String,
        emptyBody: String,
        showOwner: Bool = false
    ) -> some View {
        if items.isEmpty {
            empty(emptyTitle, emptyBody)
        } else {
            ForEach(items) { list in
                HStack(spacing: RexSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                            .fill(RexColor.badgeBackground)
                        Text(list.emoji ?? "\u{1F4D2}").font(.system(size: 20))
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.name)
                            .font(RexFont.display(17, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        if showOwner, let ownerId = list.user_id, let owner = owners[ownerId] {
                            Text("by \(owner.display_name ?? owner.username)")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        } else if let type = list.item_type, !type.isEmpty {
                            Text(RexCategory(rawType: type).label)
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                    Spacer()
                    if list.visibility == "public" {
                        Text("Public")
                            .font(RexFont.text(11, weight: .medium))
                            .foregroundStyle(RexColor.badgeForeground)
                            .padding(.horizontal, RexSpacing.sm)
                            .padding(.vertical, 3)
                            .background(RexColor.badgeBackground)
                            .clipShape(Capsule())
                    }
                }
                .padding(RexSpacing.cardPadding)
                .rexCard()
            }
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
