import SwiftUI

struct RecommendationCardView: View {
    let rec: FeedRecommendation
    /// Total people who've Rex'd this item, including the author.
    var rexCount: Int = 0
    /// Already on your list — you want to go/read/watch it.
    var isOnMyList: Bool = false
    /// Oct 7 — everyone who wants to try this, oldest first. Only drawn on a
    /// want card, where "how many other people fancy this" is the whole point.
    var wanters: [RexProfileDetail] = []
    @State private var chipsContentWidth: CGFloat = 0
    @State private var chipsRowWidth: CGFloat = 0
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
    /// Nov 22 — "been?" on a want card. Only wired on screens that own an
    /// edit sheet; elsewhere the button is simply not drawn rather than
    /// drawn and dead.
    var onMarkBeen: (() -> Void)? = nil
    /// #133 — jumps to this item's pin on the map. Only meaningful for
    /// place/event categories (anything else has no coordinates at all), so
    /// the locality row below only becomes tappable when both this is
    /// provided and the category actually has one.
    var onViewOnMap: ((String) -> Void)? = nil
    /// Sept 10 — "when you click on the map in a trip card in the feed, it
    /// should take you to a filtered view of the map with just the pins for
    /// that trip". Trip recommendation id and title.
    var onViewTripOnMap: ((String, String) -> Void)? = nil
    /// Oct 14 — "users should be able to show Lists as full titles if it's
    /// more of a 'to do' list format rather than a list of Rexes." Set by the
    /// list page when its author has said so; off everywhere else, where the
    /// three-line cut is what keeps a column of cards readable.
    var showsFullTitle: Bool = false

    @State private var noteExpanded = false
    /// Nov 22 — who else has Rex'd this. Opened from the "Also Rex'd by N
    /// friends" chip now that the action row's dino has gone.
    @State private var showingRexers = false
    /// How tall the note wants to be, and how tall it is allowed to be — the
    /// difference is whether it has been cut off. See noteIsClipped.
    @State private var fullNoteHeight: CGFloat = 0
    @State private var shownNoteHeight: CGFloat = 0

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
    /// A couple of points of slack, so a rounding difference between the two
    /// measurements doesn't put "Read more" under a note that isn't clipped.
    private var noteIsClipped: Bool {
        fullNoteHeight > shownNoteHeight + 2
    }

    private var titleTrailingReserve: CGFloat {
        // Sept 29 — "the title should run to the end of the card".
        //
        // This reserved 104pt on a want-to-try and 72pt on a blast for
        // corner labels that haven't been there since 21 Sept, when "Wants
        // to try" moved down into the status row. cornerLabel draws nothing
        // in either case now, so the title was wrapping early to make room
        // for empty space — "Mackerel Sky Seafood Bar" taking two lines in
        // a card with a third of its width spare.
        //
        // Reserve what's actually in the corner, and nothing else.
        //
        // Oct 1 — "can we get the 100 to go under the …, and keep the title
        // going across one line to the … as far as possible". They used to
        // sit side by side, so a card of your own reserved 66pt and pushed
        // every title into an early wrap. Stacked, the corner is only ever as
        // wide as the wider of the two.
        // Nov 22 — the rating is no longer in this corner; it rides on the
        // thumbnail, which now ends the row and takes its own width out of
        // the text column. So nothing has to be reserved for it. What is
        // still up there is the "…" on your own cards, and only on those.
        let isMine = rec.user_id == RexAPI.shared.currentUserId
        return isMine ? 36 : 0
    }

    /// The rail down the left edge, and the hairline round the rest: the
    /// category's own colour, softened to a pastel so it frames the card
    /// rather than competing with the photo inside it.
    private var railColor: Color { category.tintColor.opacity(0.38) }
    private static let railWidth: CGFloat = 10

    /// Sept 22 — the feed never showed when anything was posted. Written to
    /// the Instagram rule Kathryn picked: relative while relative still means
    /// something, then a plain date once nobody counts in that unit any more.
    /// "4h" tells you something; "36w ago" makes you do arithmetic.
    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static let dayMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f
    }()

    private var relativeTime: String {
        guard let date = rec.createdDate else { return "" }
        let seconds = Date().timeIntervalSince(date)
        // A clock skew between phone and server shouldn't read "in 2 minutes".
        guard seconds > 0 else { return "now" }
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3_600))h ago"
        case ..<604_800: return "\(Int(seconds / 86_400))d ago"
        default:
            let calendar = Calendar.current
            let sameYear = calendar.component(.year, from: date)
                == calendar.component(.year, from: Date())
            return sameYear
                ? Self.dayMonth.string(from: date)
                : Self.dayMonthYear.string(from: date)
        }
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
                categoryBar

                // Nov 22 — "put thumbnails on the right instead of the left
                // so you have a nice clean line down the left hand side and
                // the thumbnail sits in the natural white space on the
                // right."
                //
                // The text column leads now and the thumbnail closes the row.
                // Every title, subtitle, tag row and locality starts on the
                // same vertical line, which is the point: the eye runs down
                // one edge instead of stepping around a 60pt square.
                //
                // The rating moves with it. cornerLabel used to float at the
                // card's top-trailing corner, which is exactly where the
                // thumbnail now sits — see the overlay below, which hangs the
                // badge off the image instead of colliding with it.
                // One column for the whole card body, so the header row and
                // everything under it share the same left edge and the same
                // padding. They were briefly two siblings with the padding on
                // only one of them, which indented the note 16pt past the
                // title.
                VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: RexSpacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Nov 22 — "make sure the text runs through the top
                        // of the card": the title should use the whole width
                        // before it wraps.
                        //
                        // It was wrapping with room to spare. "TYCOZ -
                        // CRÊPERIE & OYSTER BAR" broke after the ampersand
                        // and left the rest of the line empty, because
                        // Archivo Black is wide and the title came to within
                        // a few points of the card — close enough that
                        // SwiftUI took the second line rather than the last
                        // word. It only looked right on build 107, where the
                        // card was wider than the screen.
                        //
                        // ViewThatFits asks for the single line first and
                        // falls back to the wrapping version only when it
                        // genuinely does not fit, so a marginal title gets
                        // its line and a long one still wraps to three.
                        // Three tries, in order. A single line at full size;
                        // a single line one step down, for the titles that
                        // miss by a few points — this one wants about 323pt
                        // and the card has 310, so it was taking a whole
                        // second line to carry "OYSTER BAR"; and only then
                        // the wrapping version, for titles that are genuinely
                        // long. ViewThatFits takes the first that fits, and
                        // each of the first two demands its natural width, so
                        // neither can be chosen unless it really does fit.
                        ViewThatFits(in: .horizontal) {
                            titleText(item, size: 17)
                                .lineLimit(1)
                                .fixedSize()
                            titleText(item, size: 15)
                                .lineLimit(1)
                                .fixedSize()
                            titleText(item, size: 17)
                                .lineLimit(showsFullTitle ? nil : 3)
                                .fixedSize(horizontal: false, vertical: showsFullTitle)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, titleTrailingReserve)

                        // Nov 22 — "crêperie and paris should be next to
                        // each other." They were two stacked rows, each
                        // holding a few words and a whole line of card.
                        //
                        // A subtitle that only repeats the title is not a
                        // subtitle, either: "Minnie-Mae Studio / Minnie-Mae
                        // Studio" and "Instinct / Instinct" are both live on
                        // the feed, from items whose two fields were filled
                        // from the same string. Compared loosely, since the
                        // title is set in caps and the year comes out of the
                        // subtitle, so the two rarely match byte for byte
                        // even when they are the same words.
                        let subtitleLine: String? = {
                            guard let raw = item.subtitle, !raw.isEmpty,
                                  !isJustTheTitleAgain(raw, title: item.title)
                            else { return nil }
                            let stripped = withoutYear(raw)
                            return stripped.isEmpty ? nil : stripped
                        }()
                        let locality = shortLocality(item.address)

                        if category == .book, let onBookAuthorTap, let subtitleLine {
                            // Oct 8 — "the authors' names need to be
                            // truncated", again. A book's author is tappable,
                            // so it keeps a row of its own rather than
                            // sitting in a line with something that isn't.
                            bookSubtitleRow(subtitleLine, onTap: onBookAuthorTap)
                                .padding(.trailing, titleTrailingReserve)
                            if let locality { localityRow(locality) }
                        } else if subtitleLine != nil || locality != nil {
                            HStack(spacing: RexSpacing.sm) {
                                if let subtitleLine {
                                    Text(subtitleLine)
                                        .font(RexFont.text(13))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .lineLimit(1)
                                }
                                if let locality { localityRow(locality) }
                            }
                            // Oct 3 — "author line needs to be truncated so
                            // doesn't interfere with the rating."
                            .padding(.trailing, titleTrailingReserve)
                        }
                    }

                    // The thumbnail closes the header row. The rating rides
                    // on it: cornerLabel used to float at the card's
                    // top-trailing corner and that is this square now, so the
                    // badge hangs off the image's bottom edge where it reads
                    // as belonging to the thing in the picture.
                    // Nov 22 — "if pictures, no thumbnail for trips."
                    //
                    // A trip has no catalogue picture, so its thumbnail falls
                    // back to the first of its own photographs — which is now
                    // page one of the carousel directly below it. The same
                    // image twice, 60pt of it stealing width from the title
                    // ("Paris Pour Le Weeke…") to say nothing the card was
                    // not already saying much better.
                    //
                    // So no thumbnail on a trip at all. The condition in the
                    // note holds either way: a trip's media strip always
                    // carries something, its stops' photographs when there
                    // are any and a map of them when there are not, and both
                    // beat a 60pt square. Every other category keeps its
                    // thumbnail, where the picture IS catalogue art — a
                    // jacket, a poster — and is not repeated below.
                    //
                    // No rating badge on it any more either; that has moved
                    // up to the author's line. What still floats in this
                    // corner is the "…" on your own Rex, put there from
                    // outside by EditableIfMine.
                    if showsThumbnail {
                        thumbnail(item: item)
                    }
                }

                // Nov 22 — "text should run all the way along to the end of
                // the tab."
                //
                // The note used to sit in the same column as the title, so it
                // wrapped at the thumbnail's edge and left a 60pt channel of
                // white down the right of every line — even though the
                // thumbnail is only 60pt tall and had stopped three lines
                // earlier. The thumbnail shortens the title now, and nothing
                // else: everything below it has the whole card to run in.
                        // Why.
                        //
                        // Oct 4 — "want to be able to expand the review in the
                        // feed rather than having to open the card."
                        //
                        // It could already, but only past 140 characters — a
                        // guess at how much fills three lines. A note of 110
                        // characters on a narrow card overflows three lines
                        // just as easily, and those got the ellipsis with no
                        // "Read more" and no tap: truncated with no way to see
                        // the rest. The gate is now whether the text is
                        // actually clipped, measured rather than guessed.
                        if let note = rec.note, !note.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(linkified("\u{201C}\(note)\u{201D}"))
                                    .font(RexFont.text(14))
                                    .foregroundStyle(RexColor.foreground.opacity(0.88))
                                    .tint(RexColor.primary)
                                    .lineLimit(noteExpanded ? nil : 3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .background {
                                        // The same text, unclamped and
                                        // invisible, purely to find out how
                                        // tall it wants to be.
                                        Text(linkified("\u{201C}\(note)\u{201D}"))
                                            .font(RexFont.text(14))
                                            .fixedSize(horizontal: false, vertical: true)
                                            .background {
                                                GeometryReader { full in
                                                    Color.clear.preference(
                                                        key: NoteHeightKey.self,
                                                        value: full.size.height
                                                    )
                                                }
                                            }
                                            .hidden()
                                    }
                                    .overlay {
                                        GeometryReader { shown in
                                            Color.clear.preference(
                                                key: NoteShownHeightKey.self,
                                                value: shown.size.height
                                            )
                                        }
                                    }
                                if !noteExpanded, noteIsClipped {
                                    Text("Read more")
                                        .font(RexFont.text(12, weight: .semibold))
                                        .foregroundStyle(RexColor.primary)
                                }
                            }
                            .onPreferenceChange(NoteHeightKey.self) { fullNoteHeight = $0 }
                            .onPreferenceChange(NoteShownHeightKey.self) { shownNoteHeight = $0 }
                            // The note is what the person wrote, links and
                            // all. See rexOutboundLinks().
                            .rexOutboundLinks()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if noteIsClipped || noteExpanded {
                                    withAnimation(.snappy) { noteExpanded.toggle() }
                                }
                            }
                            // Clipped (so there's something to open), already
                            // open (so there's something to close), or
                            // carrying a link to tap.
                            .allowsHitTesting(
                                noteIsClipped || noteExpanded
                                    || note.contains("http") || note.contains("www.")
                            )
                        }

                        TaggedFriendsRow(friends: rec.taggedFriends)

                        rexdByRow

                        // Nov 22 — "remove the hashtags." The tags a
                        // poster adds are still stored and still searched on;
                        // they were just repeating words already in the note
                        // and the category, three capsules at a time.
                }
                // Widened before the overlay so the corner label is measured
                // against the card's real right edge — see the 6 Sept
                // "floating in the middle" fix.
                .frame(maxWidth: .infinity, alignment: .leading)
                // Nov 22 — the rating used to hang here. It is on the
                // thumbnail now (see above), which is what sits in this
                // corner since the row flipped. The "…" for your own Rex
                // still floats here, applied from outside by EditableIfMine.
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

                // Oct 1 — "put the icons back in one line with the name and
                // have the 'now' or '7min ago' under the name. Set a default
                // length so a really long username turns into a … to allow
                // the icons to remain where they are."
                //
                // On 29 Sept I fixed truncated names by letting the icons drop
                // to their own row, which worked but moved them about from
                // card to card. Stacking the time under the name buys back the
                // width that was the real problem, so one row holds again —
                // and a genuinely long name now truncates rather than pushing
                // anything, which keeps the icons in the same place on every
                // card.
                HStack(spacing: RexSpacing.sm) {
                    authorRow
                    Spacer(minLength: RexSpacing.sm)
                    // Blasts are questions, not Rex — no like/save row.
                    if !rec.isBlast {
                        RexCardActions(rec: rec, rexCount: rexCount, onCommentTap: onCommentTap)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)

                        // The one-tap way out of a want, after the action bar
                        // rather than inside it: those four icons are the same
                        // on every card and this is the one thing a want card
                        // has that the others do not. Only your own — a
                        // friend's want is not yours to mark done.
                        if rec.isWant, let onMarkBeen,
                           rec.user_id == RexAPI.shared.currentUserId {
                            Button(action: onMarkBeen) {
                                Text("Been? Rate it")
                                    .font(RexFont.text(12, weight: .semibold))
                                    .foregroundStyle(RexColor.primary)
                                    .padding(.horizontal, RexSpacing.md)
                                    .padding(.vertical, 8)
                                    .background(RexColor.badgeBackground)
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
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
            .sheet(isPresented: $showingRexers) {
                RexersSheetView(itemId: rec.item_id, itemTitle: item.title)
            }
        )
    }

    /// Top-right corner: the rating, and only the rating.
    ///
    /// Sept 21 — "the want to try tag still takes up all the heading — move
    /// it above the map in line with 'On your list'". A rating badge is two
    /// characters wide and leaves the title alone; "Wants to try" is eleven
    /// and was squeezing every long title into three lines. It sits with the
    /// other status chips now, where it reads as the same kind of thing.
    @ViewBuilder
    private var cornerLabel: some View {
        if !rec.isWant, !rec.isBlast, rec.rating > 0 {
            RexRatingBadge(raw: rec.rating, compact: true)
        }
    }

    /// Oct 3 — "Place shouldn't be across two lines. The tags are all
    /// jumbled."
    ///
    /// A plain HStack given more chips than fit doesn't overflow, it squeezes:
    /// SwiftUI shrinks each child until the words inside them wrap, so "PLACE"
    /// broke across two lines and the sub-category pills ended up different
    /// heights. Each chip holds its natural width now and the row scrolls
    /// instead, which is also how the map's own filter row behaves — a chip is
    /// either legible or it isn't there.
    private func tagRow(item: RexItem) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RexSpacing.xs) {
                categoryBadge
                    .fixedSize()
                // Nov 22 — "different styling of what I assume are related
                // elements, eg bar restaurant has a kind of tag icon on the
                // map but not on the feed — these indicators help a user
                // understand how objects are related across the app."
                //
                // rexSubcategorySymbol was drawn on map pins and nowhere
                // else, so the same bar was a wineglass on the map and a
                // plain word in the feed, and nothing linked the two. The
                // first chip carries the symbol here as well; the rest stay
                // text, because the symbol belongs to the leading genre the
                // way the pin's does.
                ForEach(Array(splitGenres(item.genre).prefix(3).enumerated()), id: \.element) { index, genre in
                    HStack(spacing: 3) {
                        if index == 0 {
                            Image(systemName: rexSubcategorySymbol(genre: genre, type: item.type))
                                .font(.system(size: 9))
                        }
                        Text(genre)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(RexColor.mutedForeground)
                    .fixedSize()
                    .padding(.horizontal, RexSpacing.sm)
                    .padding(.vertical, 3)
                    .background(RexColor.muted)
                    .clipShape(Capsule())
                }
            }
            // Oct 9 — "need to move one of the tags to the row below to
            // prevent this": PLACE · Restaurant · Mediterranean ran under the
            // rating badge in the corner, so the heart sat on top of the word.
            //
            // The third time this corner has caught something. The title
            // reserves room for it, the author line was given the same reserve
            // on 3 October and again on 8 October for books — and this row,
            // which sits at exactly the badge's height, never had it. Adding
            // the cuisine chip made it long enough to reach.
            //
            // Reserved rather than wrapped: these scroll already, so the
            // overflow has somewhere to go, and a second row of chips would
            // make every card taller to fix a few.
            .padding(.trailing, titleTrailingReserve)
            .background(GeometryReader { geo in
                Color.clear.preference(key: ChipsContentWidthKey.self, value: geo.size.width)
            })
        }
        .background(GeometryReader { geo in
            Color.clear.preference(key: ChipsRowWidthKey.self, value: geo.size.width)
        })
        .onPreferenceChange(ChipsContentWidthKey.self) { chipsContentWidth = $0 }
        .onPreferenceChange(ChipsRowWidthKey.self) { chipsRowWidth = $0 }
        // The chips are a label, not a control — a drag on them should still
        // swipe the card away, so scrolling stays off unless there is
        // genuinely something out of sight.
        //
        // Oct 18 — "I should be able to scroll across these buttons." This
        // used to be `genres.count <= 2`, on the assumption that two chips
        // always fit. "Mediterranean restaurant" is one chip and most of a
        // row: the screenshot shows PLACE, that, and a third cut off at the
        // edge with no way to reach it. Count was never the question —
        // width is — so it is measured now.
        .scrollDisabled(chipsContentWidth <= chipsRowWidth + 1)
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
        // Nov 22 — "user uploaded photos being the first images, then the
        // map being the last thing in the carousel."
        //
        // These used to be alternatives: photos OR a map, first branch wins.
        // So a place somebody had photographed never said where it was, and
        // the map only appeared on the cards with no pictures — exactly
        // backwards, since a card with photos is the one you want to place.
        // One carousel now, photographs first, map last.
        let photos = rec.photo_urls ?? []

        if category == .trip {
            // A trip's own row rarely carries photos; they are on its stops.
            // TripMapTileView already loads both, so it builds the carousel.
            TripMapTileView(tripRecommendationId: rec.id, tripName: item.title, height: 170,
                            ownPhotos: photos)
                .swipeToRemoveExclusionZone()
                .accessibilityLabel("This trip's photos and a map of its stops")
        } else if category == .place || category == .event, let lat = item.lat, let lng = item.lng {
            PhotoCarouselView(
                urls: photos,
                cornerRadius: 0,
                trailingPage: AnyView(
                    // A strip when it is the only thing here, matching the
                    // mock-up's proportions; inside a carousel it fills the
                    // page the photographs set.
                    PlaceMapTileView(lat: lat, lng: lng, height: photos.isEmpty ? 96 : 170)
                        .contentShape(Rectangle())
                        .onTapGesture { onViewOnMap?(rec.item_id) }
                )
            )
            // #120: a swipe started on the photo pages the photos
            // rather than triggering the card's swipe-to-remove.
            .swipeToRemoveExclusionZone()
        } else if !photos.isEmpty {
            PhotoCarouselView(urls: photos, cornerRadius: 0)
                .swipeToRemoveExclusionZone()
        }
    }

    /// Social proof and your own state with this item, both of which are the
    /// point of Rex and were previously buried.
    /// Oct 7 — "the 'want to try' and 'on your list' is still duplicative.
    /// Only need one."
    ///
    /// It was worse than duplicative, it was triplicated: a want card carried
    /// a bookmark chip saying "Wants to try", a near-identical bookmark chip
    /// saying "On your list", and the action bar underneath already showed
    /// "Saved" on the control you'd actually use to change it. "On your list"
    /// is gone — the Saved button says it, in the place you can act on it.
    ///
    /// What replaces it is the thing that was missing: how many people want
    /// this. A want card could only ever say "Wants to try" no matter whether
    /// one friend or six had saved it, because the count beside it was
    /// rexCount — people who had *been*, which on a want is usually nobody.
    @ViewBuilder
    private var rexdByRow: some View {
        let others = max(0, rexCount - 1)
        // Oct 18 — "making clear if others have also wanted to try something
        // on the feed like if there were multiple rex's."
        //
        // A want card has carried its own count for a while. A Rex card
        // carried none: somebody had been, three friends meant to go, and the
        // card mentioned only the visit. Not on a want card, where the badge
        // beside it already says this, and not counting yourself — the Saved
        // button in the action bar says that, and saying it twice is the
        // mistake the bookmark pair already made once.
        let alsoWant = rec.isWant || rec.isBlast
            ? []
            : wanters.filter { $0.id != RexAPI.shared.currentUserId }
        if others > 0 || rec.isWant || rec.isBlast || !alsoWant.isEmpty {
            HStack(spacing: RexSpacing.sm) {
                if rec.isWant {
                    wantedByBadge
                } else if rec.isBlast {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text("Asking").font(RexFont.text(11, weight: .medium))
                    }
                    .foregroundStyle(RexColor.accent)
                }

                // Kept on a want card too. "You want to try it, and two
                // friends have actually been" is a different sentence from
                // "six people want to try it" — it was the bookmark pair that
                // said the same thing twice, not this.
                if others > 0 {
                    // Nov 22 — this is the "who else Rex'd this" entry point
                    // now. The dino and its count came out of the action row
                    // ("can we remove the Rex icon to give more space to the
                    // name"), and that button was the only way in. Putting it
                    // here loses nothing and gains a lot: it says the same
                    // thing in words, it is already where the eye goes, and
                    // a capsule is a far bigger target than a 15pt glyph was.
                    Button {
                        showingRexers = true
                    } label: {
                        HStack(spacing: 4) {
                            // Three or more people is worth calling hot.
                            Image(systemName: others >= 3 ? "flame.fill" : "person.2.fill")
                                .font(.system(size: 10))
                            Text(others >= 3
                                 ? "Hot — \(others + 1) friends Rex'd this"
                                 : "Also Rex'd by \(others) \(others == 1 ? "friend" : "friends")")
                                .font(RexFont.text(12, weight: .semibold))
                        }
                        // Nov 22 — "also rex'd should be in the same blue
                        // colour as the outline." It was Rex green on a grey
                        // capsule, the one thing in the card body wearing a
                        // colour that had nothing to do with the card. The
                        // category's own tint is what draws the rail, the
                        // hairline and the bar across the top, so the chip
                        // joins them. "Hot" keeps the gold: that is a
                        // different thing being said, and it should not look
                        // like the ordinary case.
                        .foregroundStyle(others >= 3 ? RexColor.accent : category.tintColor)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 4)
                        .background(others >= 3
                                    ? RexColor.accent.opacity(0.1)
                                    : category.tintColor.opacity(0.14))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(others + 1) people have Rex'd this — see who")
                }

                if !alsoWant.isEmpty { alsoWantedBadge(alsoWant) }

                // Nov 16 — "tried to move this book to drafts and it's not
                // working. It stays on the feed and doesn't go."
                //
                // It had gone. What she did next was search for it to check,
                // and fetchFeed deliberately drops the show_in_feed filter
                // when the feed is searched or filtered — hidden means "don't
                // broadcast this", not "make this unfindable". So the card
                // came back looking exactly as it had before, and the control
                // looked broken by doing precisely what it promised.
                //
                // Saying so on the card is the missing half. Only you ever
                // see this: a hidden Rex is already out of everybody else's
                // feed, so there is nobody else to show it to.
                if rec.show_in_feed == false {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash").font(.system(size: 10))
                        Text("Hidden").font(RexFont.text(12, weight: .semibold))
                    }
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.horizontal, RexSpacing.sm)
                    .padding(.vertical, 4)
                    .background(RexColor.muted)
                    .clipShape(Capsule())
                }

                Spacer(minLength: 0)
            }
            .padding(.top, RexSpacing.xs)
        }
    }

    /// The same sentence a want card makes, in the quieter register a Rex
    /// card can spare: the Rex is the headline, the wants are context.
    @ViewBuilder
    private func alsoWantedBadge(_ people: [RexProfileDetail]) -> some View {
        HStack(spacing: RexSpacing.xs) {
            facePile(people)
            Text(people.count == 1 ? "wants to try" : "\(people.count) want to try")
                .font(RexFont.text(11, weight: .medium))
                .foregroundStyle(RexColor.mutedForeground)
        }
    }

    /// The want card's one label, carrying the count and — from three people
    /// up — the same flame a Rex card gets, because a thing six friends all
    /// mean to try is exactly as interesting as one six friends have done.
    @ViewBuilder
    private var wantedByBadge: some View {
        let count = max(wanters.count, 1)
        let hot = count >= 3

        HStack(spacing: RexSpacing.xs) {
            if !wanters.isEmpty {
                wanterFaces
            }

            HStack(spacing: 4) {
                Image(systemName: hot ? "flame.fill" : "bookmark")
                    .font(.system(size: 10))
                Text(count == 1
                     ? "Wants to try"
                     : "\(count) want to try this")
                    .font(RexFont.text(hot ? 12 : 11, weight: hot ? .semibold : .medium))
            }
            .foregroundStyle(hot ? RexColor.accent : RexColor.mutedForeground)
            .padding(.horizontal, hot ? RexSpacing.sm : 0)
            .padding(.vertical, hot ? 4 : 0)
            .background(hot ? RexColor.accent.opacity(0.1) : .clear, in: Capsule())
        }
    }

    /// Overlapping faces rather than the item page's scrolling strip: a card
    /// has one line to spare, and four faces and a number say "a few people"
    /// faster than a row you have to swipe. Tapping the card still opens the
    /// page, where the full strip lives.
    @ViewBuilder
    private var wanterFaces: some View { facePile(wanters) }

    @ViewBuilder
    private func facePile(_ people: [RexProfileDetail]) -> some View {
        let shown = Array(people.prefix(4))
        HStack(spacing: -7) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, profile in
                UserAvatarView(
                    url: profile.avatar_url,
                    name: profile.display_name ?? profile.username,
                    size: 20
                )
                .overlay(Circle().stroke(RexColor.card, lineWidth: 1.5))
                .zIndex(Double(shown.count - index))
            }
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

    /// Nov 22 — "make the bar along the top a bit thicker and put the name
    /// of the category in the bar."
    ///
    /// There was already a bar along the top: the category-coloured hairline
    /// that runs round the card, 1.5pt of it. This gives that edge a job.
    /// The category used to be a capsule in the chip row below, which is now
    /// gone, so the colour and the word arrive together at the top of the
    /// card instead of being a tint in one place and a label in another.
    private var categoryBar: some View {
        HStack(spacing: 5) {
            Image(systemName: category.symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(category.label.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.8)
            Spacer(minLength: 0)
            // The rating lives here now. It used to ride on the thumbnail's
            // bottom corner, and a card with a photograph no longer has a
            // thumbnail for it to ride on. The bar is always present, always
            // full width, and its trailing end was empty.
            cornerLabel
        }
        .foregroundStyle(category.tintColor)
        .padding(.horizontal, RexSpacing.cardPadding)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Nov 22 — "make the surround all one colour." The bar was the same
        // hue as the rail and the hairline but a weaker wash of it, so the
        // three read as two colours rather than one band round the card.
        // railColor is what draws the other two; the bar takes it as well.
        .background(railColor)
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

    /// Oct 3 — "The dino drawing is used as the thumbnail even when there's a
    /// real image."
    ///
    /// Two separate causes, both ending at the dino. The thumbnail only ever
    /// looked at `item.image_url`, so a Rex whose own photographs were sitting
    /// right there in the card's carousel still drew the mascot in the corner
    /// — the photo was on the recommendation, not the catalogue item. And a
    /// Google Places URL can't be loaded by AsyncImage at all (it needs the
    /// bundle-id header), so those failed into the mascot too.
    private func thumbnailURL(item: RexItem) -> URL? {
        if let urlString = item.image_url, let url = URL(string: urlString) { return url }
        if let photo = rec.photo_urls?.first, let url = URL(string: photo) { return url }
        if let photo = rec.photo_url, let url = URL(string: photo) { return url }
        return nil
    }


    /// Where it is. Shares a line with the subtitle now, so it is a view of
    /// its own rather than a row.
    @ViewBuilder
    private func localityRow(_ locality: String) -> some View {
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
        // Sept 15 — "Can't click through to the details in this section, the
        // whole tile should bring me through" (Danny). It only takes the tap
        // when there is something for it to do; otherwise it falls through
        // to the card.
        .allowsHitTesting(canViewOnMap)
    }

    /// The card's title, before the line-breaking decision is made about it.
    private func titleText(_ item: RexItem, size: CGFloat) -> some View {
        Text(item.title)
            .font(RexFont.display(size, weight: .semibold))
            .foregroundStyle(RexColor.foreground)
    }

    /// Whether a subtitle is only saying the title over again.
    ///
    /// Case and punctuation are ignored, and the year is stripped first, so
    /// "Instinct" against "Instinct" matches and so would "Instinct (2024)".
    private func isJustTheTitleAgain(_ subtitle: String, title: String) -> Bool {
        func bare(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined()
        }
        let stripped = bare(withoutYear(subtitle))
        return !stripped.isEmpty && stripped == bare(title)
    }

    /// Nov 22 — "remove publish / release dates from the main feed."
    ///
    /// The year is not a separate column; it is baked into items.subtitle
    /// when the item is created — "2021 · Drama" for a film, "Madeline
    /// Miller · 2011" for a book. So it comes out here, at the point of
    /// display, rather than by rewriting rows that other screens still want
    /// it on.
    ///
    /// Only a standalone four-digit year in the 19xx/20xx range, so "Sgt.
    /// Pepper 1967" keeps its title and "Catch-22" keeps its number. The
    /// separators either side go with it, or a stripped subtitle reads
    /// "· Drama".
    private func withoutYear(_ subtitle: String) -> String {
        let parts = subtitle
            .components(separatedBy: CharacterSet(charactersIn: "\u{00B7}|"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { part in
                guard part.count == 4, let n = Int(part) else { return !part.isEmpty }
                return !(1900...2099).contains(n)
            }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Nov 22 — "if map or user uploaded photo, then hero (across card). If
    /// stock image, then just thumbnail." And: "if hero pic, then no
    /// thumbnail."
    ///
    /// Two different kinds of picture were being treated as one. A film's
    /// poster and a book's jacket are stock: they are what the thing looks
    /// like, the same for everybody, and a 60pt square beside the title is
    /// exactly the right amount of them. A photograph somebody took is about
    /// this Rex in particular, and it deserves the width of the card.
    ///
    /// So a photograph becomes the hero and the thumbnail goes, because they
    /// would otherwise be the same image twice, 60pt of it stealing room
    /// from the title — "Paris Pour Le Weeke…".
    ///
    /// A map is a hero too, but it does not displace the thumbnail: a map
    /// and a picture of the place answer different questions, which is why a
    /// restaurant keeps its photograph beside the title and its map across
    /// the card below.
    ///
    /// Trips never show one. They have no catalogue art at all, so their
    /// thumbnail could only ever be the first of their own photographs —
    /// page one of the carousel directly beneath it.
    private var showsThumbnail: Bool {
        if category == .trip { return false }
        return (rec.photo_urls ?? []).isEmpty
    }

    @ViewBuilder
    private func thumbnail(item: RexItem) -> some View {
        Group {
            if let url = thumbnailURL(item: item) {
                // GoogleSafeAsyncImage, not AsyncImage: see thumbnailURL.
                GoogleSafeAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    // Sept 7 — "thumbnails aren't loading well on the feed".
                    // A dead or slow image URL left a plain grey square; the
                    // category's own illustration is a better answer than a
                    // blank tile, and it's what a Rex with no image at all
                    // already shows.
                    Image(category.placeholderImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .background(RexColor.muted)
                }
                // Places added before the URL fix never render — whichever
                // card sees it first repairs it for everyone, since items
                // aren't per-user.
                .task {
                    if let urlString = item.image_url {
                        await RexAPI.shared.repairPlacePhotoIfNeeded(itemId: item.id, imageURL: urlString)
                    }
                }
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
                // Name over time, which is what frees the width for the icons
                // to stay on this row — see the footer in body.
                VStack(alignment: .leading, spacing: 1) {
                    Text(author.display_name ?? author.username)
                        .font(RexFont.text(13, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !relativeTime.isEmpty {
                        Text(relativeTime)
                            .font(RexFont.text(11.5))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
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

/// The note's natural height, and the height it was given. Two keys rather
/// than one because they are measured in different places and SwiftUI would
/// otherwise reduce them together.
/// Oct 18 — the chip row's natural width against the width it was given, so
/// it scrolls exactly when something is out of sight and not otherwise.
private struct ChipsContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChipsRowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NoteHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NoteShownHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
