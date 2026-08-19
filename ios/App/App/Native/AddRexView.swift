import SwiftUI

/// v1 scope: category picker → manual entry form → post.
/// Skips live external search (Google/TMDB/etc — those are our own server functions over a
/// different RPC protocol, not plain Supabase REST) and skips Trips (needs the stops builder).
/// "Enter details manually" is exactly the fallback path the web app already offers, so this
/// is a real, working subset of Add a Rex rather than a stub.
struct AddRexView: View {
    var onDone: () -> Void

    // Trip sits second, as on the web. A trip is created as a normal Rex here
    // and stops get added to it afterwards from the trip screen.
    private let creatableCategories: [RexCategory] = [.place, .trip, .book, .movie, .tv, .podcast, .recipe, .event, .other]

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
    @State private var subcategories: Set<String> = []
    @State private var productLink = ""
    @State private var tripStops: [DraftStop] = []
    @State private var recipeText = ""
    /// Searchable categories open on a search field; the full form only
    /// appears once something's picked or you choose to type it in manually.
    @State private var manualEntry = false
    @State private var showingListsImport = false

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if category != nil && !didPost {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            withAnimation {
                                category = nil
                                manualEntry = false
                                picked = nil
                                hits = []
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
                        VStack(spacing: 8) {
                            Image(systemName: cat.symbol).font(.system(size: 22)).foregroundStyle(RexColor.primary)
                            Text(cat.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(RexColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // #109 — same entry point the web offers ("Import a collection"),
            // but this one runs the extraction itself rather than deep
            // -linking to the web importer: paste text in, review what came
            // out, save as a Trip or a Collection.
            Button {
                showingListsImport = true
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
                        Text("Import a list")
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
        .sheet(isPresented: $showingListsImport) {
            ListsImportView(onDone: { showingListsImport = false; onDone() })
        }
    }

    @ViewBuilder
    private func form(for category: RexCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let searchable: Set<RexCategory> = [.place, .event, .book, .movie, .tv, .podcast]
            let searchFirst = searchable.contains(category) && picked == nil && !manualEntry

            field(searchFirst ? "Search" : "Title", text: $title,
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
            field(subtitleLabel(for: category), text: $subtitle, placeholder: "Optional")

            if category == .place || category == .event {
                field("Address", text: $address, placeholder: "Optional")
            }

            if category == .trip {
                TripStopsBuilderView(stops: $tripStops)
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
            // field there is just another box to ignore.
            if ![.book, .movie, .tv, .podcast].contains(category) {
                field("Link (optional)", text: $productLink, placeholder: "https://…")
                    .textInputAutocapitalization(.never)
            }

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

                Text("Photos").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexColor.foreground)
                PhotoPickerView(photoURLs: $photoURLs)

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
                    Text(mode == .rated ? "Post" : addToWantLabel(for: category))
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
        let searchable: Set<RexCategory> = [.place, .event, .book, .movie, .tv, .podcast]

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
                    ForEach(hits.prefix(6)) { hit in
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

                        if hit.id != hits.prefix(6).last?.id {
                            Rectangle().fill(RexColor.divider).frame(height: 1)
                        }
                    }
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

    private func placeholderTitle(for category: RexCategory) -> String {
        switch category {
        case .place: return "Dishoom"
        case .book: return "The Hobbit"
        case .movie: return "Inception"
        case .tv: return "Breaking Bad"
        case .podcast: return "This American Life"
        case .recipe: return "Koshari"
        case .event: return "Glastonbury"
        default: return "Title"
        }
    }

    private func post(category: RexCategory, asDraft: Bool = false) async {
        isSaving = true
        errorMessage = nil
        postingProgress = nil
        do {
            let itemId = try await RexAPI.shared.createItem(
                type: category.rawValue,
                title: title.trimmingCharacters(in: .whitespaces),
                subtitle: subtitle.isEmpty ? nil : subtitle,
                address: (category == .place || category == .event) && !address.isEmpty ? address : nil,
                hit: picked,
                genre: subcategories.isEmpty ? nil : subcategories.sorted().joined(separator: ", "),
                linkURL: productLink.trimmingCharacters(in: .whitespaces).isEmpty ? nil : productLink.trimmingCharacters(in: .whitespaces),
                // #21 "guaranteed image": recipes have no catalogue to
                // auto-import a cover photo from the way books/movies do,
                // so every recipe card fell back to the same generic
                // fork-and-knife placeholder. If a photo was attached to
                // the post, promote it to the item's own cover too - fine
                // if there isn't one (no forced upload step), but a real
                // photo when there is one.
                imageURL: category == .recipe ? photoURLs.first : nil,
                recipeText: category == .recipe && !recipeText.isEmpty ? recipeText : nil
            )
            // Trip stops become their own Rex, linked to the trip.
            if category == .trip, !tripStops.isEmpty {
                let tripRecId = try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: note.isEmpty ? nil : note,
                    photoURLs: photoURLs,
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

            switch mode {
            case .rated:
                try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: note.isEmpty ? nil : note,
                    photoURLs: photoURLs,
                    anonymous: anonymous,
                    asDraft: category == .trip && asDraft
                )
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
            title = ""
            note = ""
            productLink = ""
            photoURLs = []
            subcategories = []
            anonymous = false
            rating = 8
            picked = nil
            hits = []
            manualEntry = false
            errorMessage = nil
        }
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
