import SwiftUI

/// Where a shelf's "See all" tile leads: every collection in that section as
/// a vertical feed, each with a header row and a horizontal carousel of its
/// contents underneath — the browsing view from Kathryn's second sketch.
struct CollectionsSectionRoute: Hashable {
    enum Section: Hashable { case mine, friends }
    let section: Section
}

struct CollectionsSectionListView: View {
    let route: CollectionsSectionRoute

    @State private var lists: [RexList] = []
    @State private var owners: [String: RexProfileDetail] = [:]
    @State private var contents: [String: [SavedPost]] = [:]
    @State private var isLoading = true
    @State private var dropTarget: String?
    @State private var pushedItemId: String?

    private var title: String {
        route.section == .mine ? "My Collections" : "Friends' Collections"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 180)
                    }
                } else if lists.isEmpty {
                    empty()
                } else {
                    ForEach(lists) { list in
                        collectionCard(list)
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.vertical, RexSpacing.lg)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushedItemId) { ItemDetailView(itemId: $0) }
        .task { await load() }
    }

    private func collectionCard(_ list: RexList) -> some View {
        let isMine = route.section == .mine
        return VStack(alignment: .leading, spacing: RexSpacing.sm) {
            NavigationLink(value: CollectionRoute(listId: list.id, name: list.name, isMine: isMine)) {
                headerRow(list, isMine: isMine)
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
        // Drag a Rex from anywhere and drop it here. Dropping copies — the
        // same Rex can sit in several collections.
        .dropDestination(for: String.self) { ids, _ in
            guard isMine else { return false }
            Task { await drop(ids, into: list) }
            return true
        } isTargeted: { targeted in
            dropTarget = targeted && isMine ? list.id : nil
        }
    }

    private func headerRow(_ list: RexList, isMine: Bool) -> some View {
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
                if !isMine, let ownerId = list.user_id, let owner = owners[ownerId] {
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
        // Without this the gaps either side of the Spacer aren't hit-testable.
        .contentShape(Rectangle())
    }

    private func subtitleFor(_ list: RexList) -> String {
        let n = (contents[list.id] ?? []).count
        if n > 0 { return n == 1 ? "1 Rex" : "\(n) Rex" }
        if let type = list.item_type, !type.isEmpty { return RexCategory(rawType: type).label }
        return "Empty"
    }

    @ViewBuilder
    private func preview(for list: RexList) -> some View {
        let rows = contents[list.id] ?? []
        if !rows.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    ForEach(rows) { row in
                        if let rec = row.recommendations, let item = rec.items {
                            Button { pushedItemId = item.id } label: {
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

    private func empty() -> some View {
        VStack(spacing: RexSpacing.sm) {
            Text("Nothing here yet")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text(route.section == .mine
                 ? "Make a list to share — like \u{201C}My favourite pubs in London\u{201D}."
                 : "Collections friends share or invite you to edit will appear here.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }

    private func drop(_ recommendationIds: [String], into list: RexList) async {
        for id in recommendationIds {
            try? await RexAPI.shared.addToCollection(recommendationId: id, listId: list.id)
        }
        contents[list.id] = (try? await RexAPI.shared.fetchCollectionItems(listId: list.id)) ?? contents[list.id]
    }

    private func load() async {
        isLoading = true
        switch route.section {
        case .mine:
            lists = (try? await RexAPI.shared.fetchLists()) ?? []
        case .friends:
            async let f = RexAPI.shared.fetchFollowedLists()
            async let c = RexAPI.shared.fetchCollaboratingLists()
            let (ff, fc) = await ((try? f) ?? [], (try? c) ?? [])
            lists = ff + fc
            let ownerIds = Array(Set(lists.compactMap { $0.user_id }))
            if !ownerIds.isEmpty {
                let profiles = (try? await RexAPI.shared.fetchProfiles(ids: ownerIds)) ?? []
                owners = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            }
        }
        await loadContents()
        isLoading = false
    }

    private func loadContents() async {
        let fetched = await withTaskGroup(of: (String, [SavedPost]).self) { group in
            for list in lists {
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
}
