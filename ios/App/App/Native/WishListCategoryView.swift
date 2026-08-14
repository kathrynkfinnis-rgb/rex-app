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

    private var title: String {
        switch route.category {
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
                    ForEach(wants) { want in
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
                                }
                                .padding(RexSpacing.md)
                                .rexCard()
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
        .task { await load() }
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
