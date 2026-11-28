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
    /// Nov 28 — stacked reviews, option 1: "dots, '1 of 3 reviews' and Next
    /// review in the card underneath."
    ///
    /// Passed in rather than built here because the card renders one Rex and
    /// knows nothing about the others — which one is showing, and how many
    /// there are, belongs to whatever is doing the stacking. It is drawn
    /// inside the coloured frame and below the white inset, which is the one
    /// place only this view can put it.
    var stackFooter: AnyView? = nil

    /// Nov 28 — "allow users to click on the thumbnail to enlarge it."
    ///
    /// Identifiable rather than a bool and a separate array, so the list being
    /// shown and the fact that something is being shown cannot disagree —
    /// the same reason ItemDetailView's viewer is shaped this way.
    private struct PhotoRoute: Identifiable {
        let urls: [String]
        var id: String { urls.first ?? "" }
    }
    @State private var viewingPhotos: PhotoRoute?

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
    /// How far the white card is sunk inside the coloured frame, and how round
    /// its own corners are. Both deliberately smaller than the outer radius so
    /// the inset reads as one card inside another rather than two edges that
    /// nearly line up.
    private static let inset: CGFloat = 5
    private static let innerRadius: CGFloat = 14

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
                typeStrip

                // Nov 28 — the white card, inset inside the coloured frame.
                //
                // "All cards need to have the same design and formatting vis a
                // vis surround design, font size and bottom bar size and
                // placement." Every category now draws this same shape: a flat
                // strip across the top, a white card with rounded corners sunk
                // 5pt inside it, and the identical footer at the bottom. What
                // changes between categories is what goes in the middle, and
                // nothing else.
                VStack(alignment: .leading, spacing: 0) {

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
                        } else if let release = releaseLine(item) {
                            // Nov 28 — "add the year of release under the
                            // title". Screen and audio categories only: a
                            // film's year is a fact about the film, where a
                            // restaurant's would be a fact about the row.
                            //
                            // The year has been stripped out of every subtitle
                            // since 22 Nov ("remove publish / release dates
                            // from the main feed"), which is still right for
                            // the subtitle — it was arriving mid-sentence as
                            // "· 2021 ·". Here it gets its own line with a
                            // calendar beside it, which is what was asked for.
                            metaRow(icon: "calendar", text: release)
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

                        // Nov 28 — one pill under the heading, in the same
                        // place on every card: "View on map" on a place,
                        // "Seen? Rate it" on a film where "View on map" sits
                        // on the place card, "Also Rex'd by N friends" on
                        // anything with neither.
                        //
                        // It used to be three different things in three
                        // different places — the map was a strip across the
                        // bottom, "Been? Rate it" had a row of its own under
                        // the footer, and "Also Rex'd" sat below the note.
                        // One slot is what makes the categories look like one
                        // set rather than five layouts.
                        actionPill(item: item)
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
                            // Clear of the MAP tab on a place card; nothing at
                            // all on every other card, which has no tab.
                            .padding(.trailing, mapTabReserve)
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

                // Nov 28 — the hairline above the footer is now on every card
                // rather than only the ones with nothing above it. "One footer
                // for every card": the rule it closes off has to be there
                // every time too, or the footer sits at a different distance
                // from the content on half the feed.
                Rectangle()
                    .fill(RexColor.divider)
                    .frame(height: 1)
                    .padding(.horizontal, RexSpacing.cardPadding)

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
                // Nov 28 — one row, and the same one on every card: "avatar,
                // name, time, then likes, comments, save and send on one row."
                //
                // The time used to sit under the name, stacked, to buy back
                // the width the row kept running out of. The width came back
                // from somewhere better: "Been? Rate it" has gone up into the
                // pill under the heading, where the deck puts it, so this row
                // holds a name and four icons and nothing else.
                HStack(spacing: RexSpacing.sm) {
                    authorRow
                    Spacer(minLength: RexSpacing.sm)
                    // Blasts are questions, not Rex — no like/save row.
                    if !rec.isBlast {
                        RexCardActions(rec: rec, rexCount: rexCount, onCommentTap: onCommentTap)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    }
                }
                .padding(.horizontal, RexSpacing.cardPadding)
                .padding(.vertical, RexSpacing.md)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: Self.innerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) { mapTab }
                .padding(.horizontal, Self.inset)
                .padding(.bottom, stackFooter == nil ? Self.inset : 0)

                // Below the white card, on the coloured frame itself, which
                // is what makes the stack read as more of the same card
                // rather than a separate control under it.
                if let stackFooter {
                    stackFooter
                        .padding(.horizontal, 13)
                        .padding(.top, 7)
                        .padding(.bottom, 9)
                }
            }
            // Nov 28 — the rail down the left edge and the hairline round the
            // rest are gone. The frame is one flat block of the category's
            // colour with the white card sitting in it, which is what every
            // card in the deck does and what made them look like one set.
            .background(railColor)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            // Every card the same width, whatever's inside — see the 5 Sept
            // trip-card fix.
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $showingRexers) {
                RexersSheetView(itemId: rec.item_id, itemTitle: item.title)
            }
            .fullScreenCover(item: $viewingPhotos) {
                PhotoFullScreenView(urls: $0.urls, initialIndex: 0)
            }
        )
    }

    /// Full-width, edge to edge inside the card: your photos if there are
    /// any, else a trip's map of its stops, else a place's own map strip.
    /// Nov 28 — the deck took the full-width strip off every card except the
    /// two that hold a collection of other things.
    ///
    /// Places lost their map (option 3: "drops the map and puts a 'View on
    /// map' pill under the location"). Everything else lost its photo
    /// carousel: the first photograph is the thumbnail now, and tapping it
    /// opens all of them full screen. What is left is the trip's stops and
    /// the list's items, which are not pictures of the card's subject — they
    /// are the card's subject.
    @ViewBuilder
    private func media(item: RexItem) -> some View {
        if category == .trip {
            // Option 2 — "a swipeable row of three photos under the review,
            // with each stop's name underneath".
            CardChildStrip(source: .trip(rec.id), category: category, tileWidth: 106)
        } else if category == .list {
            // "Option 2 shows three bigger thumbnails across instead of four."
            CardChildStrip(source: .list(rec.id), category: category, tileWidth: 98)
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
                    // Only when it says more than the banner does — the
                    // faces and "N want to try this". A lone "Wants to try"
                    // is now in the bar at the top.
                    if wanters.count > 1 { wantedByBadge }
                } else if rec.isBlast {
                    HStack(spacing: 4) {
                        // Nov 23 — sparkles are the "made by a machine" icon
                        // everywhere else on a phone, and a blast is the
                        // opposite: a person asking their friends. Same swap
                        // the Ask-friends card and the Other category made.
                        Image(systemName: "megaphone").font(.system(size: 10))
                        Text("Asking").font(RexFont.text(11, weight: .medium))
                    }
                    .foregroundStyle(RexColor.accent)
                }

                // Kept on a want card too. "You want to try it, and two
                // friends have actually been" is a different sentence from
                // "six people want to try it" — it was the bookmark pair that
                // said the same thing twice, not this.
                // Nov 28 — only when the pill slot above is already taken by
                // the map or a rate-it prompt. Otherwise this chip is up there
                // under the heading, and drawing it in both places is how the
                // bookmark pair said the same thing twice in October.
                if others > 0, pillIsTakenByAction {
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
    /// Nov 28 — the redesign deck. A flat strip: the type on the left, the
    /// poster's stance on the right, and nothing else in it.
    ///
    /// Two things left this bar. The wave, because "make the curve like in
    /// option 1" is the rounded white inset below — no feed card in the deck
    /// has a wave, and the detail page still does. And the rating, because
    /// "remove the 3.0/5 rating on every card".
    private var typeStrip: some View {
        HStack(spacing: 5) {
            Image(systemName: category.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(category.label.uppercased())
                // Nov 28 — "no text smaller than 11pt: type labels, dates,
                // thumbnail names and counts." This was 10.5.
                .font(.system(size: 11, weight: .bold))
                .tracking(0.9)
            Spacer(minLength: 0)
            stance
        }
        .foregroundStyle(category.tintColor)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the poster means by this — been and loved it, or means to go.
    ///
    /// Confirmed 28 Nov: the heart on the strip is the *poster's* stance, not
    /// the viewer's own like. The viewer's like is the heart in the footer,
    /// which is the one that counts and the one that can be tapped.
    @ViewBuilder
    private var stance: some View {
        if rec.isBlast {
            // Nov 23 — sparkles are the "made by a machine" icon everywhere
            // else on a phone, and a blast is the opposite: a person asking
            // their friends.
            stanceLabel(icon: "megaphone", text: "Asking")
        } else if rec.isWant {
            stanceLabel(icon: "bookmark", text: "Wants to try")
        } else {
            Image(systemName: "heart.fill")
                .font(.system(size: 13))
                .foregroundStyle(RexColor.destructive)
        }
    }

    /// Nov 28 — place card, option 3: "a small ‹ MAP tab on the right edge
    /// hinting you can swipe left to see the map."
    ///
    /// A tap, not a swipe. The card already carries a horizontal gesture —
    /// swipe-to-remove — and a second one competing with it on the same axis
    /// is exactly how #120 happened, where a drag on a photo took the card
    /// off the feed instead of paging it. The tab reads the same and goes to
    /// the same place; it just does not fight the gesture already there.
    private var showsMapTab: Bool {
        guard category == .place || category == .event else { return false }
        guard let item = rec.items, item.lat != nil, item.lng != nil else { return false }
        return onViewOnMap != nil
    }

    /// The tab hangs over the card's trailing edge at the review's height, so
    /// the review has to stop short of it. Without this the last word of
    /// every line runs underneath it — "Le Chevre" half under MAP, which is
    /// exactly what the first build of this did.
    private var mapTabReserve: CGFloat { showsMapTab ? 40 : 0 }

    @ViewBuilder
    private var mapTab: some View {
        if showsMapTab, let item = rec.items, let onViewOnMap {
            Button { onViewOnMap(rec.item_id) } label: {
                VStack(spacing: 0) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                    Text("MAP")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                }
                .foregroundStyle(category.tintColor)
                .padding(.vertical, 7)
                .padding(.horizontal, 6)
                .background(railColor.opacity(0.55))
                .clipShape(
                    .rect(topLeadingRadius: 9, bottomLeadingRadius: 9,
                          bottomTrailingRadius: 0, topTrailingRadius: 0)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Level with the review, which is where the deck puts it — clear
            // of the thumbnail above and the footer below.
            .padding(.top, 108)
            .accessibilityLabel("See \(item.title) on the map")
        }
    }

    private func stanceLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
        }
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
    ///
    /// Nov 28 — which of the two wins now depends on the category. On a place
    /// the poster's own photograph is the better picture and is what the
    /// deck's place card shows; on a book or a film the catalogue art is, and
    /// somebody's photo of their own television is not.
    private func thumbnailURL(item: RexItem) -> URL? {
        let catalogueArtWins = category == .book || category == .tv
            || category == .movie || category == .podcast
        if !catalogueArtWins, let photo = rec.photo_urls?.first,
           let url = URL(string: photo) { return url }
        if let urlString = item.image_url, let url = URL(string: urlString) { return url }
        if let photo = rec.photo_urls?.first, let url = URL(string: photo) { return url }
        if let photo = rec.photo_url, let url = URL(string: photo) { return url }
        return nil
    }

    /// A jacket is portrait and a photograph is square, and forcing one into
    /// the other's box is why covers used to arrive cropped through the title.
    private var thumbnailSize: CGSize {
        category == .book
            ? CGSize(width: 74, height: 96)
            : CGSize(width: 76, height: 76)
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

    /// A line of secondary information under the title — a date, a year, a
    /// count. Set the same way wherever it appears, which is the whole point:
    /// "same title, date and review fonts" across every category.
    private func metaRow(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text)
                .font(RexFont.text(12.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(RexColor.mutedForeground)
    }

    /// Nov 28 — "add the year of release under the title, and for tv add how
    /// many series there are along with the year it was released."
    ///
    /// The year is the half that exists. It is baked into `items.subtitle` when
    /// the item is created — "2021 · Drama" for a film, "Madeline Miller ·
    /// 2011" for a book — so it comes back out here rather than by rewriting
    /// rows other screens still read.
    ///
    /// The series count does not exist anywhere: no column on `items`, and
    /// nothing has ever fetched one. That is a migration plus a lookup at
    /// import time, not a layout change, so it is deliberately absent rather
    /// than guessed. A card that says "6 series" because the card decided is
    /// worse than one that only says 2015.
    private func releaseLine(_ item: RexItem) -> String? {
        switch category {
        case .tv, .movie, .podcast: break
        default: return nil
        }
        return item.subtitle?
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .first { part in
                guard part.count == 4, let n = Int(part) else { return false }
                return (1900...2099).contains(n)
            }
    }

    /// How many people other than the author have Rex'd this item.
    private var otherRexers: Int { max(0, rexCount - 1) }

    /// Whether the pill slot is already spoken for by something the category
    /// owns, in which case "Also Rex'd by N" stays where it has always been,
    /// in the row under the note.
    private var pillIsTakenByAction: Bool {
        if category == .place || category == .event,
           let item = rec.items, item.lat != nil, item.lng != nil,
           onViewOnMap != nil { return true }
        if rec.isWant, onMarkBeen != nil,
           rec.user_id == RexAPI.shared.currentUserId { return true }
        return false
    }

    /// What "rate it" is called depends on what you'd have done with the
    /// thing. You are not "been" to a film.
    private var rateItPrompt: String {
        switch category {
        case .tv, .movie, .podcast: return "Seen? Rate it"
        case .book: return "Read it? Rate it"
        default: return "Been? Rate it"
        }
    }

    /// The one pill under the heading. At most one, deliberately: two pills is
    /// two things asking to be tapped in a card whose whole surface is already
    /// a tap target, and every card in the deck shows exactly one.
    @ViewBuilder
    private func actionPill(item: RexItem) -> some View {
        if category == .place || category == .event,
           item.lat != nil, item.lng != nil, let onViewOnMap {
            // Nov 28 — places lost their map strip (option 3), so this pill
            // and the MAP tab on the card's edge are now the two ways to it.
            pill(icon: "map", text: "View on map") { onViewOnMap(rec.item_id) }
        } else if rec.isWant, let onMarkBeen,
                  rec.user_id == RexAPI.shared.currentUserId {
            // Nov 22 — "been?" on a want card, which had a row of its own
            // under the footer and now sits where the map pill does.
            pill(icon: "star", text: rateItPrompt, action: onMarkBeen)
        } else if otherRexers > 0 {
            pill(icon: otherRexers >= 3 ? "flame.fill" : "person.2.fill",
                 text: alsoRexdLabel,
                 tint: otherRexers >= 3 ? RexColor.accent : nil) {
                showingRexers = true
            }
        }
    }

    /// Three or more people is worth calling hot.
    private var alsoRexdLabel: String {
        otherRexers >= 3
            ? "Hot — \(otherRexers + 1) friends Rex'd this"
            : "Also Rex'd by \(otherRexers) \(otherRexers == 1 ? "friend" : "friends")"
    }

    private func pill(icon: String, text: String, tint: Color? = nil,
                      action: @escaping () -> Void) -> some View {
        let colour = tint ?? category.tintColor
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(text).font(RexFont.text(12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(colour)
            .padding(.horizontal, 10)
            // Short of the 44pt tap target the rest of the app holds to: the
            // deck's pills are a third of the card's heading block and a 44pt
            // capsule there would be taller than the title beside it. 32 with
            // the row's own spacing around it is the compromise.
            .frame(minHeight: 32)
            .background(colour.opacity(0.14))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The card's title, before the line-breaking decision is made about it.
    private func titleText(_ item: RexItem, size: CGFloat) -> some View {
        Text(item.title)
            // Nov 28 — DM Sans Bold, not Archivo Black. Archivo is the
            // display face: it is very heavy and very wide, which is right
            // for a screen heading and the wordmark and wrong for a title
            // sitting beside a 76pt thumbnail. "TYCOZ - CRÊPERIE & OYSTER
            // BAR" took two lines in Archivo at any size the card could
            // afford. The whole deck sets card titles in the body face.
            .font(RexFont.text(size, weight: .bold))
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
    /// Nov 28 — the deck replaces all of the above with a simpler rule, and
    /// the rule is the reason the cards now look like one set: every card gets
    /// a thumbnail in the same corner at the same size.
    ///
    /// The hero went with the place card's map (option 3). A photograph that
    /// used to run the width of the card is now the thumbnail itself, and
    /// tapping it opens every photo full screen — which is what "allow users
    /// to click on the thumbnail to enlarge it" asks for, and is where the
    /// rest of the pictures went.
    private var showsThumbnail: Bool {
        // A blast is a question, not a thing, so there is nothing to
        // picture — it was showing the category's mascot, which is 46pt of
        // decoration holding the title away from the question underneath.
        if rec.isBlast { return false }
        // A trip shows its stops in a row underneath and a list shows its
        // items; either would otherwise repeat its own first photograph a
        // few points further up.
        if category == .trip || category == .list { return false }
        return true
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
        // Nov 23 — "too much blank space, needs to move up", twice, both
        // times on a card whose text column is a single line. The header row
        // is as tall as the taller of its two sides, and that was always the
        // thumbnail: 60pt of it against a 24pt title left 36pt of nothing
        // between the title and the note underneath. 46 takes most of that
        // back without the picture stopping being a picture.
        // Nov 28 — 46 was sized for a card where a photograph ran full width
        // underneath and the thumbnail was only ever catalogue art. It is the
        // only picture on the card now, so it takes the deck's size.
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            // "Allow users to click on the thumbnail to enlarge it."
            let photos = rec.photo_urls ?? []
            if !photos.isEmpty { viewingPhotos = PhotoRoute(urls: photos) }
        }
        // A card with no photographs of its own has nothing to enlarge — the
        // tap should fall through and open the item instead.
        .allowsHitTesting(!(rec.photo_urls ?? []).isEmpty)
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
                // Nov 28 — "avatar, name, time" on one line. They were stacked
                // to buy width back for the icons; the pill slot under the
                // heading took "Been? Rate it" off this row, which is where
                // that width actually came from.
                //
                // The name truncates and the time does not: a long name
                // shortening to "lizzieever…" keeps the icons where they are
                // on every card, which is the thing stacking was protecting.
                HStack(spacing: 4) {
                    Text(author.display_name ?? author.username)
                        .font(RexFont.text(13, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !relativeTime.isEmpty {
                        Text("\u{00B7} \(relativeTime)")
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

/// Nov 28 — the row of children on a trip or a list card.
///
/// "A swipeable row of pub photos with each pub's name underneath, and an
/// arrow on the right hinting there are more." Trips take the same row with
/// their stops in itinerary order (option 2); lists take three bigger ones.
///
/// Both sources already existed and both return whole `FeedRecommendation`s,
/// so the photograph and the name arrive together in one request —
/// `fetchTripStops` and `fetchListItems`. No new endpoint, and no second
/// round trip for the pictures.
///
/// It replaces TripMapTileView on the card. The map has not gone: it is still
/// what the trip's own page draws, and still what the map tab filters. What
/// went is a map of Paris standing in for the eight places the trip is about.
struct CardChildStrip: View {
    enum Source: Equatable {
        case trip(String)
        case list(String)

        var id: String {
            switch self {
            case .trip(let id), .list(let id): return id
            }
        }
    }

    let source: Source
    let category: RexCategory
    var tileWidth: CGFloat = 98
    var tileHeight: CGFloat = 74

    @State private var children: [FeedRecommendation] = []
    /// Set only when the fetch actually answered. nil means it failed and
    /// should be retried; [] means the trip genuinely has no stops yet — the
    /// distinction TripMapTileView got wrong on 22 Nov and pinned a map onto
    /// every card that had timed out once.
    @State private var loaded = false

    var body: some View {
        Group {
            if children.isEmpty {
                // Nothing at all rather than an empty frame: a trip with no
                // stops is a card whose middle is the review, and 74pt of
                // grey says only that something failed.
                EmptyView()
            } else {
                strip
            }
        }
        .task(id: source.id) { await load() }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 9) {
                ForEach(children) { child in
                    VStack(alignment: .leading, spacing: 5) {
                        tile(child)
                            .frame(width: tileWidth, height: tileHeight)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(child.items?.title ?? "")
                            // "No text smaller than 11pt: type labels, dates,
                            // thumbnail names and counts."
                            .font(RexFont.text(11))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: tileWidth, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, RexSpacing.cardPadding)
        }
        // #120 — a horizontal drag here is a scroll through the stops, not a
        // swipe that takes the card off the feed.
        .swipeToRemoveExclusionZone()
        .overlay(alignment: .trailing) {
            // "An arrow on the right hinting there are more." Only when there
            // genuinely are: four tiles that all fit need no affordance, and
            // one drawn anyway is a promise of something that is not there.
            if children.count > Int(3) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RexColor.foreground)
                    .frame(width: 26, height: 26)
                    .background(RexColor.card, in: Circle())
                    .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                    .padding(.trailing, 6)
                    .offset(y: -(tileHeight > 0 ? 9 : 0))
                    .allowsHitTesting(false)
            }
        }
        .padding(.bottom, RexSpacing.md)
    }

    @ViewBuilder
    private func tile(_ child: FeedRecommendation) -> some View {
        let urlString = child.photo_urls?.first ?? child.items?.image_url
        if let urlString, let url = URL(string: urlString) {
            // GoogleSafeAsyncImage, not AsyncImage: a Google Places photo
            // needs the bundle-id header and fails into the placeholder
            // otherwise. See thumbnailURL.
            GoogleSafeAsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        // The child's own category would be better than the parent's, but a
        // stop with no photograph usually has no type either; the trip's
        // mascot is at least the right family.
        Image(category.placeholderImageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .background(RexColor.muted)
    }

    private func load() async {
        guard !loaded else { return }
        let fetched: [FeedRecommendation]?
        switch source {
        case .trip(let id):
            fetched = try? await RexAPI.shared.fetchTripStops(tripRecommendationId: id)
        case .list(let id):
            fetched = try? await RexAPI.shared.fetchListItems(listRecommendationId: id)
        }
        // Capped. A list of sixty pubs reads fine as "the first dozen, swipe
        // for more", and every extra tile is another image request on a card
        // that may well scroll past before anyone looks at it.
        children = Array((fetched ?? []).prefix(12))
        loaded = fetched != nil
    }
}
