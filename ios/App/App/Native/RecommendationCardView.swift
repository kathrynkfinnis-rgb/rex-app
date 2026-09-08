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

    @State private var noteExpanded = false

    private var category: RexCategory { RexCategory(rawType: rec.items?.type) }

    /// How much trailing space the title's own line needs to clear, to
    /// leave room for whichever badge is floating in the same top corner —
    /// see the .overlay(alignment: .topTrailing) below. "Asking"/"Wants to
    /// try" carry a text label and need real room; a rating is just one
    /// small emoji; a plain Rex with none of the three needs nothing.
    private var titleTrailingReserve: CGFloat {
        // Sept 7 — was 110 when these carried a text label; they're a bare
        // icon now, so the title gets that width back.
        if rec.isBlast || rec.isWant { return 34 }
        if rec.rating > 0 { return 40 }
        return 0
    }

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
            // Sept 7 — the category's colour, take three. It was a 5px left
            // rail (too easy to miss), then a full border (option B), and now
            // option D: a 3px cap along the top plus a wash behind the title
            // block, with everything below the divider left white. Seeing all
            // five as full feeds is what settled it — D is the one you can
            // read without looking directly at it.
            Group {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(category.tintColor)
                        .frame(height: 3)

                    // Sept 8 — "for maps, move pin (location) up and then
                    // tags, spanning across the whole card, then the text
                    // review". Beside a thumbnail the text column is barely
                    // half the card, and the category badge plus two or
                    // three sub-category chips never fitted on one line
                    // there — they wrapped or dropped. Only the title, the
                    // subtitle and the location need to sit next to the
                    // thumbnail; everything wider than that now runs the
                    // full width underneath it, which is also the order the
                    // card reads best in: what it is, where it is, then why
                    // it's worth going.
                    VStack(alignment: .leading, spacing: RexSpacing.xs) {
                        HStack(alignment: .top, spacing: RexSpacing.md) {
                            thumbnail(item: item)
                            VStack(alignment: .leading, spacing: RexSpacing.xs) {
                                Text(item.title)
                                    .font(RexFont.display(17, weight: .semibold))
                                    .foregroundStyle(RexColor.foreground)
                                    // Sept 5 — "the titles on the feed should be
                                    // full unless it goes over 3 lines, in which
                                    // case can '...' them". Was a hard one line,
                                    // which truncated plenty of ordinary titles
                                    // ("Cumin roasted carrots,…") that had room
                                    // to breathe.
                                    .lineLimit(3)
                                    .truncationMode(.tail)
                                    // Room for the floating blast/want/rating badge
                                    // sharing this same corner now that it's an
                                    // overlay rather than its own row above — sized
                                    // to whichever of those is actually showing, so
                                    // a plain rated Rex (just a small emoji) doesn't
                                    // lose title width it doesn't need to.
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
                                // Sept 8 — the location moved back above the
                                // tags. It went under them in the first place
                                // because both lived in this narrow column and
                                // the tags read as part of the title; now that
                                // the tags run full-width below, the column is
                                // just "what it is and where it is", which is
                                // the pair that belongs beside the thumbnail.
                                if let locality = shortLocality(item.address) {
                                    let canViewOnMap = onViewOnMap != nil && (category == .place || category == .event)
                                    HStack(spacing: 3) {
                                        Image(systemName: "mappin")
                                            .font(.system(size: 9))
                                        Text(locality)
                                            .font(RexFont.text(12, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(RexColor.mutedForeground)
                                    .padding(.top, 2)
                                    // "Don't need pin and map icon — just keep the
                                    // pin, make the whole location clickable." No
                                    // second icon any more; the tap target is the
                                    // whole row instead of a dedicated glyph.
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if canViewOnMap { onViewOnMap?(rec.item_id) }
                                    }
                                }
                            }
                        }
                        // Has to come BEFORE the .overlay below, not after: overlay
                        // aligns to whatever size its content already reports at
                        // the point it's attached, so a frame stretch applied
                        // afterwards would just leave the whole (HStack+overlay)
                        // pair sitting left-aligned in extra empty space, rather
                        // than actually moving the overlay itself rightward — which
                        // is exactly the "floating in the middle" bug this line
                        // fixes. Widening the HStack FIRST means the overlay's own
                        // topTrailing is computed against the true full-width edge.
                        //
                        // Also fixes "make sure the title is top-aligned to the
                        // card": the blast/want/rating badge used to sit inline
                        // above the title as its own row, which meant the title —
                        // not that row — was what needed to line up with the
                        // thumbnail's top edge, and didn't. Floating it instead
                        // frees the title to be the text column's first, top-
                        // aligned element.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .topTrailing) {
                            HStack(spacing: 4) {
                                // A blast is a question, not a verdict.
                                if rec.isBlast {
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 10))
                                        Text("Asking")
                                            .font(RexFont.text(12, weight: .semibold))
                                    }
                                    .foregroundStyle(RexColor.accent)
                                }
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
                                // Rating is an "important element" — one of the few
                                // places the spec allows forest green. Emoji only
                                // here: there's no room for a full label ("Do not
                                // Rex") this close to the floating edit-pencil in
                                // the same corner. The word appears on the detail
                                // screen instead, where there's room for it.
                                if rec.rating > 0 {
                                    RexRatingBadge(raw: rec.rating, compact: true)
                                }
                            }
                            // Your own cards get an edit-pencil floating in this
                            // exact corner too (EditableIfMine, applied outside this
                            // view) — clearance so the two don't overlap. No extra
                            // top/trailing inset needed beyond that: the HStack
                            // this overlay hangs off gets the same .padding(
                            // cardPadding) as everything else below, which already
                            // insets the whole thing (overlay included) from the
                            // card's edges.
                            .padding(.trailing, 26)
                        }

                        // "Move the category tag under the name as well, next
                        // to the sub category tags (to the left though so
                        // category comes first)" — categoryBadge used to live
                        // in the header row up top; it moved down here, first
                        // in line, ahead of the genre/subcategory tags that
                        // already relocated here for the same "under the
                        // title" reason (#136 → reference design).
                        HStack(spacing: RexSpacing.xs) {
                            // Sept 7 — "want to try headings are still not
                            // looking perfect... perhaps just the bookmark
                            // at the top, and a 'wants to try' text
                            // somewhere else". The words moved down here
                            // beside the category, where the card already
                            // keeps its other labels; the corner keeps
                            // just the icon. Same for a blast's "Asking".
                            if rec.isWant { statusPill("Wants to try", icon: "bookmark") }
                            if rec.isBlast { statusPill("Asking", icon: "sparkles", tint: RexColor.accent) }
                            categoryBadge
                            ForEach(splitGenres(item.genre).prefix(3), id: \.self) { genre in
                                Text(genre)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(RexColor.mutedForeground)
                                    .padding(.horizontal, RexSpacing.sm)
                                    .padding(.vertical, 3)
                                    .background(RexColor.muted)
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                            }
                        }
                        .padding(.top, 2)

                        if let note = rec.note, !note.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                // Links people paste into a note become
                                // tappable rather than dead text.
                                Text(linkified("\u{201C}\(note)\u{201D}"))
                                    .font(RexFont.text(14))
                                    .foregroundStyle(RexColor.foreground.opacity(0.88))
                                    .tint(RexColor.primary)
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

                        TaggedFriendsRow(friends: rec.taggedFriends)
                            .padding(.top, RexSpacing.xs)

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
                    .padding(RexSpacing.cardPadding)
                    // The wash sits behind the title, badges and note only.
                    // Photos, the map tile and the author row all stay on
                    // plain white — a tinted strip behind a photo just looks
                    // like a rendering mistake.
                    .background(category.tintColor.opacity(0.11))

                    if let photos = rec.photo_urls, !photos.isEmpty {
                        PhotoCarouselView(urls: photos, cornerRadius: 0)
                            .padding(.bottom, RexSpacing.sm)
                            // #120: without this, a swipe started on the photo
                            // itself was captured by the enclosing
                            // SwipeToRemove (when this card is your own, in the
                            // feed) as a delete-swipe instead of paging photos.
                            .swipeToRemoveExclusionZone()
                    } else if category == .trip {
                        // A trip has no photos of its own — its stops do — so in
                        // that empty-carousel slot show where the trip actually
                        // goes instead. rec.id is the trip's own recommendation
                        // row, which is exactly what every stop's trip_id points
                        // back to.
                        TripMapTileView(tripRecommendationId: rec.id, tripName: item.title)
                            .padding(.bottom, RexSpacing.sm)
                            .swipeToRemoveExclusionZone()
                    } else if category == .place || category == .event,
                              let lat = item.lat, let lng = item.lng {
                        // Sept 5 — "a small map thumbnail on a place's card".
                        // Same slot, same reasoning as the trip tile above:
                        // only when there's no photo, because someone's own
                        // picture of the place beats a map of it.
                        PlaceMapTileView(lat: lat, lng: lng)
                            .padding(.bottom, RexSpacing.sm)
                            .swipeToRemoveExclusionZone()
                    }

                    Rectangle()
                        .fill(RexColor.divider)
                        .frame(height: 1)

                    HStack(spacing: RexSpacing.sm) {
                        authorRow
                        Spacer(minLength: RexSpacing.sm)
                        // "You should still have all the icons in the bottom
                        // right of the card" for a want, same as any other
                        // Rex — RexCardActions itself hides just the two
                        // (like/comment) that have no real row to attach to
                        // for a want, per Kathryn's call, and keeps
                        // dino-count + bookmark working since those key off
                        // the item rather than a recommendation row. Blasts
                        // are a genuinely different, questions-not-Rex
                        // shape, so they're still excluded outright.
                        if !rec.isBlast {
                            RexCardActions(rec: rec, rexCount: rexCount, onCommentTap: onCommentTap)
                        }
                    }
                    .padding(.horizontal, RexSpacing.cardPadding)
                    .padding(.vertical, RexSpacing.md)
                }
            }
            // Sept 5 — "make the trips card the same width as all the
            // other cards in the feed". A card sized to its own content,
            // and a trip's map tile is greedy where a plain card's text
            // isn't, so trips came out wider than their neighbours. Pinning
            // the width here makes every card identical regardless.
            .frame(maxWidth: .infinity)
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

    /// "Wants to try" / "Asking", sitting with the category chip rather
    /// than crowding the title.
    private func statusPill(_ label: String, icon: String, tint: Color = RexColor.mutedForeground) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, RexSpacing.sm)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
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
