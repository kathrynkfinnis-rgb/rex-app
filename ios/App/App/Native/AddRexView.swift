import SwiftUI

/// v1 scope: category picker → manual entry form → post.
/// Skips live external search (Google/TMDB/etc — those are our own server functions over a
/// different RPC protocol, not plain Supabase REST) and skips Trips (needs the stops builder).
/// "Enter details manually" is exactly the fallback path the web app already offers, so this
/// is a real, working subset of Add a Rex rather than a stub.
struct AddRexView: View {
    var onDone: () -> Void

    /// #167 — "add a Rex by finding a place on the map first": the map
    /// already resolves a tapped point to a real place (reverse-geocoded,
    /// same as the "type of place" header does elsewhere), so this reuses
    /// the exact same picked-hit path a Google Places search result takes
    /// (see apply(_:)) rather than inventing a second prefill mechanism —
    /// jumping straight past the category picker and the search box into
    /// the already-filled-in form.
    init(onDone: @escaping () -> Void, initialPlaceHit: RexSearchHit? = nil) {
        self.onDone = onDone
        if let hit = initialPlaceHit {
            _category = State(initialValue: .place)
            _picked = State(initialValue: hit)
            _title = State(initialValue: hit.title)
            _address = State(initialValue: hit.address ?? "")
        }
    }

    /// Sept 5 — "ensure that the layout of the input page then mirrors
    /// (exactly) the other input page". A document import used to end at
    /// its own review screen, which could only toggle and delete rows; now
    /// it lands here, on the identical Add-a-trip form, pre-filled — so
    /// adding a stop the document never mentioned, adding a heading, and
    /// dragging things around all work exactly as they do when building a
    /// trip by hand, because it *is* the same screen.
    ///
    /// Same shape as initialPlaceHit above: open straight on one category's
    /// form rather than the picker.
    init(
        onDone: @escaping () -> Void,
        initialTripName: String,
        initialTripEntries: [ItineraryEntry]
    ) {
        self.onDone = onDone
        _category = State(initialValue: .trip)
        _manualEntry = State(initialValue: true)
        _title = State(initialValue: initialTripName)
        _tripEntries = State(initialValue: initialTripEntries)
    }

    /// Sept 5 — "when it comes to editing a trip after submission, it
    /// should take you to the same page as the input page". Same form,
    /// pre-filled from what was posted; save updates in place rather than
    /// creating a second trip (see saveTripEdits).
    init(onDone: @escaping () -> Void, editingTrip trip: FeedRecommendation, stops: [FeedRecommendation]) {
        self.onDone = onDone
        _category = State(initialValue: .trip)
        _manualEntry = State(initialValue: true)
        _editingTripRecId = State(initialValue: trip.id)
        _editingTripItemId = State(initialValue: trip.item_id)
        _title = State(initialValue: trip.items?.title ?? "")
        _note = State(initialValue: trip.note ?? "")
        _rating = State(initialValue: trip.rating > 0 ? trip.rating : 10)
        _photoURLs = State(initialValue: trip.photo_urls ?? [])
        _subcategories = State(initialValue: Set(splitGenres(trip.items?.genre)))

        let draftStops = stops.map { rec in
            DraftStop(
                type: RexCategory(rawType: rec.items?.type),
                title: rec.items?.title ?? "",
                subtitle: rec.items?.subtitle,
                address: rec.items?.address,
                lat: nil,
                lng: nil,
                genre: rec.items?.genre,
                imageURL: rec.items?.image_url,
                externalId: nil,
                externalSource: nil,
                rating: rec.rating,
                note: rec.note ?? "",
                section: rec.trip_section,
                photoURL: rec.photo_urls?.first,
                existingRecId: rec.id,
                existingItemId: rec.item_id
            )
        }
        _tripEntries = State(initialValue: .fromStops(draftStops))
        _originalStopRecIds = State(initialValue: Set(stops.map { $0.id }))

        // The date lives in the item's subtitle ("March 2026"); parse it
        // back into the two wheels so editing doesn't silently drop it.
        if let subtitle = trip.items?.subtitle, !subtitle.isEmpty {
            let parts = subtitle.split(separator: " ").map(String.init)
            let months = Calendar.current.monthSymbols
            for part in parts {
                if let monthIndex = months.firstIndex(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) {
                    _tripMonth = State(initialValue: monthIndex + 1)
                } else if let year = Int(part), year > 1900, year < 2200 {
                    _tripYear = State(initialValue: year)
                }
            }
        }
    }

    // Trip sits second, as on the web. A trip is created as a normal Rex here
    // and stops get added to it afterwards from the trip screen. List sits
    // right after — same "container + its own items" shape as Trip — for
    // building one by hand, right here, rather than only ever arriving via
    // "Import from doc" (#118). That importer is still the fast path for a
    // list that already exists somewhere as text; this tile is for a list
    // that doesn't fit any other category and is being made up as you go.
    private let creatableCategories: [RexCategory] = [.place, .trip, .list, .book, .movie, .tv, .podcast, .recipe, .event, .other]

    /// A list can hold any kind of Rex — that's the whole point of it being
    /// the catch-all container — unlike a trip's stops, which are almost
    /// always a place.
    private let listItemTypes: [RexCategory] = [.book, .movie, .tv, .place, .recipe, .event, .podcast, .other]

    private enum Mode { case rated, want }

    @State private var category: RexCategory?
    @State private var mode: Mode = .rated
    @State private var title = ""
    @State private var subtitle = ""
    @State private var address = ""
    @State private var rating: Double = 10
    @State private var note = ""
    @State private var isSaving = false
    /// Posting a trip is several sequential network calls (the trip itself,
    /// then each stop) — without this it just looks stuck for however many
    /// stops there are.
    @State private var postingProgress: String?
    @State private var anonymous = false
    @State private var errorMessage: String?
    @State private var didPost = false
    @State private var didWant = false
    /// Trips only, for now — see AddRexView's "Save as draft" button.
    @State private var didSaveDraft = false
    /// The item just saved as "want to try" — kept around so the success
    /// screen can offer an immediate undo. RexAPI already had removeWant for
    /// this; there was just nowhere in Add-a-Rex that called it, so tapping
    /// "Want to try" was a one-way door until you went and found it again in
    /// Collections to swipe it away.
    @State private var lastWantItemId: String?
    @State private var isUndoingWant = false

    // Search-as-you-type against the external catalogues.
    @State private var hits: [RexSearchHit] = []
    @State private var isSearching = false
    @State private var picked: RexSearchHit?
    @State private var searchTask: Task<Void, Never>?
    @State private var photoURLs: [String] = []
    @State private var taggedFriendIds: Set<String> = []
    @State private var subcategories: Set<String> = []
    @State private var productLink = ""
    /// Sept 2 trips rebuild — a trip's itinerary is an ordered list of
    /// headings and stops now (see ItineraryEntry), not a flat [DraftStop]
    /// with a heading string on each. It flattens back to that shape on
    /// save (resolvedTripStops), which is what actually gets posted.
    @State private var tripEntries: [ItineraryEntry] = []
    @State private var tripMonth: Int?
    @State private var tripYear: Int?
    /// Non-nil when this form is editing an already-posted trip rather than
    /// building a new one — see init(onDone:editingTrip:stops:).
    @State private var editingTripRecId: String?
    @State private var editingTripItemId: String?
    /// What the trip had when the editor opened, so stops deleted during
    /// the edit can be told from ones that were never there.
    @State private var originalStopRecIds: Set<String> = []
    @State private var listItems: [DraftStop] = []
    /// Sept 5 — a list's items are an ordered heading/item list now, the
    /// same shape a trip's itinerary uses. listItems above is still what
    /// gets posted; this flattens into it on save.
    @State private var listEntries: [ItineraryEntry] = []
    @State private var customListKind = ""
    @State private var showingCustomListKind = false
    @State private var listKind = rexListKinds.first ?? "Other"
    @State private var recipeText = ""
    /// Searchable categories open on a search field; the full form only
    /// appears once something's picked or you choose to type it in manually.
    @State private var manualEntry = false
    /// Every sheet this screen can present, as one value — see the single
    /// .sheet modifier in `body` for why they can't be separate modifiers.
    private enum ActiveSheet: Identifiable {
        case editListItem(ItineraryEntry)
        case editTripStop(ItineraryEntry)
        case documentImport
        case buildTripFromRex

        var id: String {
            switch self {
            case .editListItem(let e): return "listItem-\(e.id)"
            case .editTripStop(let e): return "tripStop-\(e.id)"
            case .documentImport: return "documentImport"
            case .buildTripFromRex: return "buildTripFromRex"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    var body: some View {
        NavigationStack {
            ZStack {
                RexColor.background.ignoresSafeArea()
                ScrollView {
                    if didPost {
                        successState
                    } else if let category {
                        form(for: category)
                    } else {
                        categoryPicker
                    }
                }
            }
            .navigationTitle(category == nil ? "What are you Rexing?" : "Add a \(category!.label.lowercased())")
            .rexDismissableKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if category != nil && !didPost {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            withAnimation {
                                category = nil
                                resetDraftFields()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onDone() }
                }
            }
        }
        .tint(RexColor.primary)
    }

    private var categoryPicker: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(creatableCategories, id: \.self) { cat in
                    Button {
                        withAnimation { category = cat }
                    } label: {
                        HStack(spacing: 0) {
                            // Left accent bar — the one colour cue that
                            // reads before the icon/label even register,
                            // same trick the reference picker uses.
                            Rectangle()
                                .fill(cat.tintColor)
                                .frame(width: 5)

                            HStack(spacing: 10) {
                                Image(systemName: cat.symbol)
                                    .font(.system(size: 20))
                                    .foregroundStyle(cat.tintColor)
                                Text(cat.label)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(RexColor.foreground)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 14)
                        }
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // #109 — same entry point the web offers ("Import a collection"),
            // but this one runs the extraction itself rather than deep
            // -linking to the web importer: paste text in, review what came
            // out, save as a Trip or a Collection.
            Button {
                activeSheet = .documentImport
            } label: {
                HStack(spacing: RexSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                            .fill(RexColor.badgeBackground)
                        Image(systemName: "doc.text")
                            .font(.system(size: 20))
                            .foregroundStyle(RexColor.primary)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from doc")
                            .font(RexFont.display(17, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text("Paste from Notes, a Word doc, or an itinerary.")
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                    Spacer()
                }
                .padding(RexSpacing.md)
                .rexCard()
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        // "If you click on each rex, [it] should take you to the same style
        // of 'add a stop' [sheet] as in the manual add a trip process."
        // Sept 7 — one sheet modifier, not four.
        //
        // "The import from doc button on the list page isn't working" was
        // this: SwiftUI does not reliably support several .sheet modifiers
        // stacked on the same view. There were four here (edit a list item,
        // edit a trip stop, import a document, build from your Rex) and in
        // practice one of them wins — the document importer was the one
        // losing, so its button set a flag that nothing was listening to.
        // Routing every sheet through a single enum-driven presentation is
        // the documented way to have more than one.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editListItem(let entry):
                if let item = entry.stop {
                    ListItemSheet(existing: item) { updated in
                        if let index = listEntries.firstIndex(where: { $0.id == entry.id }) {
                            listEntries[index].kind = .stop(updated)
                        }
                    }
                }
            case .editTripStop(let entry):
                TripStopSheet(
                    subcategories: rexSubcategories[.place] ?? [],
                    existing: entry.stop
                ) { updated in
                    guard let index = tripEntries.firstIndex(where: { $0.id == entry.id }) else { return }
                    tripEntries[index].kind = .stop(updated)
                }
            case .documentImport:
                ListsImportView(
                    onDone: { activeSheet = nil; onDone() },
                    // A document imported as a trip or a list fills in this
                    // form rather than posting itself — see the .trip and
                    // .list cases in ImportReviewView.save().
                    onExtractedAsTrip: { name, entries in
                        activeSheet = nil
                        category = .trip
                        manualEntry = true
                        if title.trimmingCharacters(in: .whitespaces).isEmpty { title = name }
                        tripEntries = entries
                    },
                    onExtractedAsList: { name, kind, entries in
                        activeSheet = nil
                        category = .list
                        manualEntry = true
                        if title.trimmingCharacters(in: .whitespaces).isEmpty { title = name }
                        if !kind.isEmpty { listKind = kind }
                        listEntries = entries
                    }
                )
            case .buildTripFromRex:
                BuildTripFromRexView(onDone: {
                    activeSheet = nil
                    onDone()
                })
            }
        }
    }

    @ViewBuilder
    private func form(for category: RexCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let searchable: Set<RexCategory> = [.place, .event, .book, .movie, .tv, .podcast, .other]
            let searchFirst = searchable.contains(category) && picked == nil && !manualEntry

            // Sept 2 — "rename title → 'Name your trip'". Only trips: for
            // everything else "Title" is still the right word, since you're
            // naming a thing that already exists rather than christening
            // something of your own.
            field(searchFirst ? "Search" : (category == .trip ? "Name your trip" : category == .list ? "Name your list" : "Title"), text: $title,
                  placeholder: searchFirst
                      ? "Search \(category.label.lowercased())s…"
                      : "e.g. \(placeholderTitle(for: category))")
                .onChange(of: title) { _, _ in scheduleSearch(for: category) }

            suggestions(for: category)

            if searchFirst {
                // Escape hatch for anything the catalogues don't have.
                Button {
                    manualEntry = true
                } label: {
                    HStack(spacing: RexSpacing.sm) {
                        Image(systemName: "square.and.pencil").font(.system(size: 12))
                        Text("Can't find it? Enter the details manually")
                            .font(RexFont.text(13, weight: .medium))
                    }
                    .foregroundStyle(RexColor.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RexSpacing.md)
                    .background(RexColor.badgeBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !searchFirst {
            // A list's "kind" chip already says what it's about — a second,
            // generic "Subtitle" box under the name would just be a blank
            // field nobody knows what to put in. Sept 2: a trip drops it
            // too — "Remove Subtitle" — since the date and the itinerary
            // now say everything the subtitle used to.
            if category != .list && category != .trip {
                field(subtitleLabel(for: category), text: $subtitle, placeholder: "Optional")
            }

            if category == .place || category == .event {
                field("Address", text: $address, placeholder: "Optional")
            }

            if category == .list {
                listKindChips
            }

            if category == .trip {
                // Sept 2 — "add an optional 'date travelled' field", to the
                // month rather than the day: nobody remembers (or wants to
                // pick) the exact date they got back from Rome, and "March
                // 2026" is what a trip is actually filed under.
                TripDateTravelledField(month: $tripMonth, year: $tripYear)

                VStack(alignment: .leading, spacing: RexSpacing.xs) {
                    Text("Cover photo").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    PhotoPickerView(photoURLs: $photoURLs, maxPhotos: 1)
                    Text("Just a thumbnail — the trip's card leads with its map.")
                        .font(RexFont.text(11.5))
                        .foregroundStyle(RexColor.mutedForeground)
                }

                TripItineraryBuilderView(
                    entries: $tripEntries,
                    onEditStop: { entry in activeSheet = .editTripStop(entry) }
                )

                // The old stops builder carried these two entry points and
                // the new one doesn't, which quietly removed the only way
                // into a document import from the Trip form itself. Same
                // two buttons, moved out here — and the import one now
                // lands back on this very screen, pre-filled, rather than
                // posting a trip behind your back.
                Button {
                    activeSheet = .documentImport
                } label: {
                    Label("Import a trip from a document", systemImage: "doc.text")
                        .font(RexFont.text(13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, RexSpacing.md)
                        .background(RexColor.badgeBackground)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(RexColor.primary)

                Button {
                    activeSheet = .buildTripFromRex
                } label: {
                    Label("Build a trip from your Rex", systemImage: "square.stack")
                        .font(RexFont.text(13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, RexSpacing.md)
                        .background(RexColor.badgeBackground)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(RexColor.primary)
            }

            if category == .list {
                // Sept 5 — "update the list inputs so it's similar to the
                // trip input: headings and items in draggable boxes". Same
                // builder the trip uses, in its list mode — the structure
                // is identical, only the wording and the item sheet differ.
                VStack(alignment: .leading, spacing: RexSpacing.xs) {
                    Text("Cover photo").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    PhotoPickerView(photoURLs: $photoURLs, maxPhotos: 1)
                }

                TripItineraryBuilderView(
                    entries: $listEntries,
                    mode: .list,
                    onEditStop: { entry in activeSheet = .editListItem(entry) }
                )

                Button {
                    activeSheet = .documentImport
                } label: {
                    Label("Import a list from a document", systemImage: "doc.text")
                        .font(RexFont.text(13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, RexSpacing.md)
                        .background(RexColor.badgeBackground)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(RexColor.primary)
            }

            if category == .recipe {
                RecipeEditorView(recipeText: $recipeText, title: $title)
            }

            if let options = rexSubcategories[category], !options.isEmpty {
                Text(category == .place ? "Type of place" : "Type")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                FlowChips(options: options, selected: $subcategories)
            }

            // A link to the thing itself: the point of Other (products,
            // services) and useful for places and events. Books, films, TV and
            // podcasts come from a catalogue with their own page, so a link
            // field there is just another box to ignore. A list isn't a single
            // thing to link to either.
            // Sept 2: a trip drops it as well — "remove link (that can be
            // inputted through notes)".
            if ![.book, .movie, .tv, .podcast, .list, .trip].contains(category) {
                field("Link (optional)", text: $productLink, placeholder: "https://…")
                    .textInputAutocapitalization(.never)
            }

            // A list is always just "posted" — there's no done-vs-want-to-try
            // state for a container, and ListDetailView never shows the
            // container's own rating, only its items'. So it gets its own
            // simple note field instead of the full rated/want picker below.
            if category == .list {
                Text("Why are you Rex\u{2019}ing it?").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                TextField("What's this list for?", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
            } else {

            modePicker(for: category)

            if mode == .want {
                Text("Why? (optional)").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                TextField("Who told you about it, what caught your eye…", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
                Text("This goes in your friends' feed so they can chime in.")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            if mode == .rated {
                Text("Your rating").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                RexRatingPicker(value: $rating)

                Text("Note").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                TextField("What did you love about it?", text: $note, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(12)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))

                // A trip already set its single cover photo up top, and its
                // carousel is built from its stops' photos — so no second,
                // contradictory multi-photo picker down here.
                if category != .trip {
                    Text("Photos").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                    PhotoPickerView(photoURLs: $photoURLs)
                }

                Text("Tag friends (optional)").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                FriendTagPickerView(selectedIds: $taggedFriendIds)

                Toggle(isOn: $anonymous) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Post anonymously")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text("Your name won't show. It still counts toward your Rex.")
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                }
                .tint(RexColor.primary)
            }
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(RexColor.destructive)
            }

            if let postingProgress {
                Text(postingProgress).font(.footnote).foregroundStyle(RexColor.mutedForeground)
            }

            Button(action: { Task { await post(category: category) } }) {
                if isSaving {
                    ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                } else {
                    Text(editingTripRecId != nil
                         ? "Save changes"
                         : (mode == .rated ? "Post" : addToWantLabel(for: category)))
                        .fontWeight(.semibold).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 48)
            .background(title.trimmingCharacters(in: .whitespaces).isEmpty ? RexColor.primary.opacity(0.4) : RexColor.primary)
            .foregroundStyle(RexColor.primaryForeground)
            .clipShape(Capsule())
            .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.top, 6)

            // Drafts only make sense for trips right now — journaling stops
            // over several sittings and publishing the finished itinerary
            // at the end. A single Rex is a one-shot post; there's nothing
            // to draft.
            if category == .trip && mode == .rated {
                Button {
                    Task { await post(category: category, asDraft: true) }
                } label: {
                    Text("Save as draft").font(RexFont.text(14, weight: .semibold))
                }
                .foregroundStyle(RexColor.primary)
                .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            }
        }
        .padding(16)
    }

    /// Live results from the external catalogues. Hidden once the user picks
    /// something, so the form stops nagging.
    @ViewBuilder
    private func suggestions(for category: RexCategory) -> some View {
        let searchable: Set<RexCategory> = [.place, .event, .book, .movie, .tv, .podcast, .other]

        if searchable.contains(category) {
            if let picked {
                HStack(spacing: RexSpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(RexColor.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(picked.title)
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                            .lineLimit(1)
                        if let sub = picked.address ?? picked.subtitle, !sub.isEmpty {
                            Text(sub)
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("Change") {
                        self.picked = nil
                        hits = []
                    }
                    .font(RexFont.text(12, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                }
                .padding(RexSpacing.md)
                .background(RexColor.badgeBackground)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            } else if isSearching || !hits.isEmpty {
                VStack(spacing: 0) {
                    if isSearching && hits.isEmpty {
                        HStack(spacing: RexSpacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("Searching…")
                                .font(RexFont.text(13))
                                .foregroundStyle(RexColor.mutedForeground)
                            Spacer()
                        }
                        .padding(RexSpacing.md)
                    }
                    // "You should be able to scroll down the list of
                    // suggestions if it's a generic title and the initial
                    // one doesn't come up" — this used to hard-cap at 6 with
                    // no way to reach anything past that, silently dropping
                    // real results a search provider (up to 15 from
                    // OpenLibrary/iTunes, 10 from Places) already returned.
                    // Capped-height ScrollView instead of a bare list: all
                    // of `hits` is reachable now, without letting a big
                    // result set push the rest of the form far off-screen.
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(hits) { hit in
                                Button {
                                    apply(hit)
                                } label: {
                                    HStack(spacing: RexSpacing.md) {
                                        thumb(hit)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(hit.title)
                                                .font(RexFont.text(14, weight: .medium))
                                                .foregroundStyle(RexColor.foreground)
                                                .lineLimit(1)
                                            if let sub = hit.address ?? hit.subtitle, !sub.isEmpty {
                                                Text(sub)
                                                    .font(RexFont.text(12))
                                                    .foregroundStyle(RexColor.mutedForeground)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, RexSpacing.md)
                                    .padding(.vertical, RexSpacing.sm)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if hit.id != hits.last?.id {
                                    Rectangle().fill(RexColor.divider).frame(height: 1)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func thumb(_ hit: RexSearchHit) -> some View {
        Group {
            if let s = hit.imageURL, let url = URL(string: s) {
                // Plain AsyncImage silently never loads a Google Places
                // photo — see GoogleSafeAsyncImage for why.
                GoogleSafeAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RexColor.muted
                }
            } else {
                RexColor.muted
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func apply(_ hit: RexSearchHit) {
        picked = hit
        title = hit.title
        // Google returns the place name in displayName, so its "subtitle" is
        // the address rather than an author/year.
        if hit.externalSource == "google_places" {
            subtitle = ""
            address = hit.address ?? ""
        } else {
            subtitle = hit.subtitle ?? ""
        }
        // #73 — a picked web result for "Other"/Stuff carries its own page
        // link; everything else leaves productLink alone (nil for them).
        if let productURL = hit.productURL {
            productLink = productURL
        }
        hits = []
    }

    /// Debounced so we're not firing a request per keystroke.
    private func scheduleSearch(for category: RexCategory) {
        searchTask?.cancel()
        guard picked == nil else { return }
        let term = title
        guard term.trimmingCharacters(in: .whitespaces).count >= 2 else {
            hits = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let results = await RexSearch.search(category: category, query: term)
            if Task.isCancelled { return }
            await MainActor.run {
                hits = results
                isSearching = false
            }
        }
    }

    @ViewBuilder
    private func modePicker(for category: RexCategory) -> some View {
        let wantLabel: String = {
            switch category {
            case .place: return "Want to visit"
            case .movie, .tv: return "Want to watch"
            default: return "Want to try"
            }
        }()
        HStack(spacing: 8) {
            modeButton("I've done it", isSelected: mode == .rated) { mode = .rated }
            modeButton(wantLabel, isSelected: mode == .want) { mode = .want }
        }
    }

    private func modeButton(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? RexColor.primary : RexColor.card)
                .foregroundStyle(isSelected ? RexColor.primaryForeground : RexColor.foreground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(RexColor.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    // Same single-select chip row as ImportReviewView's "What kind of list
    // is this?" — kept visually and behaviorally identical so a list looks
    // the same whether it was typed by hand here or came in from a pasted
    // document.
    private var listKindChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What kind of list is this?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    // Sept 5 — "under 'what kind of list is this?' allow a
                    // free text box". The stock kinds cover the common
                    // cases; anything you've typed yourself joins them as a
                    // chip so it can be selected and deselected like the rest.
                    ForEach(offeredListKinds, id: \.self) { kind in
                        let isOn = listKind == kind
                        Button(kind) { listKind = kind }
                            .font(RexFont.text(13, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? RexColor.primaryForeground : RexColor.foreground)
                            .padding(.horizontal, RexSpacing.md)
                            .padding(.vertical, 7)
                            .background(isOn ? RexColor.primary : RexColor.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isOn ? RexColor.primary : RexColor.border, lineWidth: 1))
                    }
                    Button("+ Add your own") { showingCustomListKind = true }
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.primary)
                        .padding(.horizontal, RexSpacing.md)
                        .padding(.vertical, 7)
                        .background(RexColor.card)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(RexColor.border, lineWidth: 1))
                }
            }
            if showingCustomListKind {
                HStack(spacing: RexSpacing.sm) {
                    TextField("e.g. Baby shower", text: $customListKind)
                        .padding(10)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                    Button("Add") {
                        let trimmed = customListKind.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        listKind = trimmed
                        customListKind = ""
                        showingCustomListKind = false
                    }
                    .font(RexFont.text(14, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                }
            }
        }
    }

    /// The stock kinds, plus a custom one already chosen so it stays visible.
    private var offeredListKinds: [String] {
        rexListKinds.contains(listKind) ? rexListKinds : rexListKinds + [listKind]
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
            TextField(placeholder, text: text)
                .padding(12)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
        }
    }

    private func subtitleLabel(for category: RexCategory) -> String {
        switch category {
        case .book: return "Author"
        case .movie, .tv: return "Year or director"
        case .podcast: return "Host or network"
        case .recipe: return "Cookbook, chef, or source"
        case .event: return "Venue, date, or type"
        default: return "Subtitle"
        }
    }

    private func addToWantLabel(for category: RexCategory) -> String {
        switch category {
        case .place: return "Add to want to visit"
        case .movie, .tv: return "Add to want to watch"
        default: return "Add to want to try"
        }
    }

    /// Sept 2 — "add an optional 'date travelled' field ... (but perhaps to
    /// the month / year)". Two wheels rather than a full date picker: a
    /// trip is remembered as "March 2026", and asking for a day you'd have
    /// to look up is friction for no gain. Clears back to nothing, since
    /// the whole field is optional.
    private struct TripDateTravelledField: View {
        @Binding var month: Int?
        @Binding var year: Int?

        private static let monthNames = Calendar.current.monthSymbols
        private var years: [Int] {
            let thisYear = Calendar.current.component(.year, from: Date())
            return Array((thisYear - 30)...(thisYear + 2)).reversed()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: RexSpacing.xs) {
                HStack {
                    Text("Date travelled").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    Text("optional").font(RexFont.text(13)).foregroundStyle(RexColor.placeholder)
                    Spacer()
                    if month != nil || year != nil {
                        Button("Clear") { month = nil; year = nil }
                            .font(RexFont.text(13, weight: .medium))
                            .foregroundStyle(RexColor.primary)
                    }
                }
                HStack(spacing: RexSpacing.sm) {
                    Menu {
                        ForEach(Array(Self.monthNames.enumerated()), id: \.offset) { index, name in
                            Button(name) { month = index + 1 }
                        }
                    } label: {
                        pickerLabel(month.map { Self.monthNames[$0 - 1] } ?? "Month")
                    }
                    Menu {
                        ForEach(years, id: \.self) { y in
                            Button(String(y)) { year = y }
                        }
                    } label: {
                        pickerLabel(year.map(String.init) ?? "Year")
                    }
                }
            }
        }

        private func pickerLabel(_ text: String) -> some View {
            HStack {
                Text(text)
                    .font(RexFont.text(15))
                    .foregroundStyle(text == "Month" || text == "Year" ? RexColor.placeholder : RexColor.foreground)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(RexColor.mutedForeground)
            }
            .padding(12)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
        }
    }

    private func placeholderTitle(for category: RexCategory) -> String {
        switch category {
        case .place: return "Dishoom"
        case .book: return "The Hobbit"
        case .movie: return "Inception"
        case .tv: return "Breaking Bad"
        case .podcast: return "This American Life"
        case .recipe: return "Koshari"
        case .event: return "Glastonbury"
        case .trip: return "Rome Weekend with the Girls"
        default: return "Title"
        }
    }

    /// The itinerary flattened back to stops, each tagged with whichever
    /// heading sits above it. Empty headings drop out here — see
    /// ItineraryEntry.resolvedStops.
    private var resolvedTripStops: [DraftStop] { tripEntries.resolvedStops }

    /// Saves an edit to an already-posted trip: the trip's own fields, then
    /// the itinerary as a diff against what it had when the editor opened.
    ///
    /// Deliberately not a delete-and-recreate: a stop is a real Rex with
    /// its own likes, comments and saves attached, so rebuilding the trip
    /// from scratch every save would quietly destroy all of that. Stops
    /// that survived are updated in place, only genuinely removed ones are
    /// deleted, and order is re-stamped across the lot (created_at is what
    /// orders stops — see TripDetailView.moveStop, which has always worked
    /// this way).
    private func saveTripEdits() async {
        guard let tripRecId = editingTripRecId, let tripItemId = editingTripItemId else { return }
        isSaving = true
        errorMessage = nil
        do {
            postingProgress = "Saving trip…"
            let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
            try await RexAPI.shared.updateItemTitle(itemId: tripItemId, title: trimmedTitle)
            try await RexAPI.shared.updateItemSubtitle(itemId: tripItemId, subtitle: tripDateText)
            try await RexAPI.shared.updateItemGenre(
                itemId: tripItemId,
                genre: subcategories.isEmpty ? nil : subcategories.sorted().joined(separator: ", ")
            )
            // Cover photo lives on the item (the thumbnail), not on the
            // recommendation — same rule as posting, see post().
            try await RexAPI.shared.updateItemImageURL(itemId: tripItemId, imageURL: photoURLs.first)
            try await RexAPI.shared.updateRecommendation(
                id: tripRecId,
                rating: rating,
                note: note.isEmpty ? nil : note,
                photoURLs: [],
                tags: []
            )

            let stops = resolvedTripStops
            let keptIds = Set(stops.compactMap { $0.existingRecId })
            for removed in originalStopRecIds.subtracting(keptIds) {
                try? await RexAPI.shared.deleteRecommendation(id: removed)
            }

            // created_at drives stop order, so re-stamp every stop onto an
            // increasing sequence matching the order on screen.
            let base = Date().addingTimeInterval(-Double(stops.count))
            let formatter = ISO8601DateFormatter()
            for (index, stop) in stops.enumerated() {
                postingProgress = "Saving stop \(index + 1) of \(stops.count)…"
                let stamp = formatter.string(from: base.addingTimeInterval(Double(index)))
                if let recId = stop.existingRecId, let itemId = stop.existingItemId {
                    try? await RexAPI.shared.updateItemTitle(itemId: itemId, title: stop.title)
                    try? await RexAPI.shared.updateItemGenre(itemId: itemId, genre: stop.genre)
                    try? await RexAPI.shared.updateRecommendation(
                        id: recId,
                        rating: stop.rating,
                        note: stop.note.isEmpty ? nil : stop.note,
                        photoURLs: [stop.photoURL].compactMap { $0 },
                        tags: []
                    )
                    try? await RexAPI.shared.setTripSection(recommendationId: recId, section: stop.section)
                    try? await RexAPI.shared.setRecommendationCreatedAt(id: recId, createdAt: stamp)
                } else {
                    let newItemId = try await RexAPI.shared.createItem(
                        type: stop.type.rawValue,
                        title: stop.title,
                        subtitle: stop.subtitle,
                        address: stop.address,
                        genre: stop.genre,
                        externalId: stop.externalId,
                        externalSource: stop.externalSource,
                        imageURL: stop.imageURL,
                        lat: stop.lat,
                        lng: stop.lng
                    )
                    let newRecId = try await RexAPI.shared.createRecommendation(
                        itemId: newItemId,
                        rating: stop.rating,
                        note: stop.note.isEmpty ? nil : stop.note,
                        photoURLs: [stop.photoURL].compactMap { $0 },
                        tripId: tripRecId,
                        tripSection: stop.section,
                        returningId: true
                    )
                    try? await RexAPI.shared.setRecommendationCreatedAt(id: newRecId, createdAt: stamp)
                }
            }
            postingProgress = nil
            onDone()
        } catch {
            postingProgress = nil
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    /// "March 2026", "2026", or nothing — every combination the two
    /// optional wheels can be left in.
    private var tripDateText: String? {
        switch (tripMonth, tripYear) {
        case let (month?, year?): return "\(Calendar.current.monthSymbols[month - 1]) \(year)"
        case let (month?, nil): return Calendar.current.monthSymbols[month - 1]
        case let (nil, year?): return String(year)
        case (nil, nil): return nil
        }
    }

    private func post(category: RexCategory, asDraft: Bool = false) async {
        // Editing an already-posted trip updates it in place instead of
        // creating a second one.
        if editingTripRecId != nil {
            await saveTripEdits()
            return
        }
        isSaving = true
        errorMessage = nil
        postingProgress = nil
        do {
            let itemId = try await RexAPI.shared.createItem(
                type: category.rawValue,
                title: title.trimmingCharacters(in: .whitespaces),
                // A trip has no subtitle field any more; the date travelled
                // takes that slot instead, which is also exactly where the
                // card already renders a line under the title.
                subtitle: category == .trip ? tripDateText : (subtitle.isEmpty ? nil : subtitle),
                address: (category == .place || category == .event) && !address.isEmpty ? address : nil,
                hit: picked,
                // The "genre" column is where approveStagingAsList already
                // stores a list's kind (Book/Place/Trip/...) — same column,
                // same meaning, whichever route created the list.
                genre: category == .list ? listKind : (subcategories.isEmpty ? nil : subcategories.sorted().joined(separator: ", ")),
                linkURL: productLink.trimmingCharacters(in: .whitespaces).isEmpty ? nil : productLink.trimmingCharacters(in: .whitespaces),
                // #21/#154 "guaranteed image", generalized beyond recipes:
                // whenever the catalogue hasn't already supplied a cover
                // (no search result picked, or the picked one had no photo —
                // recipes always land here since they never have a hit at
                // all), promote whatever photo the post itself carries
                // instead of leaving every card on the generic placeholder
                // icon. A real photo, when there is one, beats no photo.
                imageURL: (picked?.imageURL?.isEmpty ?? true) ? photoURLs.first : nil,
                recipeText: category == .recipe && !recipeText.isEmpty ? recipeText : nil
            )
            // Trip stops become their own Rex, linked to the trip.
            if category == .trip, !resolvedTripStops.isEmpty {
                let tripStops = resolvedTripStops
                let tripRecId = try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: note.isEmpty ? nil : note,
                    // Sept 7 — "uploaded a thumbnail for a trip but it became
                    // the card pic". The cover photo was being written to both
                    // the item (which draws the small thumbnail) and the
                    // recommendation's photos (which draws the full-width
                    // carousel), and the carousel won. A trip's card is meant
                    // to lead with its map, so the cover photo stays on the
                    // item only — see the imageURL argument to createItem.
                    photoURLs: [],
                    returningId: true,
                    asDraft: asDraft
                )
                // Posting is several sequential network calls; if one stop
                // partway through fails, the trip used to just be left half
                // -built with no way to retry cleanly. Track what's been
                // created so a failure can roll it all back instead.
                var createdStopRecIds: [String] = []
                do {
                    for (index, stop) in tripStops.enumerated() {
                        postingProgress = tripStops.count > 1
                            ? "Adding stop \(index + 1) of \(tripStops.count)…" : "Adding stop…"
                        let stopItemId = try await RexAPI.shared.createItem(
                            type: stop.type.rawValue,
                            title: stop.title,
                            subtitle: stop.subtitle,
                            address: stop.address,
                            genre: stop.genre,
                            externalId: stop.externalId,
                            externalSource: stop.externalSource,
                            imageURL: stop.imageURL,
                            lat: stop.lat,
                            lng: stop.lng
                        )
                        let stopRecId = try await RexAPI.shared.createRecommendation(
                            itemId: stopItemId,
                            rating: stop.rating,
                            note: stop.note.isEmpty ? nil : stop.note,
                            // A stop's one photo rides along on its own Rex,
                            // which is what feeds the trip's carousel.
                            photoURLs: [stop.photoURL].compactMap { $0 },
                            tripId: tripRecId,
                            tripSection: stop.section,
                            returningId: true,
                            asDraft: asDraft
                        )
                        createdStopRecIds.append(stopRecId)
                    }
                } catch {
                    postingProgress = "Undoing partial trip…"
                    // Best-effort: these are cleanup after a failure we're
                    // about to report anyway, so a second error here
                    // shouldn't replace the one the user needs to see.
                    for id in createdStopRecIds { try? await RexAPI.shared.deleteRecommendation(id: id) }
                    try? await RexAPI.shared.deleteRecommendation(id: tripRecId)
                    postingProgress = nil
                    throw error
                }
                postingProgress = nil
                didSaveDraft = asDraft
                withAnimation { didPost = true }
                isSaving = false
                return
            }

            // List items become their own Rex, linked to the list — the
            // same shape as trip stops above, just addressed by
            // list_id/list_section/show_in_feed instead of trip_id
            // /trip_section (#118). Every item defaults to visible on the
            // feed, same as a fresh import; the toggle to hide one lives in
            // ListDetailView after the fact.
            // Sept 5 — a list's items come from the ordered heading/item
            // builder now, same as a trip's itinerary.
            let listItems = listEntries.resolvedStops
            if category == .list, !listItems.isEmpty {
                let listRecId = try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: note.isEmpty ? nil : note,
                    returningId: true
                )
                var createdItemRecIds: [String] = []
                do {
                    for (index, draftItem) in listItems.enumerated() {
                        postingProgress = listItems.count > 1
                            ? "Adding item \(index + 1) of \(listItems.count)…" : "Adding item…"
                        let childItemId = try await RexAPI.shared.createItem(
                            type: draftItem.type.rawValue,
                            title: draftItem.title,
                            subtitle: draftItem.subtitle,
                            address: draftItem.address,
                            genre: draftItem.genre,
                            linkURL: draftItem.linkURL,
                            externalId: draftItem.externalId,
                            externalSource: draftItem.externalSource,
                            imageURL: draftItem.photoURL ?? draftItem.imageURL,
                            lat: draftItem.lat,
                            lng: draftItem.lng
                        )
                        let childRecId = try await RexAPI.shared.createRecommendation(
                            itemId: childItemId,
                            rating: draftItem.rating,
                            note: draftItem.note.isEmpty ? nil : draftItem.note,
                            listId: listRecId,
                            listSection: draftItem.section,
                            // Sept 5 — "each item becomes its own Rex as well
                            // as part of the list but only the list will be
                            // visible in the feed". Was true, which is what
                            // put every imported item on the feed as its own
                            // card.
                            showInFeed: false,
                            returningId: true
                        )
                        createdItemRecIds.append(childRecId)
                    }
                } catch {
                    postingProgress = "Undoing partial list…"
                    for id in createdItemRecIds { try? await RexAPI.shared.deleteRecommendation(id: id) }
                    try? await RexAPI.shared.deleteRecommendation(id: listRecId)
                    postingProgress = nil
                    throw error
                }
                postingProgress = nil
                withAnimation { didPost = true }
                isSaving = false
                return
            }

            switch mode {
            case .rated:
                let newRecId = try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: note.isEmpty ? nil : note,
                    // A trip's cover photo is a thumbnail, not a card photo —
                    // see the trip branch above.
                    photoURLs: category == .trip ? [] : photoURLs,
                    anonymous: anonymous,
                    returningId: !taggedFriendIds.isEmpty,
                    asDraft: category == .trip && asDraft
                )
                if !taggedFriendIds.isEmpty {
                    try? await RexAPI.shared.setTaggedFriends(recommendationId: newRecId, userIds: Array(taggedFriendIds))
                }
                didWant = false
                didSaveDraft = category == .trip && asDraft
            case .want:
                try await RexAPI.shared.createWant(
                    itemId: itemId,
                    note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
                )
                didWant = true
                lastWantItemId = itemId
            }
            withAnimation { didPost = true }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    /// Clear the form but keep the category — you're usually adding another of
    /// the same kind. Tags deliberately don't carry over; that was a bug once.
    private func undoWant() async {
        guard let itemId = lastWantItemId else { return }
        isUndoingWant = true
        do {
            try await RexAPI.shared.removeWant(itemId: itemId)
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isUndoingWant = false
    }

    private func startAnother() {
        withAnimation {
            didPost = false
            didWant = false
            didSaveDraft = false
            lastWantItemId = nil
            resetDraftFields()
        }
    }

    /// Everything typed into the form for one category, cleared whenever
    /// that draft is abandoned — either by posting (startAnother) or by
    /// backing out to the category picker to start a different kind of Rex.
    /// The Back button used to only clear category/manualEntry/picked/hits,
    /// which is how a list ended up carrying a trip's leftover subtitle:
    /// pick Trip, type a title and subtitle, hit Back, pick List instead —
    /// subtitle (and address/tripStops/listItems/etc, none of which mean
    /// the same thing for a List) rode along into the post untouched, and
    /// since ListDetailView has no subtitle field to fix it afterwards, it
    /// was stuck there for good.
    private func resetDraftFields() {
        title = ""
        note = ""
        productLink = ""
        photoURLs = []
        subcategories = []
        taggedFriendIds = []
        anonymous = false
        rating = 8
        picked = nil
        hits = []
        manualEntry = false
        errorMessage = nil
        subtitle = ""
        address = ""
        tripEntries = []
        tripMonth = nil
        tripYear = nil
        listItems = []
        listEntries = []
        customListKind = ""
        showingCustomListKind = false
        recipeText = ""
    }

    private var successState: some View {
        VStack(spacing: 16) {
            Image(systemName: didWant ? "bookmark.fill" : didSaveDraft ? "doc.text" : "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(RexColor.primary)
            Text(didWant ? "Saved" : didSaveDraft ? "Saved as draft" : "Posted")
                .font(RexFont.display(26, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text(
                didWant ? "\"\(title)\" is on your want-to list."
                : didSaveDraft ? "\"\(title)\" is saved in Drafts. Nobody sees it until you publish."
                : "\"\(title)\" is in your feed."
            )
                .font(.system(size: 15))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
            // People rarely add just one, so offer to go again without
            // having to come back in through the + button.
            Button("Add another") { startAnother() }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RexColor.primary)
                .foregroundStyle(RexColor.primaryForeground)
                .clipShape(Capsule())
                .padding(.top, 8)

            Button("Back to feed") { onDone() }
                .font(RexFont.text(15, weight: .semibold))
                .foregroundStyle(RexColor.primary)

            // Tapping "Want to try" used to be a one-way door — the only
            // way back was finding it in Collections and swiping it away.
            if didWant, lastWantItemId != nil {
                Button {
                    Task { await undoWant() }
                } label: {
                    if isUndoingWant {
                        ProgressView().tint(RexColor.destructive)
                    } else {
                        Text("Undo").font(RexFont.text(14, weight: .semibold))
                    }
                }
                .foregroundStyle(RexColor.destructive)
                .disabled(isUndoingWant)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(RexColor.destructive)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
