import SwiftUI

struct ItemDetailView: View {
    let itemId: String
    /// Oct 2 — "don't need the heading twice here". Inside the map's place
    /// sheet the item's name is already the first thing in the card, so the
    /// navigation bar repeating it is noise. Pushed as a page it still wants
    /// a title, so this is a parameter rather than a removal.
    var showsTitle: Bool = true

    @State private var item: RexItem?
    /// Sept 17 — synopsis and ratings for films, TV and books, fetched from
    /// the catalogue the item came from. See RexSearch.details.
    @State private var details: RexSearch.ItemDetails?
    /// Oct 2 — "could we have a button here to see more from this author, and
    /// then a list of other works and who has rex'd if any".
    @State private var moreByAuthor: [RexSearchHit] = []
    /// Lowercased title -> the item in REX, for whichever of the author's
    /// books someone here has actually Rex'd.
    @State private var authorBookItems: [String: RexItem] = [:]
    @State private var authorBookRexCounts: [String: Int] = [:]
    @State private var isLoadingDetails = false
    @State private var synopsisExpanded = false
    /// Oct 3 — Google Place Details for a place: its photos, its one-line
    /// description and its opening times. Held here only for the fetch that
    /// populated it; every later visit reads the cached columns off the item.
    @State private var placeDetails: RexPlaceDetails?
    @State private var hoursExpanded = false
    /// Oct 5 — other branches of this chain: those already in REX, and those
    /// Google knows about that nobody has Rex'd.
    @State private var chainBranchesHere: [RexItem] = []
    @State private var chainBranchesElsewhere: [RexSearchHit] = []
    @State private var addingBranch: RexSearchHit?
    /// Oct 3 — press coverage, under "On Google".
    @State private var articles: [RexArticle] = []
    @State private var recs: [FeedRecommendation] = []
    /// Oct 12 — "when you Rex a want-to-try it should also show who has Rex'd
    /// it and who else has want-to-try it." Who has Rex'd it was already here;
    /// who else is only meaning to was not, anywhere on the page.
    @State private var wanters: [RexProfileDetail] = []
    /// Oct 14 — the wants themselves, not just who made them: a want carries a
    /// note, photos and its own comment thread, and none of that was on the
    /// page while the only trace of a want was a face in a row.
    @State private var wantPosts: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var rating: Double = 10
    @State private var note: String = ""
    @State private var isSaving = false
    /// Oct 4 — whether the note is being edited. A take you've already written
    /// shows as text until you ask to change it.
    @State private var isEditingNote = false
    /// "When you click into a 'want to try', you should be able to add to
    /// want to try — at the moment, on a TV want, I click in and can only
    /// rate, not add to want to try." A want is its own table/row, separate
    /// from a rated recommendation (see RexCardActions.toggleWant) — this
    /// screen only ever offered the rating form, with no way to see or
    /// toggle the want flag at all once you'd followed a want card in here.
    @State private var wanted = false
    /// Oct 12 — everyone who has asked to be told when this event's tickets
    /// drop: you, and whichever friends RLS lets you see.
    @State private var ticketReminderPeople: [RexProfileDetail] = []
    /// Raised the moment you add an event to want-to-try, which is when the
    /// question is live. Never raised on its own.
    @State private var offerTicketReminder = false
    @State private var editingOnSaleDate = false
    /// Which timings you have on this event. Empty means no reminder.
    @State private var myTicketLeads: Set<Int> = []
    @State private var editingReminderTimings = false
    @State private var draftOnSaleDate = Date()
    @State private var isTogglingWant = false
    /// The card's own save button merged bookmark ("want to try") and this
    /// into one icon a while back — two save actions there tested as
    /// confusing ("what does that tick mean?"). Kathryn asked for a
    /// dedicated save-to-collection action back, just scoped to here (the
    /// full item page, which has the room) rather than reintroducing that
    /// on the card.
    /// Sept 9 — one sheet modifier, not several. Stacking `.sheet`
    /// modifiers on the same view silently drops all but one of them; see
    /// FeedView.ActiveSheet.
    private enum ActiveSheet: Identifiable {
        case collection(FeedRecommendation)
        case edit(FeedRecommendation)
        /// Oct 13 — Joe's ordering: place this one against the rest.
        case rank
        var id: String {
            switch self {
            case .collection(let rec): return "collection-\(rec.id)"
            case .edit(let rec): return "edit-\(rec.id)"
            case .rank: return "rank"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    /// Oct 13 — where this sits in your own ordering, and how long that
    /// ordering is. Nil until looked up; nil after, if it isn't placed.
    @State private var myRank: (position: Int, total: Int)?
    /// "View on map function via a button" — the feed/profile cards
    /// already had one (#133), the full item page never did.
    @Environment(\.viewOnMap) private var viewOnMap

    /// Oct 16 — "Phoebe shouldn't be able to Rex the same place twice", and
    /// "I can't see my own review here".
    ///
    /// She hadn't, and it was there. Adding a place you have Rex'd to a trip
    /// writes a second recommendation row for it — trip_id set, rating 0, no
    /// note — which is deliberate and is what lets a trip revisit somewhere
    /// (3 Oct). This page asked for every row on the item and drew each one,
    /// so one person showed up twice: once for what they said, and once for
    /// an empty stop.
    ///
    /// One row per person, the real one winning. Same rule the map pin took
    /// yesterday, and the same reason — a stop is a fact about an itinerary,
    /// not a second opinion. Decided on what the row carries rather than on
    /// trip_id, because that column isn't in this select and a row with a
    /// rating and a note is the one worth showing whatever put it there.
    static func onePerPerson(_ recs: [FeedRecommendation]) -> [FeedRecommendation] {
        func weight(_ rec: FeedRecommendation) -> Int {
            (rec.rating > 0 ? 2 : 0) + ((rec.note ?? "").isEmpty ? 0 : 1)
        }
        var best: [String: FeedRecommendation] = [:]
        for rec in recs {
            guard let held = best[rec.user_id] else { best[rec.user_id] = rec; continue }
            if weight(rec) > weight(held) { best[rec.user_id] = rec }
        }
        // Keep the order the query returned, which is newest first.
        var seen = Set<String>()
        return recs.compactMap { rec in
            guard seen.insert(rec.user_id).inserted else { return nil }
            return best[rec.user_id]
        }
    }

    /// Whether anybody other than you has said something about this.
    private var othersHaveSpoken: Bool {
        recs.contains { $0.user_id != RexAPI.shared.currentUserId && !($0.note ?? "").isEmpty }
            || recs.contains { $0.user_id != RexAPI.shared.currentUserId && $0.rating > 0 }
    }

    private var myRec: FeedRecommendation? {
        recs.first { $0.user_id == RexAPI.shared.currentUserId }
    }

    /// Which take a save-to-collection action here actually attaches to —
    /// collections are per-recommendation (saved_posts references one), so
    /// this needs a real rec. Your own take if you have one, otherwise
    /// whichever friend's take is showing — same as saving straight from
    /// their card in the feed.
    private var collectionTargetRec: FeedRecommendation? {
        myRec ?? recs.first
    }

    var body: some View {
        ScrollView {
            if isLoading {
                // Oct 14 — "this is the weird bar on my loading screen. I was trying
                // to load my profile."
                //
                // A ScrollView takes its content's width, and a bare
                // ProgressView is about twenty points wide. The page's
                // background is painted behind that content and told to ignore
                // the safe area, so while the only thing on the page was a
                // spinner it painted a narrow strip the full height of the
                // screen instead of the whole page — the bar, sitting right
                // behind the spinner, in every pushed screen that loads this
                // way.
                //
                // Filling the width is also just what a loading state should
                // do: hold the space the content is about to occupy.
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if let item {
                VStack(alignment: .leading, spacing: 0) {
                    header(item: item)
                    // Oct 8 — "I want most info to appear on one screen,
                    // there's just a lot of blank space." Option two of the
                    // three mock-ups: the details section's nine labelled rows
                    // become a two-column strip of facts directly under the
                    // header, and the synopsis sits under that at two lines.
                    // Together they cost about the height one old heading did,
                    // which is what puts the reviews above the fold.
                    // Oct 12 — "change cards so all mirror the places format."
                    // The facts strip built for books on the 8th, now on every
                    // category that has a catalogue behind it, so the four
                    // pages read as one family rather than four screens that
                    // happen to share a back button.
                    if hasFactsStrip {
                        catalogueFactsSection(item: item).padding(.horizontal, 16)
                    }
                    // Oct 12 — "include on a card for film and TV where you can
                    // watch said show. Make it prominent at the top."
                    //
                    // Directly under the title, above the reviews, because it
                    // is the one thing on the page you act on rather than read:
                    // you have decided to watch it, and the only question left
                    // is where.
                    watchOnSection
                    // Oct 14 — "move cast up in the movie page." This reverses
                    // the call of 5 October, which put the cast below the
                    // reviews because it was the longest thing on the page and
                    // was sitting between you and what your friends thought.
                    // It sits above them now, under Watch on: by then you know
                    // what it is and where to see it, and who is in it is the
                    // next thing anybody asks about a film.
                    castSection
                    googlePhotosSection
                    communityPhotosSection
                    recipeSection(item: item)
                    // Oct 5 — "if you are opening a friend's Rex, perhaps the
                    // box to Rex it yourself should be below the friend's
                    // review?"
                    //
                    // Yes, and it's the stronger half of the ask. You open a
                    // friend's recommendation to read what they said; a form
                    // asking what *you* think, before you've been told
                    // anything, is the app talking over them. When somebody
                    // else has already said something, they go first.
                    //
                    // When nobody has, your own box leads — there is nothing
                    // to read, and an empty "What friends say" above a form is
                    // a worse opening than the form.
                    // Oct 8 — one order, whoever has spoken. Your review sits
                    // in the same place on every page: under anybody else's,
                    // where you'd look for it. The conditional swap meant a
                    // page you had Rex'd was laid out differently from one you
                    // hadn't, which is what made them feel like two screens.
                    friendsSection
                    yourTakeSection
                    // Context below the people. Cast, then other work by the
                    // same author, then where else it exists.
                    // Oct 5 — the synopsis and the outside world's scores moved
                    // down here from the header. They are the longest thing on
                    // the page and they were sitting between you and the
                    // reviews; nobody opens a friend's Rex to read a synopsis
                    // first.
                    // The catalogue categories moved their details up under
                    // the header; anything else still shows them here.
                    if !hasFactsStrip {
                        detailsSection
                            .padding(.horizontal, 16)
                    }
                    chainSection
                    moreByAuthorSection
                    elsewhereSection
                    // Oct 14 — "move the rank it against your others to the
                    // bottom of the card." It was up in the header beside
                    // Rex'd by and Want to try, where it read as one of the
                    // things you do when you arrive. It isn't: you place a
                    // book against your others once you've read the page and
                    // formed a view, so it belongs at the end of it.
                    rankRow
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(showsTitle ? (item?.title ?? "") : "")
        .navigationBarTitleDisplayMode(.inline)
        // Oct 12 — "move the save to collection button?"
        //
        // It sat in the middle of the header sharing a row with a rating
        // badge, which is why it read as floating: a control among labels.
        // In the navigation bar it is always in the same place, always
        // reachable without scrolling, and competing with nothing — the same
        // spot Safari and Instagram put the equivalent, so the gesture is
        // already learned.
        //
        // An icon rather than words, because the bar has room for one of
        // those and the sheet it opens says what it is.
        .toolbar {
            if let collectionTargetRec {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .collection(collectionTargetRec)
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(RexColor.primary)
                    }
                    .accessibilityLabel("Save to collection")
                }
            }
        }
        // A drag can drop the keyboard too, so the comment field and its Post
        // button aren't only reachable via the keyboard's own Done button.
        .rexDismissableKeyboard()
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .collection(let rec):
                AddToCollectionView(rec: rec, onDone: {})
            case .edit(let rec):
                EditRexView(
                    rec: rec,
                    onSaved: { Task { await load() } },
                    onDeleted: { Task { await load() } }
                )
            case .rank:
                if let item {
                    RankingCompareView(
                        newItem: item,
                        category: RexCategory(rawType: item.type)
                    ) {
                        Task { await loadMyRank() }
                    }
                }
            }
        }
        .task { await load() }
        // Needs the item first, for its author.
        .task(id: item?.id) { await loadMoreByAuthor() }
        .task(id: item?.id) {
            if let item { await loadPlaceDetails(item) }
        }
        .task(id: item?.id) {
            if let item { await loadArticles(item) }
        }
        .task(id: item?.id) {
            if let item { await loadChain(item) }
        }
        .sheet(item: $addingBranch) { branch in
            // Rexing a branch is posting a Rex like any other — you say what
            // you thought, because you are the one who went.
            AddRexView(onDone: { Task { await load() } }, initialPlaceHit: branch)
        }
        // Oct 12 — the offer, raised by adding an event to want-to-try. An
        // alert rather than a sheet: it is one question with a yes and a no,
        // and it arrives unprompted, so it should be dismissable without
        // reading twice.
        .alert("Remind you about tickets?", isPresented: $offerTicketReminder) {
            Button("Yes, remind me") { Task { await toggleTicketReminder() } }
            Button("Pick the timings") {
                guard let onSale = ticketsOnSale else { return }
                Task {
                    await applyTicketLeads(RexAPI.defaultTicketLeads, onSale: onSale)
                    editingReminderTimings = true
                }
            }
            Button("No thanks", role: .cancel) {}
        } message: {
            if let onSale = ticketsOnSale {
                Text("Tickets go on sale \(onSale.formatted(date: .abbreviated, time: .shortened)). We'll nudge you the day before and again half an hour before.")
            }
        }
        // Oct 12 — "make these editable." A list of ticks rather than a count
        // or a slider: the timings people want are a handful of named moments,
        // and picking from them is one tap where a duration picker is four.
        // Writes on each tap, so backing out with the arrow keeps the change —
        // the same call made for arranging collections this morning.
        .sheet(isPresented: $editingReminderTimings) {
            NavigationStack {
                List {
                    Section {
                        ForEach(RexAPI.ticketLeadChoices, id: \.minutes) { choice in
                            Button {
                                guard let onSale = ticketsOnSale else { return }
                                var next = myTicketLeads
                                if next.contains(choice.minutes) {
                                    next.remove(choice.minutes)
                                } else {
                                    next.insert(choice.minutes)
                                }
                                myTicketLeads = next
                                Task { await applyTicketLeads(next, onSale: onSale) }
                            } label: {
                                HStack {
                                    Text(choice.label)
                                        .font(RexFont.text(15))
                                        .foregroundStyle(RexColor.foreground)
                                    Spacer()
                                    if myTicketLeads.contains(choice.minutes) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(RexColor.primary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text(myTicketLeads.isEmpty
                             ? "Nothing ticked — you won't be reminded about this one."
                             : "Each one is a separate push, and each goes out once.")
                    }
                }
                .scrollContentBackground(.hidden)
                .background(RexColor.background.ignoresSafeArea())
                .navigationTitle("When to remind you")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { editingReminderTimings = false }
                            .font(RexFont.text(15, weight: .semibold))
                    }
                }
            }
            .tint(RexColor.primary)
        }
        .sheet(isPresented: $editingOnSaleDate) {
            NavigationStack {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    DatePicker(
                        "On sale",
                        selection: $draftOnSaleDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .tint(RexColor.primary)

                    Text("Anyone can set this — it's a fact about the event, not about who added it. Everyone who asks for a reminder gets told half an hour before.")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                    Spacer()
                }
                .padding(RexSpacing.page)
                .background(RexColor.background.ignoresSafeArea())
                .navigationTitle("When do tickets drop?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { editingOnSaleDate = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            let chosen = draftOnSaleDate
                            editingOnSaleDate = false
                            Task {
                                do {
                                    try await RexAPI.shared.setTicketsOnSale(itemId: itemId, at: chosen)
                                    await load()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .font(RexFont.text(15, weight: .semibold))
                    }
                }
            }
            .tint(RexColor.primary)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let itemTask = RexAPI.shared.fetchItem(id: itemId)
            async let recsTask = RexAPI.shared.fetchRecommendations(forItem: itemId)
            // Best-effort, same reasoning as everywhere else this is
            // fetched — not knowing your want status shouldn't break
            // loading the rest of the page.
            async let wantedTask = RexAPI.shared.isWanted(itemId: itemId)
            let (fetchedItem, fetchedRecs) = try await (itemTask, recsTask)
            item = fetchedItem
            // Nothing from someone on either side of a block.
            recs = Self.onePerPerson(RexAPI.shared.filterHidden(fetchedRecs))
            wanters = await RexAPI.shared.fetchWanters(itemIds: [itemId])[itemId] ?? []
            wantPosts = await RexAPI.shared.fetchWants(forItem: itemId)
            // Only events have these, so only events pay for the request.
            if RexCategory(rawType: fetchedItem.type) == .event {
                ticketReminderPeople = await RexAPI.shared.ticketReminders(itemId: itemId)
                myTicketLeads = await RexAPI.shared.myTicketLeads(itemId: itemId)
            }
            await loadMyRank()
            Task { await loadDetails(fetchedItem) }
            wanted = (try? await wantedTask) ?? false
            if let mine = fetchedRecs.first(where: { $0.user_id == RexAPI.shared.currentUserId }) {
                rating = mine.rating
                note = mine.note ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleWant() async {
        isTogglingWant = true
        let next = !wanted
        wanted = next
        do {
            if next {
                try await RexAPI.shared.createWant(itemId: itemId)
                // Oct 12 — "if someone says 'want to try' on an event, then
                // give them an option to set a reminder for ticket sales if
                // appropriate."
                //
                // Offered here rather than always on show, because this is the
                // moment it is wanted — you have just said you want to go, and
                // the next thought is how you get in. "If appropriate" is the
                // on-sale time existing: no time, no offer, which is correct
                // for a free exhibition and for everything added before anyone
                // thought to record one.
                if isEvent, ticketsOnSale != nil, !reminderSet {
                    offerTicketReminder = true
                }
            } else {
                try await RexAPI.shared.removeWant(itemId: itemId)
            }
        } catch {
            wanted = !next
        }
        isTogglingWant = false
    }

    /// The event's ticket-release time, once the item has loaded one.
    private var ticketsOnSale: Date? {
        item?.tickets_on_sale_at.flatMap { ISO8601DateFormatter.rexDate(from: $0) }
    }

    private var isEvent: Bool {
        RexCategory(rawType: item?.type) == .event
    }

    private var reminderSet: Bool { !myTicketLeads.isEmpty }

    /// What the button says once reminders are on. Names the timings when
    /// there are one or two, because "the day before and 30 minutes before" is
    /// the whole answer and reads better than a number; counts them beyond
    /// that, where naming all of them would be longer than the card.
    private var reminderSummary: String {
        let names = RexAPI.ticketLeadChoices
            .filter { myTicketLeads.contains($0.minutes) }
            .map { $0.label.replacingOccurrences(of: " before", with: "") }
        switch names.count {
        case 0: return "Reminder set"
        case 1: return "Reminding you \(names[0].lowercased())"
        case 2: return "Reminding you \(names[0].lowercased()) and \(names[1].lowercased())"
        default: return "\(names.count) reminders set"
        }
    }

    /// Turns reminders on with both defaults, or off entirely. The picker is
    /// for changing the timings; this is the one-tap yes and no either side of
    /// it, which is what the want-to-try offer and the main button need.
    private func toggleTicketReminder() async {
        guard let onSale = ticketsOnSale else { return }
        await applyTicketLeads(reminderSet ? [] : RexAPI.defaultTicketLeads, onSale: onSale)
    }

    private func applyTicketLeads(_ leads: Set<Int>, onSale: Date) async {
        do {
            try await RexAPI.shared.setTicketReminders(itemId: itemId, onSaleAt: onSale, leads: leads)
            myTicketLeads = leads
            ticketReminderPeople = await RexAPI.shared.ticketReminders(itemId: itemId)
        } catch {
            errorMessage = error.localizedDescription
            myTicketLeads = await RexAPI.shared.myTicketLeads(itemId: itemId)
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await RexAPI.shared.upsertRecommendation(itemId: itemId, rating: rating, note: note)
                recs = try await RexAPI.shared.fetchRecommendations(forItem: itemId)
                // Back to reading it, now that it's written.
                isEditingNote = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    /// Oct 13 — the rebrand's header.
    ///
    /// One shape for every category: the painted band, the wavy edge, the
    /// thing's own artwork resting on it, then the pill, the title and whoever
    /// is involved. Replaces the two layouts that were here — a hero photo for
    /// places, a thumbnail beside the title for everything else — which is why
    /// a place and a book never quite read as the same app.
    ///
    /// The artwork is on the band rather than beside the title so the title
    /// gets the full width: see RexPageHeader for why no type size fixes that
    /// on its own.
    @ViewBuilder
    private func header(item: RexItem) -> some View {
        let category = RexCategory(rawType: item.type)
        VStack(alignment: .leading, spacing: 0) {
            // Oct 14 — photographs if there are any, the category's texture if
            // not. A folded screen of real photos is worth 30% of the screen;
            // a flat pattern is worth 20%, and no more.
            Group {
            // Oct 14 — "the user uploaded photo at the top, with the thumbnail
            // being the Google pic." A picture somebody who went there took
            // goes across the band; Google's sits in the card on it. A listing
            // photo supports a personal one and should not outrank it.
            if let hero = heroPhoto {
                ZStack(alignment: .topTrailing) {
                    RexPhotoBand(url: hero)
                    if let card = cardPhoto {
                        RexHeaderThumbnail(url: card, category: category)
                            .padding(.trailing, RexHeaderMetrics.thumbTrailing)
                            .padding(.top, RexHeaderMetrics.photoThumbTop)
                    }
                }
                .frame(height: RexHeaderMetrics.photoBandHeight, alignment: .top)
            } else {
                ZStack(alignment: .topTrailing) {
                    RexBannerBand(category: category)
                    RexHeaderThumbnail(url: item.image_url, category: category)
                        .padding(.trailing, RexHeaderMetrics.thumbTrailing)
                        .padding(.top, RexHeaderMetrics.thumbTop)
                }
                // The cover hangs past the band's bottom edge; without this the
                // stack clips it at the fold.
                .frame(height: RexHeaderMetrics.bandHeight, alignment: .top)
            }
            }
            // Oct 13 — "alignment too close to the left-hand side, need to
            // maintain the margins." The header this replaced ended with one
            // .padding(16) around the whole stack, which is what gave Rex'd by,
            // the rating row and everything else their margin. I put the
            // padding on the title block alone, so only the title block kept
            // it. The band bleeds back out instead.
            .padding(.horizontal, -16)
            .padding(.top, -16)

            VStack(alignment: .leading, spacing: 0) {
                RexCategoryPill(category: category)

                Text(item.title)
                    .font(RexFont.display(min(34, titleSize(for: item.title))))
                    .lineSpacing(-4)
                    .foregroundStyle(RexColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                // The byline is the one place a voice belongs: an author, a
                // cuisine and a neighbourhood, a year and a run of seasons.
                if let summary = standfirst(item: item, category: category) {
                    Text(summary)
                        .font(RexFont.editorial(19))
                        .foregroundStyle(RexColor.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                if let address = item.address, !address.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "mappin").font(.system(size: 12))
                        Text(address)
                            .font(RexFont.text(14))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.top, 9)
                }
            }
            .padding(.top, 10)
            // Oct 14 — "need a bigger gap here." The title block ran straight
            // into Rex'd by with nothing between them, so a sentence about the
            // programme and a list of people reading as one paragraph.
            .padding(.bottom, 18)

            savedByRow
            wantedByRow
            ticketsSection
                // Oct 14 — "need more space between Gemma's profile picture
                // and the line below." The name under the last face and the
                // row of buttons were touching, so a person and a control read
                // as one stack.
                .padding(.bottom, 4)


            // Oct 4 — "the Google reviews line is corrupted on place cards."
            // It wasn't corrupted, it was crushed: this was one HStack holding
            // the rating, the Google score and up to three buttons, and SwiftUI
            // answers an overfull HStack by shrinking every child until the
            // words inside break — "Obsessed" across two lines, "Google" down
            // the side a letter at a time. Each item keeps its natural width
            // now and the row scrolls, the same fix the feed card's tag row
            // needed.
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RexSpacing.md) {
                if !recs.isEmpty {
                    HStack(spacing: 6) {
                        if recs.count == 1 {
                            RexRatingBadge(raw: recs[0].rating)
                        } else {
                            RexRatingAverageBadge(ratings: recs.map { $0.rating })
                        }
                        // The count used to live here too; the row of faces
                        // above now says it, and saying it twice is noise.

                        // Google's own score has been stored on every place
                        // picked from search since the beginning and has
                        // never once been shown. Clearly marked as Google's,
                        // so it can't be mistaken for what friends thought.
                        if let googleRating = item.google_rating, googleRating > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").font(.system(size: 9))
                                Text(String(format: "%.1f", googleRating))
                                    .font(.system(size: 12, weight: .semibold))
                                if let count = item.google_rating_count, count > 0 {
                                    Text("(\(count))").font(.system(size: 11))
                                }
                                Text("Google").font(.system(size: 10))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(RexColor.mutedForeground)
                            .padding(.horizontal, RexSpacing.sm)
                            .padding(.vertical, 4)
                            .background(RexColor.badgeBackground)
                            .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 0)

                // Oct 12 — "include the website for restaurants and booking
                // links as well, as per Google."
                //
                // Google tells us a place takes reservations but keeps the
                // booking URL behind its own Place Actions product, which this
                // key can't reach. So this says what is true — it books — and
                // sends you to the listing where the Reserve button is.
                // Building an OpenTable search URL out of the name would land
                // people on the wrong restaurant often enough to be worse than
                // not offering it at all.
                //
                // First in the row on purpose: on a restaurant you have
                // decided on, booking is the thing you came to do.
                // Oct 14 — "Book goes to the website when there is one, and the
                // Google listing when there isn't."
                //
                // Google tells us a place takes bookings and will not tell us
                // where — that URL is behind its separate Place Actions
                // product, which this key cannot reach. So the button goes to
                // the best page we do have. A restaurant's own site usually
                // has booking on the front, and is one tap shorter than the
                // listing; the listing is the fallback, where Reserve is at
                // least always there.
                if let details = effectivePlaceDetails, details.takesBookings,
                   let link = details.websiteURL ?? details.googleMapsURL,
                   let url = URL(string: link) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.plus").font(.system(size: 12))
                            Text("Book").font(RexFont.text(12, weight: .semibold))
                        }
                        .foregroundStyle(RexColor.primaryForeground)
                        .padding(.horizontal, RexSpacing.md)
                        .padding(.vertical, 6)
                        .background(RexColor.primary)
                        .clipShape(Capsule())
                    }
                }

                if let viewOnMap, category == .place || category == .event {
                    Button {
                        viewOnMap(itemId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "map").font(.system(size: 12))
                            Text("View on map").font(RexFont.text(12, weight: .semibold))
                        }
                        .foregroundStyle(RexColor.primary)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(RexColor.primary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if let link = item.link_url, let url = URL(string: link), url.scheme?.hasPrefix("http") == true {
                    // Opens in Safari. Labelled with the site's own name so
                    // it's clear where you're going. Sept 21 — goes through
                    // RexOutboundLink, which asks for tracking permission the
                    // first time and only then routes it via the affiliate
                    // redirect; a refusal opens the plain link just as fast.
                    RexOutboundLinkButton(url: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 12))
                            Text(category == .other || category == .list ? "View product" : "Visit website")
                                .font(RexFont.text(12, weight: .semibold))
                        }
                        .foregroundStyle(RexColor.primary)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(RexColor.primary, lineWidth: 1))
                    }
                }

            }
            // Each pill keeps its natural width; the row scrolls if they
            // don't all fit.
            .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(16)
    }

    /// Google's details for this place, whichever way they arrived: the
    /// columns cached on the item, or the fetch this visit just made.
    private var effectivePlaceDetails: RexPlaceDetails? {
        if let placeDetails { return placeDetails }
        guard let item else { return nil }
        let cached = RexPlaceDetails(
            summary: item.summary,
            openingHours: item.opening_hours ?? [],
            photoURLs: item.google_photo_urls ?? [],
            rating: item.google_rating,
            ratingCount: item.google_rating_count,
            websiteURL: item.link_url
        )
        return cached.isEmpty ? nil : cached
    }

    /// Fetches Place Details at most once per place, ever — the guard here is
    /// the whole cost control, so it stays strict: a Google place id, nothing
    /// cached, and nobody has asked in the last ninety days.
    private func loadPlaceDetails(_ item: RexItem) async {
        let category = RexCategory(rawType: item.type)
        guard category == .place || category == .event,
              item.external_source == "google_places",
              let placeId = item.external_id, !placeId.isEmpty
        else { return }

        if let fetchedAt = item.details_fetched_at,
           let date = ISO8601DateFormatter.rexDate(from: fetchedAt),
           date.timeIntervalSinceNow > -90 * 24 * 60 * 60 {
            return
        }

        guard let fetched = await RexSearch.placeDetails(placeId: placeId), !fetched.isEmpty else { return }
        placeDetails = fetched
        await RexAPI.shared.saveItemPlaceDetails(itemId: item.id, details: fetched)
    }

    /// Oct 3 — "please can we pull photos from Google?" Google's own photos of
    /// the place, swipeable. Friends' photos keep their own carousel further
    /// down: a picture someone you know took there is worth more than the
    /// listing's, so the two don't get mixed into one undifferentiated reel.
    /// Where you can watch it tonight, on something you already pay for.
    ///
    /// Logos rather than names alone: these are brands people recognise at a
    /// glance and read as words only slowly. The row scrolls rather than
    /// wrapping, so a title on six services doesn't push the reviews down.
    /// Books, films and TV have a portrait cover; a place has a photograph.
    /// Podcasts are square artwork, so they take the square.
    /// Oct 14 — the photograph across the band: one somebody who went there
    /// uploaded. Nil when nobody has, which is when the category's texture
    /// takes the band instead.
    private var heroPhoto: String? {
        communityPhotoURLs.first
    }

    /// The card resting on it: Google's picture of the place, falling back to
    /// whatever the item itself carries. Never the same image as the band —
    /// the same photograph twice is worse than one.
    private var cardPhoto: String? {
        let google = (item?.google_photo_urls ?? []).first
        let candidate = google ?? item?.image_url
        return candidate == heroPhoto ? nil : candidate
    }

    /// Archivo Black is wide, and a 44pt title that runs to five lines stops
    /// being a title. Long names step down rather than wrap forever; short
    /// ones keep the full size, which is the whole reason for the face.
    /// Oct 14 — "font size can come down quite a bit on both the title and
    /// the description underneath." It was set against the mockup, where a
    /// title sits alone on a wide artboard; on a phone, under a band, above a
    /// row of faces, 44pt of Archivo Black is shouting.
    private func titleSize(for title: String) -> CGFloat {
        switch title.count {
        case ..<18: return 34
        case ..<30: return 30
        case ..<48: return 26
        default: return 23
        }
    }

    private var coverIsPortrait: Bool {
        let category = RexCategory(rawType: item?.type)
        return category == .book || category == .movie || category == .tv
    }

    @ViewBuilder
    private var watchOnSection: some View {
        if let details, !details.watchOn.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                // Oct 14 — "it's the Watch on that is the problem." The
                // heading had no horizontal padding while the chips inside the
                // scroller did, so the label sat against the screen edge and
                // the thing it labels began 16pt to its right. The padding is
                // on the scroller's contents rather than the scroller so chips
                // can still run off the edge as you swipe; the heading needs
                // its own.
                Text("Watch on")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        ForEach(details.watchOn) { provider in
                            HStack(spacing: 6) {
                                if let logo = provider.logoURL, let url = URL(string: logo) {
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFit()
                                        } else {
                                            RexColor.muted
                                        }
                                    }
                                    .frame(width: 22, height: 22)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                }
                                Text(provider.name)
                                    .font(RexFont.text(12, weight: .semibold))
                                    .foregroundStyle(RexColor.foreground)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, RexSpacing.sm)
                            .padding(.vertical, 5)
                            .background(RexColor.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(RexColor.border, lineWidth: 1))
                        }

                        // TMDB's data comes from JustWatch, whose terms ask
                        // that you link to their page rather than deep-link
                        // each service. It is also the honest place to send
                        // somebody whose service isn't listed.
                        if let link = details.watchLink, let url = URL(string: link) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Text("All ways").font(RexFont.text(12, weight: .semibold))
                                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(RexColor.primary)
                                .padding(.horizontal, RexSpacing.sm)
                                .padding(.vertical, 5)
                                .background(RexColor.badgeBackground)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, RexSpacing.lg)
        }
    }

    @ViewBuilder
    private var googlePhotosSection: some View {
        let urls = effectivePlaceDetails?.photoURLs ?? []
        if urls.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(urls.dropFirst(), id: \.self) { urlString in
                            GoogleSafeAsyncImage(url: URL(string: urlString)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RexColor.muted
                            }
                            .frame(width: 150, height: 110)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Text("Photos from Google")
                    .font(.system(size: 10))
                    .foregroundStyle(RexColor.placeholder)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, RexSpacing.sm)
        }
    }

    /// Opening times. Today's line is the one anybody actually wants, so it's
    /// the one on screen; the rest of the week is a tap away rather than seven
    /// lines of small print on every place page.
    @ViewBuilder
    private var openingHoursSection: some View {
        if let details = effectivePlaceDetails, !details.openingHours.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.snappy) { hoursExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock").font(.system(size: 12))
                        Text(details.todayHours ?? "Opening times")
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Image(systemName: hoursExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(RexColor.foreground.opacity(0.9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if hoursExpanded {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(details.openingHours, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                    .padding(.leading, 18)
                }
            }
        }
    }

    /// Oct 5 — "for the book page (and TV and film), can we please go back to
    /// having the image as a thumbnail next to the title and author. I
    /// basically want to compress the info so that you see the reviews in the
    /// screen you open."
    ///
    /// Yesterday every page opened with a picture across the width. For a
    /// place that is right — you decide whether to go by looking at it. For a
    /// book it isn't: the cover is decoration you have usually already seen,
    /// and 180pt of it pushes the only thing you came for below the fold.
    ///
    /// So the hero belongs to the categories whose picture is the information:
    /// a place, an event, a recipe. Everything else goes back to the cover
    /// beside the title, which costs 76pt instead of 180 and leaves the first
    /// review on the opening screen.
    private func usesHeroImage(category: RexCategory) -> Bool {
        category == .place || category == .event || category == .recipe
    }

    /// Whether the hero image is landscape and should fill the frame, or
    /// portrait and should sit in the middle of it.
    private func heroFills(category: RexCategory) -> Bool {
        if category == .place || category == .event || category == .recipe { return true }
        // A film or programme only fills when TMDB actually gave us a
        // backdrop; without one we are back to the poster, which is portrait.
        return (category == .movie || category == .tv) && details?.backdropURL != nil
    }

    /// One line saying what it is, under the title. Google's description for a
    /// place; for everything else the opening of the synopsis, which is the
    /// nearest equivalent — with the whole thing still further down the page.
    private func standfirst(item: RexItem, category: RexCategory) -> String? {
        if category == .place || category == .event {
            return placeSummary(item: item, category: category)
        }
        // Oct 14 — this used to be the first sentence of the synopsis, and the
        // synopsis itself sits a few inches below under the facts strip. So
        // "Alice is devastated when her best friend Steve starts dating her
        // 26-year-old daughter Izzy" was on the page twice, once in Cormorant
        // and once in DM Sans, which reads as a mistake because it is one.
        //
        // The byline says what kind of thing this is and when — the line you
        // would say after the title out loud. The plot has its own place.
        // `facts` is already the line this wants — "3 seasons", "1h 58m ·
        // Drama, Romance", "384 pages" — assembled wherever the catalogue was
        // read. An author or a creator goes in front of it where we have one.
        var parts: [String] = []
        if let who = item.subtitle?.trimmingCharacters(in: .whitespaces), !who.isEmpty {
            parts.append(who)
        }
        if let facts = details?.facts?.trimmingCharacters(in: .whitespaces), !facts.isEmpty {
            parts.append(facts)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// The hard facts under the standfirst: hours for a place, certificate and
    /// running time for a film, author and year for a book.
    @ViewBuilder
    private func heroFacts(item: RexItem, category: RexCategory) -> some View {
        if category == .place || category == .event {
            openingHoursSection
        } else {
            HStack(spacing: RexSpacing.sm) {
                if let certificate = details?.certificate {
                    Text(certificate)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(RexColor.mutedForeground.opacity(0.6), lineWidth: 1)
                        )
                }
                let line = [item.subtitle, details?.facts]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " \u{00B7} ")
                if !line.isEmpty {
                    Text(line)
                        .font(.system(size: 12.5))
                        .foregroundStyle(RexColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func categoryBadge(_ category: RexCategory) -> some View {
        HStack(spacing: 3) {
            Image(systemName: category.symbol).font(.system(size: 9))
            Text(category.label.uppercased()).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(RexColor.primary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RexColor.primary.opacity(0.12))
        .clipShape(Capsule())
    }

    /// The item's own picture if it has one, otherwise the best photo anybody
    /// has attached to a take on it — which is usually a better photograph of
    /// the place than the catalogue's, because a friend took it there.
    /// The portrait cover, for the categories whose only image is one.
    private var portraitHeroURL: URL? {
        guard let urlString = item?.image_url, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    private var heroImageURL: URL? {
        // A film's backdrop beats its poster for a full-width frame; the
        // poster is portrait and would be cropped to a band of somebody's
        // chin.
        if let backdrop = details?.backdropURL, let url = URL(string: backdrop) { return url }
        if let urlString = item?.image_url, let url = URL(string: urlString) { return url }
        if let urlString = effectivePlaceDetails?.photoURLs.first, let url = URL(string: urlString) { return url }
        return communityPhotoURLs.first.flatMap(URL.init(string:))
    }

    @ViewBuilder
    private func heroImage(item: RexItem, category: RexCategory) -> some View {
        Group {
            if !heroFills(category: category), let url = portraitHeroURL {
                // A portrait cover, floated rather than stretched. The tinted
                // ground is the category's own colour at low opacity, which
                // keeps a shelf of book pages from all looking identical
                // without needing to sample the artwork.
                GoogleSafeAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(category.placeholderImageName).resizable().aspectRatio(contentMode: .fit)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(category.tintColor.opacity(0.18))
            } else if let url = heroImageURL {
                // GoogleSafeAsyncImage rather than AsyncImage: a Places photo
                // URL needs the bundle-id header, and without it loads as a
                // permanently blank box with no error.
                GoogleSafeAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RexColor.muted
                }
            } else {
                // No photograph anywhere: the drawn placeholder, sized down
                // and centred rather than stretched across the full width,
                // which is how the dino ends up looking like a mistake.
                Image(category.placeholderImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .background(RexColor.muted)
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// One line saying what the thing actually is — the sub-category and the
    /// town. Built from what's already stored rather than fetched: Google's
    /// own one-liner would read better ("smash burgers"), but it's a billed
    /// Place Details call per view, so that's a decision to take separately.
    private func placeSummary(item: RexItem, category: RexCategory) -> String? {
        // Google's own line first when we have it — "smash burgers" beats
        // "Restaurant · Streatham", which is what the fallback below builds.
        if let summary = effectivePlaceDetails?.summary?.trimmingCharacters(in: .whitespaces),
           !summary.isEmpty {
            if let locality = locality(from: item.address) {
                return "\(summary) \u{00B7} \(locality)"
            }
            return summary
        }
        var parts: [String] = []
        if let genre = item.genre?.trimmingCharacters(in: .whitespaces), !genre.isEmpty {
            parts.append(genre)
        }
        if let subtitle = item.subtitle?.trimmingCharacters(in: .whitespaces), !subtitle.isEmpty {
            parts.append(subtitle)
        }
        if let locality = locality(from: item.address) { parts.append(locality) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// "180 Franciscan Rd, London SW17 8HG, UK" -> "London". Addresses here
    /// are Google-formatted, so the town is the second-to-last component
    /// before the country, with the postcode trimmed off.
    private func locality(from address: String?) -> String? {
        guard let address else { return nil }
        let parts = address.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let candidate = parts[parts.count - 2]
        // Drop a trailing postcode ("London SW17 8HG" -> "London").
        let words = candidate.components(separatedBy: " ")
        let town = words.prefix { word in
            !word.contains(where: \.isNumber)
        }
        let result = town.joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    /// Oct 3 — "a swipeable 'saved by' row of clickable profile pictures;
    /// how many people have Rex'd it". The faces were buried under the takes
    /// at the bottom of the page; who has been is the fastest answer to
    /// "should I go", so it moves up to sit under the title.
    /// Whoever Rex'd it first, then everyone since. `recs` comes back
    /// newest-first from fetchRecommendations(forItem:), and the person who
    /// found a place before anyone else is the one worth leading with.
    /// Oct 12 — "How is Phoebe recommending this place twice and appearing in
    /// the REX list twice?"
    ///
    /// Because on 4 October we deliberately allowed a second Rex of the same
    /// place — going back two years later and feeling differently is worth
    /// recording. This strip was never told. It drew one face per Rex, so the
    /// second visit arrived as a second Phoebe, and the heading counted rows
    /// and called them people.
    ///
    /// One face per person, keeping their earliest Rex: that is the row the
    /// "1" badge is about, and it is the one that decides where they sit in a
    /// strip ordered by who got there first. Both takes still appear in full
    /// further down the page, which is where a second visit is actually
    /// interesting.
    private var orderedRexers: [FeedRecommendation] {
        var seen = Set<String>()
        return recs.reversed().filter { seen.insert($0.user_id).inserted }
    }


    /// Oct 5 — "reorder book, film and TV pages so reviews come higher up
    /// (cast etc should be below reviews)."
    ///
    /// The cast sat inside the details block in the header, which put a row of
    /// actors above what your friends thought of the film. On REX the friends
    /// are the point and everything else is context, so the context goes
    /// under them.
    @ViewBuilder
    private var castSection: some View {
        if let details, !details.cast.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cast")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(RexColor.mutedForeground)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.md) {
                        ForEach(details.cast) { member in
                            // Oct 15 — "like authors, can we make the cast
                            // clickable? So you can see what else they've
                            // been in?" Only when TMDB gave us their id: a
                            // name alone is not something to look a person
                            // up by, and a tile that goes nowhere is worse
                            // than one that was never tappable.
                            CastTile(
                                member: member,
                                fromTitle: item?.title
                            ) {
                            VStack(spacing: 4) {
                                AsyncImage(url: member.imageURL.flatMap(URL.init(string:))) { phase in
                                    if let image = phase.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        RexColor.muted.overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(RexColor.placeholder)
                                        )
                                    }
                                }
                                .frame(width: 54, height: 54)
                                .clipShape(Circle())
                                Text(member.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(RexColor.foreground)
                                    .lineLimit(1)
                                if let role = member.role {
                                    Text(role)
                                        .font(.system(size: 10))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 68)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, RexSpacing.lg)
        }
    }


    /// Oct 5 — "if someone posts a small chain restaurant, can we Rex the
    /// whole chain but make it clear where the actual Rex was… and if two
    /// people Rex different venues of the same chain, can we flag that?"
    ///
    /// Nobody Rexes anywhere they haven't been. Instead a place knows its
    /// siblings, so this can say how many people rate the chain and where —
    /// which is the question underneath both halves of the ask. A branch
    /// nobody has been to is listed plainly as that, and tapping it opens the
    /// branch rather than claiming anything about it.
    @ViewBuilder
    private var chainSection: some View {
        if !chainBranchesHere.isEmpty || !chainBranchesElsewhere.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                Text(chainHeadline)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(RexColor.mutedForeground)

                ForEach(chainBranchesHere, id: \.id) { branch in
                    NavigationLink(value: branch.id) {
                        chainRow(title: branch.title, detail: branch.address, rexd: true)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(chainBranchesElsewhere, id: \.id) { branch in
                    Button {
                        addingBranch = branch
                    } label: {
                        chainRow(title: branch.title, detail: branch.address, rexd: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, RexSpacing.lg)
        }
    }

    private var chainHeadline: String {
        let known = chainBranchesHere.count + 1
        if chainBranchesHere.isEmpty { return "Other branches" }
        return "This chain \u{2014} \(known) branch\(known == 1 ? "" : "es") Rex'd by your friends"
    }

    private func chainRow(title: String, detail: String?, rexd: Bool) -> some View {
        HStack(spacing: RexSpacing.sm) {
            Image(systemName: rexd ? "mappin.circle.fill" : "mappin.circle")
                .font(.system(size: 15))
                .foregroundStyle(rexd ? RexColor.primary : RexColor.mutedForeground)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(RexFont.text(13.5, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(1)
                Text(rexd ? (detail ?? "") : "Nobody's been to this one yet")
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: rexd ? "chevron.right" : "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .padding(RexSpacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .rexCard()
    }

    /// Branches already in REX, and branches Google knows about that nobody
    /// has Rex'd. Fetched only for a place that belongs to a chain, so an
    /// ordinary restaurant costs nothing.
    private func loadChain(_ item: RexItem) async {
        guard let key = item.chain_key, !key.isEmpty else { return }
        chainBranchesHere = await RexAPI.shared.chainSiblings(chainKey: key, excludingItemId: item.id)
        let known = Set(chainBranchesHere.map { $0.title.lowercased() } + [item.title.lowercased()])
        let found = await RexSearch.chainBranches(
            name: item.title,
            key: key,
            excludingPlaceId: item.external_id
        )
        chainBranchesElsewhere = found.filter { !known.contains($0.title.lowercased()) }
    }

    /// Who means to go, as distinct from who has been. Deliberately its own
    /// row under the Rexers rather than mixed in with them: "three friends
    /// rate this" and "three friends fancy it" are different sentences, and
    /// running them together would make the second borrow the first's weight.
    ///
    /// Yourself included, because your own want is a fact about the thing and
    /// leaving it out would make the count disagree with the bookmark.
    /// Oct 12 — "offer notifications for upcoming ticket sales for events."
    ///
    /// Only on events, and it has two shapes. With an on-sale time it says
    /// when, and offers to tell you half an hour before. Without one it asks
    /// for the time, because nothing else can supply it — no catalogue
    /// publishes ticket releases, so an empty state here is an invitation
    /// rather than a dead end, and anyone can fill it in: when Glastonbury
    /// tickets drop is a fact about the event, not about whoever added it.
    @ViewBuilder
    private var ticketsSection: some View {
        if isEvent {
            VStack(alignment: .leading, spacing: 8) {
                if let onSale = ticketsOnSale {
                    Text("Tickets on sale")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.3)
                        .foregroundStyle(RexColor.mutedForeground)

                    Text(onSale.formatted(date: .abbreviated, time: .shortened))
                        .font(RexFont.display(17, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)

                    Button {
                        if reminderSet {
                            editingReminderTimings = true
                        } else {
                            Task { await toggleTicketReminder() }
                        }
                    } label: {
                        HStack(spacing: RexSpacing.sm) {
                            Image(systemName: reminderSet ? "bell.fill" : "bell")
                            Text(reminderSet ? reminderSummary : "Remind me")
                                .font(RexFont.text(14, weight: .semibold))
                        }
                        .padding(.horizontal, RexSpacing.md)
                        .padding(.vertical, 10)
                        .background(reminderSet ? RexColor.badgeBackground : RexColor.primary)
                        .foregroundStyle(reminderSet ? RexColor.primary : RexColor.primaryForeground)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    let others = ticketReminderPeople.filter { $0.id != RexAPI.shared.currentUserId }
                    if !others.isEmpty {
                        Text(others.count == 1
                             ? "\(others[0].display_name ?? others[0].username) is waiting for these too"
                             : "\(others.count) friends are waiting for these too")
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                    }

                    Button("Change the on-sale time") {
                        draftOnSaleDate = onSale
                        editingOnSaleDate = true
                    }
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
                } else {
                    Button {
                        draftOnSaleDate = Date()
                        editingOnSaleDate = true
                    } label: {
                        HStack(spacing: RexSpacing.sm) {
                            Image(systemName: "bell.badge")
                            Text("Know when tickets go on sale? Add it")
                                .font(RexFont.text(14, weight: .medium))
                        }
                        .foregroundStyle(RexColor.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RexSpacing.md)
            .rexCard()
        }
    }

    /// Oct 13 — Joe: "I would love to have my library of books in a ranking
    /// order… you rank it against your other books."
    ///
    /// Only on the categories where "better than" is a real question — a book
    /// against a book, a film against a film. A restaurant against a podcast
    /// is not something anybody has an opinion about, so those pages say
    /// nothing rather than offering a question with no answer.
    @ViewBuilder
    private var rankRow: some View {
        if isRankable, recs.contains(where: { $0.user_id == RexAPI.shared.currentUserId }) {
            HStack(spacing: RexSpacing.sm) {
                if let myRank {
                    NavigationLink(value: RankedLibraryRoute(
                        category: item?.type ?? "", userId: nil, name: nil
                    )) {
                        HStack(spacing: 7) {
                            Text("#\(myRank.position)")
                                .font(RexFont.display(17))
                                .foregroundStyle(RexColor.primary)
                            Text("of your \(myRank.total)")
                                .font(RexFont.text(13))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                        .padding(.horizontal, RexSpacing.md)
                        .padding(.vertical, 8)
                        .background(RexColor.badgeBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button("Move it") { activeSheet = .rank }
                        .font(RexFont.text(13, weight: .semibold))
                        .foregroundStyle(RexColor.primary)
                } else {
                    Button {
                        activeSheet = .rank
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "list.number")
                                .font(.system(size: 12, weight: .semibold))
                            // Oct 14 — "can we rename this 'rank it'." The
                            // long version explained the mechanic; the short
                            // one is what the button does.
                            Text("Rank it")
                                .font(RexFont.text(13, weight: .semibold))
                        }
                        .padding(.horizontal, RexSpacing.md)
                        .padding(.vertical, 8)
                        .background(RexColor.badgeBackground, in: Capsule())
                        .foregroundStyle(RexColor.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            // Last thing on the page now, so it needs room above it rather
            // than the hairline gap it had as one row among several.
            .padding(.top, RexSpacing.lg)
            .padding(.bottom, RexSpacing.md)
        }
    }

    /// Ordering only makes sense within a kind, and only for kinds people
    /// actually compare. Trips, lists and blasts are not things you rank.
    private var isRankable: Bool {
        [.book, .movie, .tv, .podcast, .recipe].contains(RexCategory(rawType: item?.type))
    }

    private func loadMyRank() async {
        guard isRankable, let type = item?.type else { myRank = nil; return }
        let ordering = await RexAPI.shared.fetchRanking(category: type) ?? []
        if let index = ordering.firstIndex(where: { $0.item_id == itemId }) {
            myRank = (index + 1, ordering.count)
        } else {
            myRank = nil
        }
    }

    @ViewBuilder
    private var wantedByRow: some View {
        if !wanters.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(wanters.count == 1 ? "Wants to try" : "\(wanters.count) want to try")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(RexColor.mutedForeground)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.md) {
                        ForEach(wanters) { person in
                            let name = person.display_name ?? person.username
                            NavigationLink(value: UserProfileRoute(userId: person.id, name: name)) {
                                // Oct 14 — "can we fix the alignment on these?
                                // They should all start from the same point on
                                // the left." A centred column insets its avatar
                                // by half the difference between the frame and
                                // the picture, so the first face sat eight
                                // points right of the label above it — and the
                                // Rex'd by row, with a bigger avatar in a wider
                                // frame, sat seven points off in its own way.
                                // Leading, same width in both rows, so every
                                // left edge on the page is one line.
                                VStack(alignment: .leading, spacing: 4) {
                                    UserAvatarView(url: person.avatar_url, name: name, size: 34)
                                    Text(name.components(separatedBy: " ").first ?? name)
                                        .font(.system(size: 10))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .lineLimit(1)
                                }
                                .frame(width: 58, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            // No gutter of its own: header(item:) already puts 16 around the
            // whole stack, and adding a second here is what set this row 16
            // points in from the rating, the rank pill and the title above it.
            .padding(.top, RexSpacing.xs)
        }
    }

    @ViewBuilder
    private var savedByRow: some View {
        if !recs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(orderedRexers.count == 1 ? "Rex\u{2019}d by" : "Rex\u{2019}d by \(orderedRexers.count) people")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(RexColor.mutedForeground)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.md) {
                        // Oct 3 — "the first person to Rex something should
                        // have a little number one next to it and on the left
                        // of the thumbnails of profile pictures so that there
                        // is an incentive to be the 1st to Rex something."
                        //
                        // `recs` arrives newest-first, so the first to Rex it
                        // is the last row; drawn first here, with the badge.
                        ForEach(orderedRexers) { rec in
                            let name = rec.profiles?.display_name ?? rec.profiles?.username ?? "Someone"
                            let isFirst = rec.id == orderedRexers.first?.id && orderedRexers.count > 1
                            NavigationLink(value: UserProfileRoute(userId: rec.user_id, name: name)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    UserAvatarView(url: rec.profiles?.avatar_url, name: name, size: 44)
                                        .overlay(alignment: .topLeading) {
                                            if isFirst {
                                                Text("1")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(RexColor.primaryForeground)
                                                    .frame(width: 17, height: 17)
                                                    .background(RexColor.primary, in: Circle())
                                                    .overlay(Circle().stroke(RexColor.background, lineWidth: 1.5))
                                                    .offset(x: -3, y: -3)
                                            }
                                        }
                                    Text(name.components(separatedBy: " ").first ?? name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .lineLimit(1)
                                }
                                .frame(width: 58, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.bottom, 2)
                }
            }
        }
    }

    /// #121 — every photo anyone's attached to a take on this item, pooled
    /// into one swipeable carousel. Most-recent-take-first, since `recs`
    /// already comes back ordered that way (fetchRecommendations(forItem:)).
    /// A single Rex's own photos already get this treatment on its card
    /// (RecommendationCardView's PhotoCarouselView) — this is the same
    /// component, just fed everyone's photos on this item at once rather
    /// than one person's.
    private var communityPhotoURLs: [String] {
        recs.flatMap { $0.photo_urls ?? ($0.photo_url.map { [$0] } ?? []) }
    }

    @ViewBuilder
    private var communityPhotosSection: some View {
        if !communityPhotoURLs.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                Text("Photos from friends")
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.horizontal, 16)
                PhotoCarouselView(urls: communityPhotoURLs, cornerRadius: RexRadius.card)
                    .padding(.horizontal, 16)
            }
            .padding(.top, RexSpacing.sm)
        }
    }

    // #126 — recipe_text saved correctly on post; this is the other half
    // of the fix, actually showing it. Reuses RecipeEditorView's own
    // Ingredients/Method splitter so a pasted or photo-auto-populated
    // recipe reads back the same shape it was reviewed in before posting.
    @ViewBuilder
    private func recipeSection(item: RexItem) -> some View {
        if let text = item.recipe_text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = RexRecipe.parse(text)
            VStack(alignment: .leading, spacing: 12) {
                if !parsed.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ingredients")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(RexColor.foreground)
                        ForEach(parsed.ingredients, id: \.self) { line in
                            Text("\u{2022} \(line)")
                                .font(.system(size: 13))
                                .foregroundStyle(RexColor.foreground)
                        }
                    }
                }
                if !parsed.method.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Method")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(RexColor.foreground)
                        ForEach(Array(parsed.method.enumerated()), id: \.offset) { index, line in
                            Text("\(index + 1). \(line)")
                                .font(.system(size: 13))
                                .foregroundStyle(RexColor.foreground)
                        }
                    }
                }
                // A recipe that didn't parse into recognizable sections —
                // pasted as one freeform block — still deserves to show up
                // rather than silently vanishing.
                if parsed.ingredients.isEmpty && parsed.method.isEmpty {
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(RexColor.foreground)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RexColor.card)
        }
    }

    /// Oct 14 — "don't need any of this section, you should only be able to
    /// update your take from the edit three dots."
    ///
    /// My last pass got this half right and half backwards. It built the card
    /// she asked for and then left the rating picker showing whenever you
    /// weren't editing — which is always — so the form she wanted gone sat
    /// directly above the card that replaced it.
    ///
    /// Once you have written a take, this is a take: the card, and a menu on
    /// it. The heading, the want chip, the five buttons and the Update button
    /// are all the machinery of writing one, and there is nothing to write.
    /// They come back whole when you ask to edit, and when there is nothing
    /// there yet — which is the only time a form is the right thing on screen.
    /// Oct 14 — "why are the spaces between these boxes not even?"
    ///
    /// Because your own review was in a section of its own, and both sections
    /// pad themselves by 16 — so the gap between the last friend's card and
    /// yours was 32 while the cards inside the list were 10 apart. Your card
    /// has moved into the list with everybody else's, where it reads as the
    /// one thing it is; this is now only the form for writing one.
    @ViewBuilder
    private var yourTakeSection: some View {
        if !showsMyTakeCard {
            VStack(alignment: .leading, spacing: 10) {
                takeEditor
            }
            .padding(16)
        }
    }

    /// Whether your review is on the page as a card rather than a form.
    private var showsMyTakeCard: Bool {
        guard let myRec, !isEditingNote else { return false }
        return !(myRec.note ?? "").isEmpty
    }

    /// What you wrote, in the shape a friend's take takes.
    private func myTakeCard(_ myRec: FeedRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    UserAvatarView(
                        url: myRec.profiles?.avatar_url,
                        name: myRec.profiles?.display_name ?? myRec.profiles?.username ?? "You",
                        size: 24
                    )
                    Text(myRec.profiles?.display_name ?? myRec.profiles?.username ?? "You")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                }
                Spacer()
                RexRatingBadge(raw: myRec.rating)
            }
            HStack(alignment: .top, spacing: RexSpacing.sm) {
                Text(linked: "\u{201C}\(myRec.note ?? "")\u{201D}")
                    .font(RexFont.text(15))
                    .foregroundStyle(RexColor.foreground.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Everything you can do to your own take lives here now.
                Menu {
                    Button {
                        note = myRec.note ?? ""
                        rating = myRec.rating
                        isEditingNote = true
                    } label: {
                        Label("Edit what I wrote", systemImage: "pencil")
                    }
                    Button {
                        activeSheet = .edit(myRec)
                    } label: {
                        Label("Edit the details", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        Task { await toggleWant() }
                    } label: {
                        Label(
                            wanted ? "Off the want-to-try list" : "Add to want-to-try",
                            systemImage: wanted ? "bookmark.slash" : "bookmark"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
            }

            // Oct 14 — "I now can't see comments under my reviews."
            //
            // When your take was rebuilt into the shape a friend's take
            // takes, it got the avatar, the quote and the badge but not the
            // strip underneath — so the likes and comments on your own Rex
            // were on the page for everybody else's and missing from yours,
            // and a comment somebody left you had nowhere to appear.
            Rectangle().fill(RexColor.divider).frame(height: 1).padding(.vertical, 4)
            LikesCommentsView(recommendationId: myRec.id)
        }
        .padding(12)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
    }

    /// Writing one, or changing one. The whole form, only when it is wanted.
    private var takeEditor: some View {
        VStack(alignment: .leading, spacing: 10) {

            Button {
                Task { await toggleWant() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: wanted ? "bookmark.fill" : "bookmark")
                    Text(wanted ? "On your want-to-try list" : "Want to try")
                }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(wanted ? RexColor.primary : RexColor.mutedForeground)
            }
            .buttonStyle(.plain)
            .disabled(isTogglingWant)

            RexRatingPicker(value: $rating)

            // Oct 14 — "bring back the emojis but only have the text box once
            // someone has clicked on an emoji."
            //
            // The emoji were never the problem; the form under them was. Five
            // faces above an empty box reads as a page demanding to be filled
            // in, and the question it is really asking — what did you make of
            // it — gets lost behind the work. Pick a face and the box arrives,
            // by which point writing something is a choice rather than a
            // prerequisite.
            if rating > 0 {
                TextField("What did you love about it?", text: $note, axis: .vertical)
                    .lineLimit(3...14)
                    .padding(12)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
                    .transition(.opacity.combined(with: .move(edge: .top)))

                Button(action: save) {
                    if isSaving {
                        ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                    } else {
                        Text(myRec != nil ? "Update" : "Post").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 46)
                .background(RexColor.primary)
                .foregroundStyle(RexColor.primaryForeground)
                .clipShape(Capsule())
                .disabled(isSaving)
            }
        }
        .animation(.snappy, value: rating > 0)
    }

    /// More by the same author, Goodreads-style — covers you can run your eye
    /// along rather than a list to read.
    ///
    /// The whole bibliography comes from OpenLibrary, so it includes books
    /// nobody here has touched; what makes it REX's rather than a catalogue is
    /// the count underneath. "2 Rex" means someone you know has read it and
    /// the cover is a door; no count means it's just a book that exists, and
    /// tapping offers to add it rather than opening a page that isn't there.
    @ViewBuilder
    private var moreByAuthorSection: some View {
        if RexCategory(rawType: item?.type) == .book, !moreByAuthor.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("More by \(primaryAuthor ?? "this author")")
                        .font(RexFont.display(18, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    Spacer(minLength: RexSpacing.sm)
                    if let author = primaryAuthor {
                        NavigationLink(value: AuthorRoute(author: author)) {
                            Text("See all")
                                .font(RexFont.text(13, weight: .semibold))
                                .foregroundStyle(RexColor.primary)
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: RexSpacing.md) {
                        ForEach(moreByAuthor) { book in
                            authorBookTile(book)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, RexSpacing.lg)
        }
    }

    private func authorBookTile(_ book: RexSearchHit) -> some View {
        let existing = authorBookItems[book.title.lowercased()]
        let count = existing.flatMap { authorBookRexCounts[$0.id] } ?? 0

        return Group {
            if let existing {
                NavigationLink(value: existing.id) { authorBookCard(book, rexCount: count) }
                    .buttonStyle(.plain)
            } else {
                authorBookCard(book, rexCount: 0)
            }
        }
    }

    private func authorBookCard(_ book: RexSearchHit, rexCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(RexColor.muted)
                if let cover = book.imageURL, let url = URL(string: cover) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "book").foregroundStyle(RexColor.mutedForeground)
                    }
                } else {
                    Image(systemName: "book").foregroundStyle(RexColor.mutedForeground)
                }
            }
            .frame(width: 92, height: 138)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(book.title)
                .font(RexFont.text(12.5, weight: .medium))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if rexCount > 0 {
                HStack(spacing: 3) {
                    Image("RexDinoLogo")
                        .resizable().scaledToFit().frame(width: 12, height: 12)
                    Text("\(rexCount) Rex")
                        .font(RexFont.text(11, weight: .medium))
                        .foregroundStyle(RexColor.primary)
                }
            } else {
                Text("Not Rex'd yet")
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        }
        .frame(width: 92, alignment: .leading)
    }

    /// A book's subtitle is its author list as OpenLibrary returned it; the
    /// first name is the one worth building a shelf around.
    private var primaryAuthor: String? {
        guard let subtitle = item?.subtitle, !subtitle.isEmpty else { return nil }
        return subtitle
            .components(separatedBy: " \u{00B7} ").first?
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces)
    }

    private func loadMoreByAuthor() async {
        guard RexCategory(rawType: item?.type) == .book,
              let author = primaryAuthor, !author.isEmpty else { return }

        async let catalogueTask = RexSearch.byAuthor(author)
        async let mineTask = RexAPI.shared.fetchBooksByAuthor(author)
        let catalogue = (try? await catalogueTask) ?? []
        let mine = (try? await mineTask) ?? []

        // The book you are already looking at doesn't belong on its own shelf.
        let currentTitle = (item?.title ?? "").lowercased()
        moreByAuthor = catalogue.filter { $0.title.lowercased() != currentTitle }.prefix(12).map { $0 }

        authorBookItems = Dictionary(
            mine.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { a, _ in a }
        )
        authorBookRexCounts = (try? await RexAPI.shared.fetchRexCounts(itemIds: mine.map(\.id))) ?? [:]
    }

    /// Public Google rating, deliberately after "What friends say" — friends
    /// lead, the crowd is secondary. Sept 29: the rating card is now a way
    /// through to the Google listing rather than a dead end, and everything
    /// that isn't a place gets the nearest equivalent.
    @ViewBuilder
    private var elsewhereSection: some View {
        let link = RexExternalLink.forItem(item)
        let rating = item?.google_rating ?? 0

        if rating > 0 || link != nil {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if rating > 0 {
                    Text("On Google")
                        .font(RexFont.text(13, weight: .semibold))
                        .foregroundStyle(RexColor.mutedForeground)
                }

                if let link {
                    RexOutboundLinkButton(url: link.url) {
                        elsewhereCard(rating: rating, link: link)
                    }
                } else {
                    elsewhereCard(rating: rating, link: nil)
                }
                articlesSection
            }
            .padding(.top, RexSpacing.lg)
        } else {
            articlesSection.padding(.top, RexSpacing.lg)
        }
    }

    /// Oct 3 — "can the same be done with other articles from popular news
    /// sources if they feature?" Sits directly under "On Google" and reads the
    /// same way: somewhere else this has been written about, and the way
    /// through to it.
    @ViewBuilder
    private var articlesSection: some View {
        if !articles.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                Text("Written about")
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.top, RexSpacing.sm)

                // Oct 15 — the same force unwrap as the photo band, on a URL
                // out of a web search rather than a database. An article whose
                // address won't parse is one we can't open, so it isn't listed
                // rather than listed and fatal.
                ForEach(articles.compactMap { article in
                    URL(string: article.url).map { (article, $0) }
                }, id: \.0.id) { article, articleURL in
                    RexOutboundLinkButton(url: articleURL) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(article.publication.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(RexColor.primary)
                            Text(article.headline)
                                .font(RexFont.text(14, weight: .medium))
                                .foregroundStyle(RexColor.foreground)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            if let snippet = article.snippet, !snippet.isEmpty {
                                Text(snippet)
                                    .font(RexFont.text(12))
                                    .foregroundStyle(RexColor.mutedForeground)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(RexSpacing.md)
                        .rexCard()
                    }
                }
            }
        }
    }

    /// Only for places and events, and only once — a web search per item page
    /// view would be both slow and pointless, since the answer barely changes.
    private func loadArticles(_ item: RexItem) async {
        let category = RexCategory(rawType: item.type)
        guard category == .place || category == .event, articles.isEmpty else { return }
        articles = await RexSearch.articles(
            about: item.title,
            near: locality(from: item.address)
        )
    }

    /// One card whether or not there's a rating to put in it: a place with a
    /// Google score shows the score and the way through, a book shows only the
    /// way through, and both read as the same component.
    @ViewBuilder
    private func elsewhereCard(rating: Double, link: RexExternalLink.Destination?) -> some View {
        HStack(spacing: RexSpacing.sm) {
            if rating > 0 {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(RexColor.accent)
                Text(String(format: "%.1f", rating))
                    .font(RexFont.text(15, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                if let count = item?.google_rating_count, count > 0 {
                    Text("· \(count) reviews")
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            } else if let link {
                Image(systemName: link.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(RexColor.mutedForeground)
                Text(link.label)
                    .font(RexFont.text(15, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
            }

            Spacer(minLength: RexSpacing.sm)

            // Only where there's somewhere to go. A rating with no link keeps
            // the card but loses the affordance, rather than promising a tap
            // that does nothing.
            if link != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        }
        .padding(RexSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .rexCard()
    }

    /// Everybody else's Rex of this, and everybody's wants, in one list.
    ///
    /// Oct 14 — "show both want to try and Rexes in the same list in
    /// chronological order (when posted), but visually differentiate between
    /// want to try and actual Rex."
    ///
    /// The wants were only ever a row of faces before, so a want with a note
    /// on it showed neither the note nor the thread of comments underneath —
    /// which is how Phoebe's comments on her want became unreachable.
    ///
    /// Your own Rex is still excluded: it has its own editable box below, and
    /// showing it twice is what the 8 October change removed. Your own *want*
    /// does appear, because nothing else on the page carries what you wrote on
    /// it or the replies to it.
    private var theirs: [FeedRecommendation] {
        let mine = RexAPI.shared.currentUserId
        let merged = recs.filter { $0.user_id != mine } + wantPosts
        return merged.sorted { a, b in
            switch (a.createdDate, b.createdDate) {
            case let (x?, y?): return x > y
            // A row with an unparseable date sorts last rather than jumping
            // the queue, which is what comparing against a nil would do.
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return false
            }
        }
    }

    private var friendsSection: some View {
        // Oct 8 — "don't need 'loved' repeated, I can already see Phoebe's
        // review", and "make the pages where you have Rex'd the same as if
        // someone else has".
        //
        // Both are this: the list was every Rex including your own, and your
        // own was then shown again underneath in its own box. On a page you
        // had Rex'd you read yourself twice, and the page looked different
        // from one you hadn't — your review above the heading on one, below it
        // on the other.
        //
        // Other people's here, yours below in the box that can edit it. The
        // section disappears entirely when nobody else has said anything,
        // rather than printing "No takes yet" over your own review.
        VStack(alignment: .leading, spacing: 10) {
            // Oct 14 — "can we just have them all in one list, so not 'What
            // friends say' and 'Your take', just 'Reviews'."
            //
            // They were two sections because yours is editable and theirs is
            // not, which is a fact about the code and not about the page. A
            // reader sees one thing: what people said about this. So one
            // heading, with everybody's underneath it and yours last — the
            // place it has been since 8 October.
            //
            // Shown whenever there is anything to head, which now includes a
            // page where you are the only person who has said something.
            if !theirs.isEmpty || myRec != nil {
                Divider().overlay(RexColor.border)

                // Oct 15 — "can we rename this to 'What friends say' and have
                // your take at the bottom."
                //
                // Third name for this heading in two days, and this one is
                // the one that survives a want sitting under it: "Reviews"
                // and "Rexes" both describe the posts, and a want is neither.
                // What friends say describes the people, and everything in
                // the list is that — a Rex, a want, a note under either.
                // Yours stays last, below all of them.
                Text("What friends say")
                    .font(RexFont.display(20))
                    .foregroundStyle(RexColor.foreground)
                    .padding(.top, 6)
            }

            ForEach(theirs) { rec in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        // Whoever said it is as interesting as what they said.
                        NavigationLink(value: UserProfileRoute(
                            userId: rec.user_id,
                            name: rec.profiles?.display_name ?? rec.profiles?.username ?? "Someone"
                        )) {
                            HStack(spacing: 6) {
                                UserAvatarView(
                                    url: rec.profiles?.avatar_url,
                                    name: rec.profiles?.display_name ?? rec.profiles?.username ?? "?",
                                    size: 24
                                )

                                Text(rec.profiles?.display_name ?? rec.profiles?.username ?? "Someone")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(RexColor.foreground)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        // A want has no rating to show, so the chip goes where
                        // the badge would be and says what this is instead.
                        if rec.isWant {
                            HStack(spacing: 4) {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text("WANTS TO TRY")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.4)
                            }
                            .foregroundStyle(RexColor.mutedForeground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RexColor.badgeBackground, in: Capsule())
                        } else {
                            RexRatingBadge(raw: rec.rating)
                        }
                    }
                    if let note = rec.note, !note.isEmpty {
                        // Oct 12 — a link somebody pasted into their review is
                        // tappable here too, not only on the feed card.
                        Text(linked: "\u{201C}\(note)\u{201D}")
                            .font(.system(size: 13))
                            .foregroundStyle(RexColor.foreground.opacity(0.9))
                            .tint(RexColor.primary)
                    }

                    Rectangle().fill(RexColor.divider).frame(height: 1).padding(.vertical, 4)
                    LikesCommentsView(recommendationId: rec.id)
                }
                .padding(12)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                // Oct 14 — "do not like the dotted surround. I think it's fine
                // to just have the wants to try sticker." The chip already
                // says what the card is; the border was saying it twice.
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
            }

            // Yours last, in the same list and the same spacing. It is still
            // the only card you can edit — everything you can do to it lives
            // behind the three dots on it.
            if showsMyTakeCard, let myRec {
                myTakeCard(myRec)
            }
        }
        .padding(16)
    }

    /// Oct 8 — a book's facts as a two-column strip rather than a stack of
    /// labelled sections, and the synopsis under it at two lines.
    ///
    /// The old details section opened with a horizontal row of rating cards,
    /// one per source, and closed with "From Open Library" underneath the
    /// synopsis. Both are gone: "lose the Open Library thing for books" — it
    /// credits whichever catalogue the data came from, which for a book is a
    /// name no reader recognises or wants. Goodreads stays, in the header,
    /// because people do know it.
    @ViewBuilder
    private func catalogueFactsSection(item: RexItem) -> some View {
        if isLoadingDetails, details == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Looking it up\u{2026}").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
            }
            .padding(.top, RexSpacing.sm)
        } else {
            let facts = catalogueFacts(item: item)
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if !facts.isEmpty {
                    // Two columns, because every one of these is a short label
                    // and a shorter value — a full-width row each would be the
                    // same whitespace the stacked sections were.
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: RexSpacing.md),
                                  GridItem(.flexible(), spacing: RexSpacing.md)],
                        alignment: .leading,
                        spacing: 0
                    ) {
                        ForEach(facts, id: \.label) { fact in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(fact.label)
                                    .font(RexFont.text(11))
                                    .foregroundStyle(RexColor.mutedForeground)
                                Spacer(minLength: 4)
                                Text(fact.value)
                                    .font(RexFont.text(11, weight: .semibold))
                                    .foregroundStyle(RexColor.foreground)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 5)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(RexColor.divider).frame(height: 1)
                            }
                        }
                    }
                }

                if let synopsis = details?.synopsis {
                    Text(synopsis)
                        .font(RexFont.text(13.5))
                        .foregroundStyle(RexColor.foreground.opacity(0.9))
                        // Two, not four: the reviews are what the page is for,
                        // and four lines of publisher copy is most of the
                        // distance between the title and the first of them.
                        .lineLimit(synopsisExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !synopsisExpanded, synopsis.count > 120 {
                        Button("Read more") { withAnimation(.snappy) { synopsisExpanded = true } }
                            .font(RexFont.text(12, weight: .semibold))
                            .foregroundStyle(RexColor.primary)
                    }
                }
            }
            .padding(.top, RexSpacing.sm)
        }
    }

    /// Which categories get the strip: the ones with a catalogue behind them
    /// and therefore facts to state. A place has opening hours and a map
    /// instead, which is a different and better answer for a place.
    private var hasFactsStrip: Bool {
        [.book, .movie, .tv, .podcast].contains(RexCategory(rawType: item?.type))
    }

    /// What the thing has to say for itself, as short label-and-value pairs.
    ///
    /// Anything missing is left out rather than shown empty: a strip reading
    /// "Pages —" is worse than four facts instead of five.
    ///
    /// The awkward part is that RexSearch hands back one `facts` string —
    /// "384 pages", "1h 58m · Drama, Romance", "3 seasons" — built for a
    /// single line under a title. Rather than change that and every caller,
    /// this takes it apart again: each piece is recognisable by shape, and a
    /// piece that isn't is simply a genre, which is what it always was.
    private func catalogueFacts(item: RexItem) -> [(label: String, value: String)] {
        var out: [(String, String)] = []
        var catalogueGenres: [String] = []

        for piece in (details?.facts ?? "").components(separatedBy: " \u{00B7} ") {
            let value = piece.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            if value.hasSuffix("pages") {
                out.append(("Pages", value.replacingOccurrences(of: " pages", with: "")))
            } else if value.hasSuffix("season") || value.hasSuffix("seasons") {
                out.append(("Seasons", value.replacingOccurrences(of: " seasons", with: "")
                    .replacingOccurrences(of: " season", with: "")))
            } else if value.first?.isNumber == true, value.contains("h") || value.hasSuffix("m") {
                out.append(("Length", value))
            } else {
                catalogueGenres.append(value)
            }
        }

        // The catalogue's own score, for everything but books.
        //
        // Books lose it on purpose: theirs comes from Open Library, whose name
        // means nothing to a reader and was the thing Kathryn asked to drop on
        // the 8th. TMDB is a score people recognise and read as a score, so a
        // film keeps it — and it is the one fact here that is somebody else's
        // opinion rather than a property of the thing, which is why it sits
        // among the facts rather than up with the friends' ratings.
        if RexCategory(rawType: item.type) != .book,
           let rating = details?.ratings.first {
            out.append((rating.source, rating.value))
        }

        // The certificate, where TMDB has one for this country.
        if let certificate = details?.certificate, !certificate.isEmpty {
            out.append(("Rated", certificate))
        }

        // A book's subtitle is "Author · Year" and a film's is the year on its
        // own (see RexSearch's import), so a four-digit tail is the year
        // either way.
        if let subtitle = item.subtitle {
            let parts = subtitle.components(separatedBy: " \u{00B7} ")
            if let year = parts.last?.trimmingCharacters(in: .whitespaces),
               year.count == 4, year.allSatisfy(\.isNumber) {
                out.append((RexCategory(rawType: item.type) == .book ? "Published" : "Released", year))
            }
        }

        // Ours first — somebody chose those — then the catalogue's, which is
        // usually finer-grained and worth having when nobody has chosen.
        let chosen = splitGenres(item.genre)
        let genres = chosen.isEmpty ? catalogueGenres : chosen
        if !genres.isEmpty {
            out.append(("Genre", genres.prefix(2).joined(separator: ", ")))
        }

        return out.map { (label: $0.0, value: $0.1) }
    }

    /// What the thing actually is, before what your friends made of it:
    /// the ratings strip, then the synopsis. Films and TV only now — a book's
    /// facts moved up under its header on 8 October.
    @ViewBuilder
    private var detailsSection: some View {
        if isLoadingDetails, details == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Looking it up\u{2026}").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
            }
        } else if let details, !details.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if !details.ratings.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: RexSpacing.sm) {
                            ForEach(details.ratings, id: \.source) { rating in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(rating.source.uppercased())
                                        .font(.system(size: 9, weight: .semibold))
                                        .tracking(0.4)
                                        .foregroundStyle(RexColor.mutedForeground)
                                    Text(rating.value)
                                        .font(RexFont.display(16, weight: .semibold))
                                        .foregroundStyle(RexColor.foreground)
                                    if let detail = rating.detail {
                                        Text(detail)
                                            .font(RexFont.text(10))
                                            .foregroundStyle(RexColor.mutedForeground)
                                    }
                                }
                                .padding(.horizontal, RexSpacing.md)
                                .padding(.vertical, RexSpacing.sm)
                                .background(RexColor.card)
                                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                        .stroke(RexColor.border, lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }

                // The certificate and the running time moved up into the
                // header on 4 Oct, where every category's hard facts now sit.
                // Leaving them here too would say the same thing twice on the
                // same screen.



                if let synopsis = details.synopsis {
                    Text(synopsis)
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.foreground.opacity(0.9))
                        .lineLimit(synopsisExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    if !synopsisExpanded, synopsis.count > 220 {
                        Button("Read more") { withAnimation(.snappy) { synopsisExpanded = true } }
                            .font(RexFont.text(12, weight: .semibold))
                            .foregroundStyle(RexColor.primary)
                    }
                    // Whose description this is, so the numbers above aren't
                    // mistaken for Rex's own.
                    Text("From \(details.ratings.first?.source ?? "the catalogue")")
                        .font(RexFont.text(10))
                        .foregroundStyle(RexColor.placeholder)
                }
            }
            .padding(.top, RexSpacing.xs)
        }
    }

    private func loadDetails(_ item: RexItem) async {
        let category = RexCategory(rawType: item.type)
        guard category == .movie || category == .tv || category == .book, details == nil else { return }
        isLoadingDetails = true
        let reference = await RexAPI.shared.fetchItemExternalRef(itemId: item.id)
        let fetched = await RexSearch.details(
            type: category, externalId: reference.id, externalSource: reference.source,
            title: item.title, subtitle: item.subtitle
        )
        details = fetched
        isLoadingDetails = false
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(.footnote).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.footnote.weight(.semibold)).foregroundStyle(RexColor.primary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

// The ten-crown picker moved to RexRatingScale.swift as RexRatingPicker,
// which is the five-tier scale (Do not Rex / Meh / Rex / Loved / Obsessed).

/// Sept 29 — "Google reviews — import or link through to the Google page.
/// For non-places, use the best thing e.g. Rotten Tomatoes for Films and TV,
/// Goodreads for books (if this is possible)".
///
/// Linking, not importing — and the "if this is possible" is the honest
/// part of the answer. Rotten Tomatoes licenses its scores through Fandango
/// and Goodreads closed its API in 2020, so neither score can legitimately be
/// read and shown as a number. What can be done is land someone on the right
/// page in one tap. Google is the exception: its rating is already stored on
/// the item, so that card shows a real figure and now has the link behind it.
enum RexExternalLink {
    struct Destination {
        let label: String
        let symbol: String
        let url: URL
    }

    static func forItem(_ item: RexItem?) -> Destination? {
        guard let item else { return nil }
        let query = [item.title, item.subtitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        switch RexCategory(rawValue: item.type) {
        case .place, .event:
            // A place found through Google keeps its place id, which opens the
            // real listing. Anything typed by hand falls back to a search for
            // the name and address — not guaranteed, but it lands right far
            // more often than it doesn't.
            if item.external_source == "google_places", let id = item.external_id, !id.isEmpty {
                return make("https://www.google.com/maps/search/?api=1&query=\(esc(item.title))&query_place_id=\(esc(id))",
                            "See on Google Maps", "mappin.and.ellipse")
            }
            let place = [item.title, item.address].compactMap { $0 }.joined(separator: " ")
            return make("https://www.google.com/maps/search/?api=1&query=\(esc(place))",
                        "See on Google Maps", "mappin.and.ellipse")

        case .movie, .tv:
            return make("https://www.rottentomatoes.com/search?search=\(esc(item.title))",
                        "See on Rotten Tomatoes", "film")

        case .book:
            return make("https://www.goodreads.com/search?q=\(esc(query))",
                        "See on Goodreads", "books.vertical")

        case .podcast:
            return make("https://podcasts.apple.com/search?term=\(esc(item.title))",
                        "See on Apple Podcasts", "mic")

        default:
            // Recipes, trips and the catch-all have no one obvious home to
            // send anyone to, so they get no link rather than a bad guess.
            return nil
        }
    }

    private static func make(_ string: String, _ label: String, _ symbol: String) -> Destination? {
        URL(string: string).map { Destination(label: label, symbol: symbol, url: $0) }
    }

    private static func esc(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }
}
