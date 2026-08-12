import SwiftUI

struct RecommendationCardView: View {
    let rec: FeedRecommendation
    /// Total people who've Rex'd this item, including the author.
    var rexCount: Int = 0
    /// Already on your list — you want to go/read/watch it.
    var isOnMyList: Bool = false

    @State private var noteExpanded = false

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
                            // Second tag: what kind of place/book/etc it is,
                            // e.g. PLACE · Restaurant.
                            if let genre = splitGenres(item.genre).first {
                                Text(genre)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(RexColor.mutedForeground)
                                    .padding(.horizontal, RexSpacing.sm)
                                    .padding(.vertical, 3)
                                    .background(RexColor.muted)
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                            }
                            Spacer(minLength: RexSpacing.sm)
                            // A want has no rating — say what it is instead of
                            // showing an empty space where the crown goes.
                            if rec.isWant {
                                HStack(spacing: 4) {
                                    Image(systemName: "bookmark")
                                        .font(.system(size: 10))
                                    Text("Wants to try")
                                        .font(RexFont.text(12, weight: .semibold))
                                }
                                .foregroundStyle(RexColor.mutedForeground)
                            }
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\u{201C}\(note)\u{201D}")
                                    .font(RexFont.text(14))
                                    .foregroundStyle(RexColor.foreground.opacity(0.88))
                                    .lineLimit(noteExpanded ? nil : 3)
                                    .fixedSize(horizontal: false, vertical: true)
                                // Only offer to expand when there's more to see.
                                if !noteExpanded, note.count > 140 {
                                    Text("Read more")
                                        .font(RexFont.text(12, weight: .semibold))
                                        .foregroundStyle(RexColor.primary)
                                }
                            }
                            .padding(.top, RexSpacing.xs)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if note.count > 140 {
                                    withAnimation(.snappy) { noteExpanded.toggle() }
                                }
                            }
                        }

                        rexdByRow

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

                if let photos = rec.photo_urls, !photos.isEmpty {
                    PhotoCarouselView(urls: photos, height: 200, cornerRadius: 0)
                        .padding(.bottom, RexSpacing.sm)
                }

                Rectangle()
                    .fill(RexColor.divider)
                    .frame(height: 1)

                HStack(spacing: RexSpacing.sm) {
                    authorRow
                    Spacer(minLength: RexSpacing.sm)
                    // Likes and comments key off a recommendation id, which a
                    // want doesn't have — so those actions stay off until wants
                    // and Rex share a table.
                    if !rec.isWant {
                        RexCardActions(rec: rec)
                    }
                }
                .padding(.horizontal, RexSpacing.cardPadding)
                .padding(.vertical, RexSpacing.md)
            }
            .rexCard()
        )
    }

    /// Social proof and your own state with this item, both of which are the
    /// point of REX and were previously buried.
    @ViewBuilder
    private var rexdByRow: some View {
        let others = max(0, rexCount - 1)
        if others > 0 || isOnMyList {
            HStack(spacing: RexSpacing.sm) {
                if others > 0 {
                    HStack(spacing: 4) {
                        // Three or more people is worth calling hot.
                        Image(systemName: others >= 3 ? "flame.fill" : "person.2.fill")
                            .font(.system(size: 10))
                        Text(others >= 3
                             ? "Hot — \(others + 1) friends Rex'd this"
                             : "Also Rex'd by \(others) \(others == 1 ? "friend" : "friends")")
                            .font(RexFont.text(12, weight: .semibold))
                    }
                    .foregroundStyle(others >= 3 ? RexColor.accent : RexColor.primary)
                    .padding(.horizontal, RexSpacing.sm)
                    .padding(.vertical, 4)
                    .background(others >= 3 ? RexColor.accent.opacity(0.1) : RexColor.badgeBackground)
                    .clipShape(Capsule())
                }

                if isOnMyList {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill").font(.system(size: 9))
                        Text("On your list").font(RexFont.text(11, weight: .medium))
                    }
                    .foregroundStyle(RexColor.mutedForeground)
                }
            }
            .padding(.top, RexSpacing.xs)
        }
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
        } else if rec.is_anonymous == true, rec.user_id != RexAPI.shared.currentUserId {
            // Posted anonymously — no name, no link to the profile. It still
            // counts toward their tally, we just don't say whose it is.
            HStack(spacing: RexSpacing.sm) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 12))
                    .foregroundStyle(RexColor.mutedForeground)
                    .frame(width: 24, height: 24)
                    .background(RexColor.muted)
                    .clipShape(Circle())
                Text("Anonymous")
                    .font(RexFont.text(13, weight: .medium))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        } else if let author = rec.profiles {
            // Tapping the author opens their profile.
            NavigationLink(value: UserProfileRoute(
                userId: rec.user_id,
                name: author.display_name ?? author.username
            )) {
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
            }
            .buttonStyle(.plain)
        } else {
            Text("Someone")
                .font(RexFont.text(13, weight: .medium))
                .foregroundStyle(RexColor.foreground)
        }
    }
}
