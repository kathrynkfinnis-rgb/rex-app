import SwiftUI

struct RecommendationCardView: View {
    let rec: FeedRecommendation
    /// Total people who've Rex'd this item, including the author.
    var rexCount: Int = 0
    /// Already on your list — you want to go/read/watch it.
    var isOnMyList: Bool = false
    /// Opening the author's profile. The card is one tap target now (so it can
    /// swipe), so the author row can't be its own NavigationLink — the parent
    /// swallowed it. The feed hands the push back in through here.
    var onAuthorTap: ((String, String) -> Void)? = nil
    /// Tapping a book's author (in the subtitle) opens everyone's other Rex'd
    /// books by them. Same nested-tap-gesture trick as onAuthorTap, and the
    /// same reason it has to be handed back up rather than pushed here.
    var onBookAuthorTap: ((String) -> Void)? = nil
    /// #130 — the comment icon used to rely on allowsHitTesting(false) to
    /// let its tap fall through to the card's own onTap, which turned out
    /// not to reliably happen on a card this gesture-laden (same class of
    /// issue as #120's swipe conflict). Same explicit hand-back-up pattern
    /// as onAuthorTap/onBookAuthorTap instead of relying on pass-through.
    var onCommentTap: (() -> Void)? = nil
    /// #133 — jumps to this item's pin on the map. Only meaningful for
    /// place/event categories (anything else has no coordinates at all), so
    /// the locality row below only becomes tappable when both this is
    /// provided and the category actually has one.
    var onViewOnMap: ((String) -> Void)? = nil
    /// Sept 10 — "when you click on the map in a trip card in the feed, it
    /// should take you to a filtered view of the map with just the pins for
    /// that trip". Trip recommendation id and title.
    var onViewTripOnMap: ((String, String) -> Void)? = nil

    @State private var noteExpanded = false

    private var category: RexCategory { RexCategory(rawType: rec.items?.type) }

    /// How much trailing space the title needs to clear for whatever sits
    /// in the top-right corner — the status label or rating, and the "…"
    /// button on your own cards (EditableIfMine, applied outside this view).
    ///
    /// Sept 10 — the new card design puts "Wants to try" back in that
    /// corner, as its only appearance on the card (the copy in the tags row
    /// is gone). Reserving width for it is what keeps a long title wrapping
    /// short of the label instead of running underneath it, which is what
    /// the 9 Sept screenshots were showing.
    private var titleTrailingReserve: CGFloat {
        var needed: CGFloat = 0
        if rec.isWant { needed = 104 }
        else if rec.isBlast { needed = 72 }
        else if rec.rating > 0 { needed = 30 }
        if rec.user_id == RexAPI.shared.currentUserId { needed += 36 }
        return needed
    }

    /// The rail down the left edge, and the hairline round the rest: the
    /// category's own colour, softened to a pastel so it frames the card
    /// rather than competing with the photo inside it.
    private var railColor: Color { category.tintColor.opacity(0.38) }
    private static let railWidth: CGFloat = 10

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var relativeTime: String {
        guard let date = rec.createdDate else { return "" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        guard let item = rec.items else { return AnyView(EmptyView()) }
        return AnyView(
            // Sept 10 — "can we try this version of the visuals for the
            // feed". From Kathryn's mock-up: a pastel rail in the category's
            // colour down the left edge, a hairline in the same colour round
            // the rest, and a white card sitting inside it. Everything about
            // the item — title, what it is, where, why — stays in one column
            // beside the thumbnail; the map (or photos) run the full width
            // beneath; the author and actions close it off.
            //
            // Replaces option D (a top cap and a tinted wash behind the
            // title block). The colour now lives only at the edges, so the
            // text and photos sit on plain white.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: RexSpacing.md) {
                    thumbnail(item: item)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(RexFont.display(17, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                            // Sept 5 — "the titles on the feed should be full
                            // unless it goes over 3 lines".
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .padding(.trailing, titleTrailingReserve)

                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            if category == .book, let onBookAuthorTap {
                                bookSubtitleRow(subtitle, onTap: onBookAuthorTap)
                            } else {
                                Text(subtitle)
                                    .font(RexFont.text(13))
                                    .foregroundStyle(RexColor.mutedForeground)
                                    .lineLimit(1)
                            }
                        }

                        // What it is: the category, then up to three
                        // sub-categories. The status ("Wants to try",
                        // "Asking") is no longer in here — it's in the corner.
                        tagRow(item: item)

                        // Where it is.
                        if let locality = shortLocality(item.address) {
                            let canViewOnMap = onViewOnMap != nil && (category == .place || category == .event)
                            HStack(spacing: 3) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 9))
                                Text(locality)
                                    .font(RexFont.text(12.5, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(RexColor.mutedForeground)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if canViewOnMap { onViewOnMap?(rec.item_id) }
                            }
                            // Sept 15 — "Can't click through to the details in
                            // this section, the whole tile should bring me
                            // through" (Danny). This row and the note below
                            // each had a tap of their own, which swallowed the
                            // card's tap even when they had nothing to do. They
                            // only take the tap now when there's something for
                            // it to do; otherwise it falls through to the card.
                            .allowsHitTesting(canViewOnMap)
                        }

                        // Why.
                        if let note = rec.note, !note.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(linkified("\u{201C}\(note)\u{201D}"))
                                    .font(RexFont.text(14))
                                    .foregroundStyle(RexColor.foreground.opacity(0.88))
                                    .tint(RexColor.primary)
                                    .lineLimit(noteExpanded ? nil : 3)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !noteExpanded, note.count > 140 {
                                    Text("Read more")
                                        .font(RexFont.text(12, weight: .semibold))
                                        .foregroundStyle(RexColor.primary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if note.count > 140 {
                                    withAnimation(.snappy) { noteExpanded.toggle() }
                                }
                            }
                            // Long enough to expand, or carrying a link to tap.
                            .allowsHitTesting(note.count > 140 || note.contains("http") || note.contains("www."))
                        }

                        TaggedFriendsRow(friends: rec.taggedFriends)

                        rexdByRow

                        if let tags = rec.tags, !tags.isEmpty {
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
                        }
                    }
                }
                // Widened before the overlay so the corner label is measured
                // against the card's real right edge — see the 6 Sept
                // "floating in the middle" fix.
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topTrailing) {
                    cornerLabel
                        // Clear of the "…" button EditableIfMine floats in
                        // the same corner on your own cards.
                        .padding(.trailing, rec.user_id == RexAPI.shared.currentUserId ? 34 : 0)
                        .padding(.top, 3)
                }
                .padding(.horizontal, RexSpacing.cardPadding)
                .padding(.top, RexSpacing.cardPadding)
                .padding(.bottom, RexSpacing.md)

                media(item: item)

                if !hasMedia(item: item) {
                    Rectangle()
                        .fill(RexColor.divider)
                        .frame(height: 1)
                        .padding(.leading, RexSpacing.cardPadding)
                }

                HStack(spacing: RexSpacing.sm) {
                    authorRow
                    Spacer(minLength: RexSpacing.sm)
                    // Blasts are questions, not Rex — no like/save row.
                    if !rec.isBlast {
                        RexCardActions(rec: rec, rexCount: rexCount, onCommentTap: onCommentTap)
                    }
                }
                .padding(.horizontal, RexSpacing.cardPadding)
                .padding(.vertical, RexSpacing.md)
            }
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            .padding(.leading, Self.railWidth)
            .background(
                RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                    .fill(RexColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                            .fill(railColor)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                    .stroke(railColor, lineWidth: 1.5)
            )
            // Every card the same width, whatever's inside — see the 5 Sept
            // trip-card fix.
            .frame(maxWidth: .infinity)
        )
    }

    /// Top-right corner: what state this Rex is in. "Wants to try" and
    /// "Asking" say it in words — they're the one place on the card that
    /// does — and a rating says it with its emoji.
    @ViewBuilder
    private var cornerLabel: some View {
        if rec.isWant {
            HStack(spacing: 5) {
                Image(systemName: "bookmark").font(.system(size: 12))
                Text("Wants to try").font(RexFont.text(12.5, weight: .semibold))
            }
            .foregroundStyle(RexColor.mutedForeground)
        } else if rec.isBlast {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 11))
                Text("Asking").font(RexFont.text(12.5, weight: .semibold))
            }
            .foregroundStyle(RexColor.accent)
        } else if rec.rating > 0 {
            RexRatingBadge(raw: rec.rating, compact: true)
        }
    }

    private func tagRow(item: RexItem) -> some View {
        HStack(spacing: RexSpacing.xs) {
            categoryBadge
            ForEach(splitGenres(item.genre).prefix(3), id: \.self) { genre in
                Text(genre)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.horizontal, RexSpacing.sm)
                    .padding(.vertical, 3)
                    .background(RexColor.muted)
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
        }
    }

    private func hasMedia(item: RexItem) -> Bool {
        if let photos = rec.photo_urls, !photos.isEmpty { return true }
        if category == .trip { return true }
        if category == .place || category == .event, item.lat != nil, item.lng != nil { return true }
        return false
    }

    /// Full-width, edge to edge inside the card: your photos if there are
    /// any, else a trip's map of its stops, else a place's own map strip.
    @ViewBuilder
    private func media(item: RexItem) -> some View {
        if let photos = rec.photo_urls, !photos.isEmpty {
            PhotoCarouselView(urls: photos, cornerRadius: 0)
                // #120: a swipe started on the photo pages the photos
                // rather than triggering the card's swipe-to-remove.
                .swipeToRemoveExclusionZone()
        } else if category == .trip {
            TripMapTileView(tripRecommendationId: rec.id, tripName: item.title, height: 170)
                .swipeToRemoveExclusionZone()
                .contentShape(Rectangle())
                .onTapGesture {
                    onViewTripOnMap?(rec.id, item.title)
                }
                .accessibilityAddTraits(onViewTripOnMap != nil ? .isButton : [])
                .accessibilityLabel("Map of this trip's stops")
        } else if category == .place || category == .event, let lat = item.lat, let lng = item.lng {
            // A strip rather than a tile — the mock-up's proportions. The
            // thumbnail above already shows what the place looks like; this
            // only has to say where.
            PlaceMapTileView(lat: lat, lng: lng, height: 96)
                .swipeToRemoveExclusionZone()
                .contentShape(Rectangle())
                .onTapGesture {
                    onViewOnMap?(rec.item_id)
                }
        }
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

    /// A book's subtitle is "Author Name · 2022" (see RexSearch's
    /// OpenLibrary import) — only the author part should read as tappable,
    /// not the publication year tacked on after it, so this splits on the
    /// " · " separator rather than making the whole string one tap target.
    private func bookSubtitleRow(_ subtitle: String, onTap: @escaping (String) -> Void) -> some View {
        let parts = subtitle.components(separatedBy: " · ")
        let author = parts.first ?? subtitle
        let rest = parts.count > 1 ? " · " + parts.dropFirst().joined(separator: " · ") : ""
        return HStack(spacing: 0) {
            Text(author)
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.primary)
                .underline()
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture { onTap(author) }
            if !rest.isEmpty {
                Text(rest)
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(1)
            }
        }
    }

    private var categoryBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbol).font(.system(size: 9))
            Text(category.label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
        }
        // Sept 7 — "please can we also colour the tag for the category".
        // The badge names the category, so it wearing the category's own
        // colour is the one place on the card where the colour is doing
        // something literal rather than decorative. Kept as tinted-on-tint
        // rather than solid: the card's top block is already washed in this
        // colour, and a solid capsule on top of that shouts.
        .foregroundStyle(category.tintColor)
        .padding(.horizontal, RexSpacing.sm)
        .padding(.vertical, 3)
        .background(category.tintColor.opacity(0.15))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func thumbnail(item: RexItem) -> some View {
        Group {
            if let urlString = item.image_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else if phase.error != nil {
                        // Sept 7 — "thumbnails aren't loading well on the
                        // feed". A dead or slow image URL left a plain grey
                        // square; the category's own illustration is a much
                        // better answer than a blank tile, and it's what a
                        // Rex with no image at all already shows.
                        Image(category.placeholderImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .background(RexColor.muted)
                    } else {
                        RexColor.muted.overlay(ProgressView().controlSize(.mini))
                    }
                }
                // Places added before the URL fix never render — whichever
                // card sees it first repairs it for everyone, since items
                // aren't per-user.
                .task { await RexAPI.shared.repairPlacePhotoIfNeeded(itemId: item.id, imageURL: urlString) }
            } else {
                // Kathryn's illustrated mascot, one per category, rather
                // than a plain tinted SF Symbol tile.
                Image(category.placeholderImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .background(RexColor.muted)
                // #141 — backfill a thumbnail for pre-v10 Rex that predate
                // any category having automatic photo lookup.
                .task {
                    await RexAPI.shared.repairMissingThumbnailIfNeeded(
                        itemId: item.id, type: item.type, title: item.title, subtitle: item.subtitle
                    )
                }
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
            // Tapping the author opens their profile. A nested tap gesture wins
            // over the card's, which a NavigationLink here did not.
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
                    // Tighter icon row (see RexCardActions) frees up the
                    // width; this makes sure the name actually gets to keep
                    // it instead of the Spacer eating the gain.
                    .layoutPriority(1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onAuthorTap?(rec.user_id, author.display_name ?? author.username)
            }
        } else {
            Text("Someone")
                .font(RexFont.text(13, weight: .medium))
                .foregroundStyle(RexColor.foreground)
        }
    }
}
