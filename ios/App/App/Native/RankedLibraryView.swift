import SwiftUI

struct RankedLibraryRoute: Hashable {
    let category: String
    /// Whose ordering. Nil means your own.
    let userId: String?
    let name: String?
}

/// Oct 13 — the thing Joe actually wants to look at: his library, in order.
///
/// "Personally would love [it] and v useful for other people to see" — so this
/// opens for a friend as readily as for yourself, and says whose it is.
///
/// A numbered list rather than a grid. The number is the whole point: it is
/// the answer to "is x better than y" for every pair at once, which is the
/// question that started this.
struct RankedLibraryView: View {
    let route: RankedLibraryRoute

    @State private var rows: [RankedItem] = []
    @State private var isLoading = true
    @State private var isSeeding = false
    @State private var errorMessage: String?

    private var category: RexCategory { RexCategory(rawType: route.category) }
    private var isMine: Bool { route.userId == nil || route.userId == RexAPI.shared.currentUserId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RexBannerBand(category: category)
                    .padding(.horizontal, -RexSpacing.page)

                VStack(alignment: .leading, spacing: 0) {
                    RexCategoryPill(category: category)

                    Text(isMine ? "Your \(category.pluralLabel.lowercased()), in order"
                                : "\(route.name ?? "Their") \(category.pluralLabel.lowercased())")
                        .font(RexFont.display(rows.count > 0 ? 34 : 30))
                        .foregroundStyle(RexColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

                    if !rows.isEmpty {
                        Text("\(rows.count) ranked \u{00B7} best first")
                            .font(RexFont.editorial(21))
                            .foregroundStyle(RexColor.primary)
                            .padding(.top, 7)
                    }
                }
                .padding(.top, 10)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if rows.isEmpty {
                    emptyState
                } else {
                    list
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                        .padding(.top, RexSpacing.md)
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.bottom, RexSpacing.xxl)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var list: some View {
        VStack(spacing: RexSpacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if let item = row.items {
                    NavigationLink(value: item.id) {
                        HStack(spacing: RexSpacing.md) {
                            // The rank, which is the content here. Wide enough
                            // for three digits so a long library doesn't shunt
                            // every title sideways at number 100.
                            Text("\(index + 1)")
                                .font(RexFont.display(index < 3 ? 26 : 19))
                                .foregroundStyle(index < 3 ? RexColor.primary : RexColor.mutedForeground)
                                .frame(width: 42, alignment: .trailing)

                            Group {
                                if let urlString = item.image_url, let url = URL(string: urlString) {
                                    GoogleSafeAsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: { RexColor.muted }
                                } else {
                                    ZStack {
                                        RexColor.badgeBackground
                                        Image(systemName: category.symbol)
                                            .font(.system(size: 16))
                                            .foregroundStyle(RexColor.primary)
                                    }
                                }
                            }
                            .frame(width: 38, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(RexFont.text(16, weight: .bold))
                                    .foregroundStyle(RexColor.foreground)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                if let subtitle = item.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(RexFont.editorial(17))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(RexColor.border)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, RexSpacing.md)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, RexSpacing.lg)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            Text(isMine
                 ? "Nothing ranked yet. Rex gives you a starting order from the ratings you've already given, and every comparison after that makes it more yours."
                 : "They haven't ranked anything yet.")
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            if isMine {
                Button {
                    Task { await seed() }
                } label: {
                    HStack(spacing: RexSpacing.sm) {
                        if isSeeding { ProgressView().controlSize(.small).tint(RexColor.primaryForeground) }
                        Text(isSeeding ? "Setting it up\u{2026}" : "Start from my ratings")
                            .font(RexFont.text(15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RexSpacing.md)
                    .background(RexColor.primary)
                    .foregroundStyle(RexColor.primaryForeground)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSeeding)
            }
        }
        .padding(.top, RexSpacing.xl)
    }

    private func load() async {
        isLoading = true
        rows = await RexAPI.shared.fetchRanking(userId: route.userId, category: route.category) ?? []
        isLoading = false
    }

    private func seed() async {
        isSeeding = true
        defer { isSeeding = false }
        do {
            try await RexAPI.shared.seedRanking(category: route.category)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
