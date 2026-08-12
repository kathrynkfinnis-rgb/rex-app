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
    @State private var typeFilter: RexCategory?
    @State private var wants: [WantRow] = []
    @State private var lists: [RexList] = []
    @State private var followed: [RexList] = []
    @State private var sharedWithMe: [RexList] = []
    @State private var owners: [String: RexProfileDetail] = [:]
    /// Contents of each collection, keyed by list id — drives the preview strips.
    @State private var contents: [String: [SavedPost]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var dropTarget: String?
    /// Swiping rows can't be NavigationLinks, so taps push through here instead.
    @State private var pushedItemId: String?

    /// "My list" grouped by category — Places to eat, Trips to take, and so on.
    private var wantsByCategory: [(category: RexCategory, items: [WantRow])] {
        var buckets: [RexCategory: [WantRow]] = [:]
        for want in filteredWants {
            let c = RexCategory(rawType: want.items?.type)
            buckets[c, default: []].append(want)
        }
        return rexAllCategories.compactMap { c in
            guard let items = buckets[c], !items.isEmpty else { return nil }
            return (category: c, items: items)
        }
    }

    private var filteredWants: [WantRow] {
        guard let typeFilter else { return wants }
        return wants.filter { RexCategory(rawType: $0.items?.type) == typeFilter }
    }

    /// A collection matches a filter if it's typed that way, or if anything
    /// inside it is — a mixed list shouldn't vanish just because it's untyped.
    private func filtered(_ items: [RexList]) -> [RexList] {
        guard let typeFilter else { return items }
        return items.filter { list in
            if let t = list.item_type, RexCategory(rawType: t) == typeFilter { return true }
            return (contents[list.id] ?? []).contains {
                RexCategory(rawType: $0.recommendations?.items?.type) == typeFilter
            }
        }
    }

    /// Only offer filters for content the user actually has.
    private var availableCategories: [RexCategory] {
        var present = Set(wants.compactMap { $0.items?.type }.map { RexCategory(rawType: $0) })
        for rows in contents.values {
            for row in rows {
                present.insert(RexCategory(rawType: row.recommendations?.items?.type))
            }
        }
        for list in lists + followed + sharedWithMe {
            if let t = list.item_type { present.insert(RexCategory(rawType: t)) }
        }
        return rexAllCategories.filter { present.contains($0) }
    }

    var body: some View {
        ZStack {
            RexColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    header

                    // Keep whatever loaded last time visible when a refresh fails.
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
                                .frame(height: 80)
                        }
                    } else if errorMessage == nil || !(wants.isEmpty && lists.isEmpty) {
                        switch tab {
                        case .mine: myList
                        case .collections: collectionList(filtered(lists), emptyTitle: "No collections yet",
                                                          emptyBody: "Make a list to share — like \u{201C}My favourite pubs in London\u{201D}.",
                                                          isMine: true)
                        case .followed: collectionList(filtered(followed), emptyTitle: "Nothing saved yet",
                                                       emptyBody: "Save a friend's collection and it'll live here.",
                                                       showOwner: true)
                        case .shared: collectionList(filtered(sharedWithMe), emptyTitle: "Nothing shared with you",
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
        .navigationDestination(item: $pushedItemId) { ItemDetailView(itemId: $0) }
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

            if availableCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        typeChip(nil, label: "All")
                        ForEach(availableCategories, id: \.self) { c in
                            typeChip(c, label: c.label)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(.top, RexSpacing.sm)
    }

    private func typeChip(_ c: RexCategory?, label: String) -> some View {
        let selected = typeFilter == c
        return Button {
            typeFilter = c
        } label: {
            HStack(spacing: 5) {
                if let c { Image(systemName: c.symbol).font(.system(size: 10)) }
                Text(label).font(RexFont.text(12, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? RexColor.primary : RexColor.mutedForeground)
            .padding(.horizontal, RexSpacing.sm + 2)
            .padding(.vertical, 5)
            .background(selected ? RexColor.badgeBackground : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(selected ? RexColor.primary.opacity(0.4) : RexColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
        if filteredWants.isEmpty {
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
                            SwipeToRemove(
                                label: "Remove",
                                systemImage: "bookmark.slash",
                                onTap: { pushedItemId = item.id },
                                action: { await removeWant(want) }
                            ) {
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
        showOwner: Bool = false,
        isMine: Bool = false
    ) -> some View {
        if items.isEmpty {
            empty(emptyTitle, emptyBody)
        } else {
            ForEach(items) { list in
                VStack(alignment: .leading, spacing: RexSpacing.sm) {
                    NavigationLink(value: CollectionRoute(listId: list.id, name: list.name, isMine: isMine)) {
                        collectionHeaderRow(list, showOwner: showOwner)
                    }
                    .buttonStyle(.plain)

                    preview(for: list)
                }
                .padding(RexSpacing.cardPadding)
                .rexCard()
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                        .stroke(dropTarget == list.id ? RexColor.primary : .clear, lineWidth: 2)
                )
                // Drag a Rex from anywhere and drop it here. Dropping copies —
                // the same Rex can sit in several collections.
                .dropDestination(for: String.self) { ids, _ in
                    guard isMine else { return false }
                    Task { await drop(ids, into: list) }
                    return true
                } isTargeted: { targeted in
                    dropTarget = targeted && isMine ? list.id : nil
                }
            }
        }
    }

    private func collectionHeaderRow(_ list: RexList, showOwner: Bool) -> some View {
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
                } else {
                    Text(subtitleFor(list))
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
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RexColor.mutedForeground)
        }
        // Without this the gaps either side of the Spacer aren't hit-testable,
        // so most of the row looks tappable but isn't.
        .contentShape(Rectangle())
    }

    private func subtitleFor(_ list: RexList) -> String {
        let n = (contents[list.id] ?? []).count
        if n > 0 { return n == 1 ? "1 Rex" : "\(n) Rex" }
        if let type = list.item_type, !type.isEmpty { return RexCategory(rawType: type).label }
        return "Empty"
    }

    /// A swipeable strip of what's inside, so you can see a collection without
    /// opening it.
    @ViewBuilder
    private func preview(for list: RexList) -> some View {
        let rows = contents[list.id] ?? []
        if !rows.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    ForEach(rows) { row in
                        if let rec = row.recommendations, let item = rec.items {
                            NavigationLink(value: item.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    previewImage(item)
                                    Text(item.title)
                                        .font(RexFont.text(11, weight: .medium))
                                        .foregroundStyle(RexColor.foreground)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(width: 92, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            // Drag one out and drop it on another collection to
                            // copy it across.
                            .draggable(rec.id)
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    @ViewBuilder
    private func previewImage(_ item: RexItem) -> some View {
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
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
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

    private func removeWant(_ want: WantRow) async {
        guard let itemId = want.items?.id else { return }
        wants.removeAll { $0.id == want.id }
        try? await RexAPI.shared.removeWant(itemId: itemId)
    }

    private func drop(_ recommendationIds: [String], into list: RexList) async {
        for id in recommendationIds {
            try? await RexAPI.shared.addToCollection(recommendationId: id, listId: list.id)
        }
        contents[list.id] = (try? await RexAPI.shared.fetchCollectionItems(listId: list.id)) ?? contents[list.id]
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

    /// Fetch every collection's contents at once so the preview strips and the
    /// type filter have something to work with.
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
