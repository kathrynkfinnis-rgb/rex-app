import SwiftUI

struct RecommendationCardView: View {
    let rec: FeedRecommendation

    private var category: RexCategory { RexCategory(rawType: rec.items?.type) }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var relativeTime: String {
        guard let date = rec.createdDate else { return "" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private var ratingText: String {
        rec.rating.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rec.rating)
            : String(format: "%.1f", rec.rating)
    }

    var body: some View {
        guard let item = rec.items else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: RexSpacing.md) {
                    thumbnail(item: item)

                    VStack(alignment: .leading, spacing: RexSpacing.xs) {
                        HStack(spacing: RexSpacing.sm) {
                            categoryBadge
                            Spacer(minLength: RexSpacing.sm)
                            // Rating is an "important icon" — one of the few
                            // places the spec allows forest green.
                            if rec.rating > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(RexColor.primary)
                                    Text(ratingText)
                                        .font(RexFont.text(14, weight: .semibold))
                                        .foregroundStyle(RexColor.foreground)
                                    Text("/10")
                                        .font(RexFont.text(12))
                                        .foregroundStyle(RexColor.mutedForeground)
                                }
                            }
                        }

                        Text(item.title)
                            .font(RexFont.display(19, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(RexFont.text(13))
                                .foregroundStyle(RexColor.mutedForeground)
                                .lineLimit(1)
                        }

                        if let note = rec.note, !note.isEmpty {
                            Text("\u{201C}\(note)\u{201D}")
                                .font(RexFont.text(14))
                                .foregroundStyle(RexColor.foreground.opacity(0.88))
                                .lineLimit(3)
                                .padding(.top, RexSpacing.xs)
                        }

                        if let tags = rec.tags, !tags.isEmpty {
                            // Neutral, not green — tags aren't an accent surface.
                            HStack(spacing: RexSpacing.xs) {
                                ForEach(tags.prefix(3), id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(RexFont.text(11, weight: .medium))
                                        .foregroundStyle(RexColor.badgeForeground)
                                        .padding(.horizontal, RexSpacing.sm)
                                        .padding(.vertical, 3)
                                        .background(RexColor.badgeBackground)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.top, RexSpacing.xs)
                        }
                    }
                }
                .padding(RexSpacing.cardPadding)

                Rectangle()
                    .fill(RexColor.divider)
                    .frame(height: 1)

                HStack(spacing: RexSpacing.sm) {
                    authorRow
                    Spacer()
                    Text(relativeTime)
                        .font(RexFont.text(11))
                        .foregroundStyle(RexColor.mutedForeground)
                }
                .padding(.horizontal, RexSpacing.cardPadding)
                .padding(.vertical, RexSpacing.md)
            }
            .rexCard()
        )
    }

    private var categoryBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbol).font(.system(size: 9))
            Text(category.label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(RexColor.badgeForeground)
        .padding(.horizontal, RexSpacing.sm)
        .padding(.vertical, 3)
        .background(RexColor.badgeBackground)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func thumbnail(item: RexItem) -> some View {
        Group {
            if let urlString = item.image_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RexColor.muted
                    }
                }
            } else {
                RexColor.muted.overlay(
                    Image(systemName: category.symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(RexColor.mutedForeground)
                )
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
    }

    @ViewBuilder
    private var authorRow: some View {
        if let creator = rec.creators {
            HStack(spacing: RexSpacing.xs) {
                Text(creator.emoji ?? "\u{1F3A4}")
                Text(creator.name).font(RexFont.text(12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, RexSpacing.sm)
            .padding(.vertical, 3)
            .background(Color(hex: creator.color.replacingOccurrences(of: "#", with: "")))
            .clipShape(Capsule())
        } else if let author = rec.profiles {
            HStack(spacing: RexSpacing.sm) {
                UserAvatarView(
                    url: author.avatar_url,
                    name: author.display_name ?? author.username,
                    size: 24
                )
                Text(author.display_name ?? author.username)
                    .font(RexFont.text(13, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(1)
            }
        } else {
            Text("Someone")
                .font(RexFont.text(13, weight: .medium))
                .foregroundStyle(RexColor.foreground)
        }
    }
}
