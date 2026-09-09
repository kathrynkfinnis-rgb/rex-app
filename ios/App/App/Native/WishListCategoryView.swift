import SwiftUI

/// Where a "My Wish Lists" shelf tile leads — every want in one category, as
/// a plain swipe-to-remove list.
struct WishListRoute: Hashable {
    let category: RexCategory
}

struct WishListCategoryView: View {
    let route: WishListRoute

    @State private var wants: [WantRow] = []
    @State private var isLoading = true
    @State private var pushedItemId: String?
    /// Sept 9 — one sheet modifier, not two. Stacking `.sheet` modifiers
    /// on the same view silently drops all but one of them, which is why
    /// "Rate it" appeared to do nothing: the collection sheet below it won.
    /// Same fault, same fix as AddRexView (5 Sept) and CollectionDetailView
    /// (8 Sept).
    private enum ActiveSheet: Identifiable {
        case edit(FeedRecommendation)
        case collection(WantRow)
        var id: String {
            switch self {
            case .edit(let rec): return "edit-\(rec.id)"
            case .collection(let want): return "collection-\(want.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    /// Sept 7 — "need to be able to edit from want to try to rating once the
    /// book has been read". This screen had no edit path at all: you could
    /// remove a want or open the item, and that was it — so there was
    /// nowhere to say you'd actually done the thing. EditRexView already
    /// knows how to convert a want into a rated Rex (see its wantRowId), it
    /// just needed reaching from here.
    /// Sub-category filter (genre) within this one category — same idea as
    /// the feed's own subcategory row, just scoped to what's actually saved
    /// here rather than the whole feed.
    @State private var subFilter: String?

    private var availableSubcategories: [String] {
        var set = Set<String>()
        for want in wants {
            set.formUnion(splitGenres(want.items?.genre))
        }
        return set.sorted()
    }

    private var visibleWants: [WantRow] {
        guard let subFilter else { return wants }
        return wants.filter { splitGenres($0.items?.genre).contains(subFilter) }
    }

    private var title: String {
        switch route.category {
        case .place: return "Places to go"
        case .trip: return "Trips to take"
        case .book: return "Books to read"
        case .movie: return "Films to watch"
        case .tv: return "TV to watch"
        case .podcast: return "Podcasts to listen to"
        case .recipe: return "Recipes to cook"
        case .event: return "Events to attend"
        case .other: return "Other"
        // A "want to try" for a List doesn't really make sense (you don't
        // want-to-try a list of things, you'd want the things on it) — kept
        // for exhaustiveness rather than because this is reachable today.
        case .list: return "Lists"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if isLoading {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 66)
                    }
                } else if wants.isEmpty {
                    empty()
                } else {
                    if !availableSubcategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: RexSpacing.sm) {
                                ForEach(availableSubcategories, id: \.self) { genre in
                                    filterChip(genre, isSelected: subFilter == genre) {
                                        subFilter = (subFilter == genre) ? nil : genre
                                    }
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                        .padding(.bottom, RexSpacing.xs)
                    }
                    if visibleWants.isEmpty {
                        Text("Nothing matches that filter.")
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    ForEach(visibleWants) { want in
                        if let item = want.items {
                            SwipeToRemove(
                                label: "Remove",
                                systemImage: "bookmark.slash",
                                onTap: { pushedItemId = item.id },
                                action: { await remove(want) }
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

                                    // Sept 9 — "you should be able to edit
                                    // a want to try as well as a Rex". It
                                    // opens the same editor a Rex gets —
                                    // rate it, fix the title, correct the
                                    // address, delete it — so the label
                                    // says Edit rather than only naming the
                                    // one thing it used to be for.
                                    Button {
                                        activeSheet = .edit(asRecommendation(want))
                                    } label: {
                                        Text("Edit")
                                            .font(RexFont.text(12, weight: .semibold))
                                            .foregroundStyle(RexColor.primary)
                                            .padding(.horizontal, RexSpacing.md)
                                            .padding(.vertical, 7)
                                            .overlay(Capsule().stroke(RexColor.primary, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(RexSpacing.md)
                                .rexCard()
                                // A folder badge when it's already in one —
                                // otherwise there was no way to tell without
                                // opening the sheet.
                                .overlay(alignment: .topTrailing) {
                                    if want.list_id != nil {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(RexColor.primaryForeground)
                                            .padding(5)
                                            .background(RexColor.primary)
                                            .clipShape(Circle())
                                            .padding(6)
                                    }
                                }
                            }
                            .contextMenu {
                                Button {
                                    activeSheet = .edit(asRecommendation(want))
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button {
                                    activeSheet = .collection(want)
                                } label: {
                                    Label(
                                        want.list_id != nil ? "Change collection" : "Add to collection",
                                        systemImage: "folder.badge.plus"
                                    )
                                }
                            }
                        }
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit(let rec):
                EditRexView(
                    rec: rec,
                    onSaved: { Task { await load() } },
                    onDeleted: { Task { await load() } }
                )
            case .collection(let want):
                AddWantToListView(want: want) { newListId in
                    if let index = wants.firstIndex(where: { $0.id == want.id }) {
                        wants[index].list_id = newListId
                    }
                }
            }
        }
        .task { await load() }
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

    private func empty() -> some View {
        VStack(spacing: RexSpacing.sm) {
            Text("Nothing here yet")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Tap the bookmark on any Rex and it'll land here.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }

    /// The same synthetic shape fetchWantsFeed produces for a want, so
    /// EditRexView recognises it as one (it keys off the "want-" prefix) and
    /// offers the want/rated switch.
    private func asRecommendation(_ want: WantRow) -> FeedRecommendation {
        FeedRecommendation(
            id: "want-\(want.id)",
            rating: 0,
            note: nil,
            created_at: want.created_at,
            photo_url: nil,
            photo_urls: nil,
            tags: nil,
            user_id: RexAPI.shared.currentUserId ?? "",
            item_id: want.item_id,
            items: want.items,
            profiles: nil,
            creators: nil,
            trip_section: nil,
            is_anonymous: false,
            list_section: nil,
            show_in_feed: nil,
            recommendation_tags: nil
        )
    }

    private func remove(_ want: WantRow) async {
        guard let itemId = want.items?.id else { return }
        wants.removeAll { $0.id == want.id }
        try? await RexAPI.shared.removeWant(itemId: itemId)
    }

    private func load() async {
        isLoading = true
        let all = (try? await RexAPI.shared.fetchWants()) ?? []
        wants = all.filter { RexCategory(rawType: $0.items?.type) == route.category }
        isLoading = false
    }
}
