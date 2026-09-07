import SwiftUI

/// Edit or delete one of your own Rex — rating, note, tags and photos.
/// Mirrors the web EditRecommendationDialog.
struct EditRexView: View {
    let rec: FeedRecommendation
    var onSaved: () -> Void
    var onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var wantToTry: Bool
    @State private var rating: Double
    @State private var note: String
    @State private var photoURLs: [String]
    @State private var tags: [String]
    @State private var tagDraft = ""
    /// #125 — the item's own shared thumbnail (its catalogue cover, shown on
    /// every card and the item page), not the "Photos" section above which is
    /// this one take's own attached photos. Same shared-catalogue model as
    /// title editing. A single-element array so PhotoPickerView's existing
    /// add/remove UI works unmodified with maxPhotos: 1.
    @State private var thumbnailURLs: [String]
    /// #134 — was List-items-only (ListDetailView's own toggle); the
    /// underlying column already lived on every recommendation regardless
    /// of type, it just only ever got set explicitly for list items. Any
    /// Rex can hide from the main feed now while still showing wherever it
    /// was deliberately looked up (your own profile, this item's page).
    @State private var showInFeed: Bool
    /// #45 — same shared-catalogue model as title/thumbnail. Only offered
    /// for the same categories AddRexView itself offers it to at creation
    /// (everything except book/movie/tv/podcast/list — those come from a
    /// catalogue with their own page, or aren't a single thing to link to).
    @State private var linkURL: String
    /// #162 — friends tagged on this Rex.
    @State private var taggedFriendIds: Set<String>
    /// #172 — recipe ingredients/method, previously only editable at
    /// creation. RecipeEditorView's own parse()/serialize() round-trip
    /// the same free-text format createItem already stores.
    @State private var recipeText: String
    /// #183 — a place/event's address, and the coordinates geocoded from
    /// it, used to only ever get set once (a live search pick at creation,
    /// or the map's own self-heal). This is the first way to fix either
    /// after the fact — a stop added by hand with a typo, a place that's
    /// moved, or a pin that geocoded to the wrong branch entirely.
    @State private var address: String
    @State private var lat: Double?
    @State private var lng: Double?
    @State private var isGeocoding = false
    @State private var geocodeError: String?
    /// "When you go to edit one of your stops... it doesn't come up with
    /// the ability to auto populate from Google etc" — AddRexView/
    /// AddTripStopSheet both search-as-you-type against the same live
    /// catalogue; editing only ever had a plain text field plus a manual
    /// "re-check" against whatever's already typed. This is that same
    /// live search, added here too.
    @State private var addressHits: [RexSearchHit] = []
    @State private var addressSearchTask: Task<Void, Never>?
    /// #183 — AddRexView's own subcategory chips (e.g. Restaurant/Activity
    /// for a place), stored as the same sorted comma-joined string
    /// splitGenres() reads everywhere. Free-text here rather than
    /// rebuilding that chip picker — same format, editable after the fact.
    @State private var genre: String
    @State private var isSaving = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    private var category: RexCategory { RexCategory(rawType: rec.items?.type) }
    private var offersLink: Bool {
        !([.book, .movie, .tv, .podcast, .list] as [RexCategory]).contains(category)
    }
    private var offersAddress: Bool { category == .place || category == .event }

    /// wants and recommendations are two separate tables (see fetchWantsFeed) —
    /// a want has no rating, no photos, no tags of its own, so there's a real
    /// row-id underneath the synthetic "want-<id>" this card carries. #124:
    /// Kathryn wants to flip between "still want to try" and "done, rate it"
    /// from the same edit sheet, which means creating a row in the other
    /// table and deleting this one, not just patching a column.
    private var wantRowId: String? {
        guard rec.isWant, rec.id.hasPrefix("want-") else { return nil }
        return String(rec.id.dropFirst("want-".count))
    }

    init(rec: FeedRecommendation, onSaved: @escaping () -> Void, onDeleted: @escaping () -> Void) {
        self.rec = rec
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _title = State(initialValue: rec.items?.title ?? "")
        _wantToTry = State(initialValue: rec.isWant)
        _rating = State(initialValue: rec.rating)
        _note = State(initialValue: rec.note ?? "")
        _photoURLs = State(initialValue: rec.photo_urls ?? (rec.photo_url.map { [$0] } ?? []))
        _tags = State(initialValue: rec.tags ?? [])
        _thumbnailURLs = State(initialValue: rec.items?.image_url.map { [$0] } ?? [])
        _showInFeed = State(initialValue: rec.show_in_feed ?? true)
        _linkURL = State(initialValue: rec.items?.link_url ?? "")
        _taggedFriendIds = State(initialValue: Set(rec.taggedFriends.map { $0.id }))
        _recipeText = State(initialValue: rec.items?.recipe_text ?? "")
        _address = State(initialValue: rec.items?.address ?? "")
        _lat = State(initialValue: rec.items?.lat)
        _lng = State(initialValue: rec.items?.lng)
        _genre = State(initialValue: rec.items?.genre ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.xl) {
                    if rec.items != nil {
                        VStack(alignment: .leading, spacing: RexSpacing.sm) {
                            Text("Title").font(RexFont.text(14, weight: .semibold))
                            // This is the shared catalogue entry's title, not
                            // just your own take on it — anyone who's Rex'd
                            // the same thing sees the fix too, same as
                            // correcting a place's address does. Worth it:
                            // there was previously no way to fix a typo'd
                            // title at all, short of deleting and re-adding.
                            TextField("Title", text: $title)
                                .font(RexFont.display(22, weight: .semibold))
                                .foregroundStyle(RexColor.foreground)
                        }

                        // #125 — same shared-catalogue model as the title
                        // above: this is the cover shown on every card and
                        // the item page, not this take's own "Photos" below.
                        VStack(alignment: .leading, spacing: RexSpacing.sm) {
                            Text("Thumbnail").font(RexFont.text(14, weight: .semibold))
                            PhotoPickerView(photoURLs: $thumbnailURLs, maxPhotos: 1)
                        }

                        // #45 — was write-once at creation (AddRexView's own
                        // "Link" field); this is the same shared-catalogue
                        // field, just now fixable after the fact too.
                        if offersLink {
                            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                                Text("Link").font(RexFont.text(14, weight: .semibold))
                                TextField("https://…", text: $linkURL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(RexFont.text(15))
                                    .padding(RexSpacing.md)
                                    .background(RexColor.card)
                                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                            .stroke(RexColor.border, lineWidth: 1)
                                    )
                            }
                        }
                    }

                    // #183 — same shared-catalogue model as title/link:
                    // fixes an address typo, or a place that's moved, for
                    // everyone who's Rex'd it — not just this take. Coords
                    // only ever move together with a fresh geocode, never
                    // edited directly, so they can't drift out of sync with
                    // whatever address is actually showing.
                    if offersAddress {
                        VStack(alignment: .leading, spacing: RexSpacing.sm) {
                            Text("Address").font(RexFont.text(14, weight: .semibold))
                            TextField("Address", text: $address, axis: .vertical)
                                .font(RexFont.text(15))
                                .padding(RexSpacing.md)
                                .background(RexColor.card)
                                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                        .stroke(RexColor.border, lineWidth: 1)
                                )
                                .onChange(of: address) { _, _ in scheduleAddressSearch() }

                            if !addressHits.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(addressHits) { hit in
                                        Button {
                                            applyAddressHit(hit)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(hit.title)
                                                    .font(RexFont.text(14, weight: .medium))
                                                    .foregroundStyle(RexColor.foreground)
                                                if let sub = hit.address ?? hit.subtitle, !sub.isEmpty {
                                                    Text(sub)
                                                        .font(RexFont.text(12))
                                                        .foregroundStyle(RexColor.mutedForeground)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(RexSpacing.sm)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        if hit.id != addressHits.last?.id {
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

                            HStack(spacing: RexSpacing.sm) {
                                Button {
                                    Task { await recheckLocation() }
                                } label: {
                                    if isGeocoding {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Re-check location", systemImage: "mappin.and.ellipse")
                                    }
                                }
                                .font(RexFont.text(13, weight: .medium))
                                .disabled(isGeocoding || address.trimmingCharacters(in: .whitespaces).isEmpty)
                                if lat != nil, lng != nil {
                                    Label("Pin set", systemImage: "checkmark.circle.fill")
                                        .font(RexFont.text(12))
                                        .foregroundStyle(RexColor.mutedForeground)
                                }
                            }
                            // "This recheck location button doesn't work" —
                            // it was correctly disabled (nothing to geocode
                            // with an empty address — common for a
                            // document-imported place, which never gets one
                            // set at all, per #135), just silently, with no
                            // way to tell "disabled, type an address first"
                            // apart from "broken."
                            if address.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text("Type an address above, then re-check to set the pin.")
                                    .font(RexFont.text(12))
                                    .foregroundStyle(RexColor.mutedForeground)
                            }
                            if let geocodeError {
                                Text(geocodeError)
                                    .font(RexFont.text(12))
                                    .foregroundStyle(RexColor.destructive)
                            }
                        }
                    }

                    // #183 — "Type of place"/"Type" at creation (AddRexView's
                    // FlowChips, keyed by rexSubcategories) was write-once
                    // too. Free-text here rather than rebuilding that chip
                    // picker, but same category gate and same comma-joined
                    // format, so a value set either way reads back fine.
                    if let options = rexSubcategories[category], !options.isEmpty {
                        VStack(alignment: .leading, spacing: RexSpacing.sm) {
                            Text("Subcategories").font(RexFont.text(14, weight: .semibold))
                            TextField("e.g. \(options.first ?? "Type")", text: $genre)
                                .font(RexFont.text(15))
                                .padding(RexSpacing.md)
                                .background(RexColor.card)
                                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                        .stroke(RexColor.border, lineWidth: 1)
                                )
                            Text("Comma separated, same as when you first added it.")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }

                    // #172 — was write-once at creation, same gap
                    // title/link/thumbnail had before their own fixes.
                    if category == .recipe {
                        RecipeEditorView(recipeText: $recipeText, title: $title)
                    }

                    // #124: a want and a Rex are different tables underneath,
                    // so this switch is what decides which one saving writes
                    // to — not just a display toggle.
                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Status").font(RexFont.text(14, weight: .semibold))
                        Picker("Status", selection: $wantToTry) {
                            Text("Rated").tag(false)
                            Text("Still want to try").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if wantToTry {
                            Text("Photos and tags don't carry over to a want-to-try — rate it once you've actually been.")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }

                    if !wantToTry {
                        VStack(alignment: .leading, spacing: RexSpacing.sm) {
                            Text("Your rating").font(RexFont.text(14, weight: .semibold))
                            RexRatingPicker(value: $rating, clearable: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Note").font(RexFont.text(14, weight: .semibold))
                        TextField("What did you think?", text: $note, axis: .vertical)
                            .font(RexFont.text(15))
                            .lineLimit(3...6)
                            .padding(RexSpacing.md)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                    .stroke(RexColor.border, lineWidth: 1)
                            )
                    }

                    if !wantToTry {
                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Tags").font(RexFont.text(14, weight: .semibold))
                        if !tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: RexSpacing.xs) {
                                    ForEach(tags, id: \.self) { tag in
                                        HStack(spacing: 4) {
                                            Text("#\(tag)").font(RexFont.text(12, weight: .medium))
                                            Button {
                                                tags.removeAll { $0 == tag }
                                            } label: {
                                                Image(systemName: "xmark").font(.system(size: 9))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .foregroundStyle(RexColor.badgeForeground)
                                        .padding(.horizontal, RexSpacing.sm)
                                        .padding(.vertical, 4)
                                        .background(RexColor.badgeBackground)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        TextField("Add a tag, press return", text: $tagDraft)
                            .font(RexFont.text(15))
                            .autocorrectionDisabled()
                            .onSubmit(addTag)
                            .padding(RexSpacing.md)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                    .stroke(RexColor.border, lineWidth: 1)
                            )
                    }
                    }

                    if !wantToTry {
                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Tag friends").font(RexFont.text(14, weight: .semibold))
                        FriendTagPickerView(selectedIds: $taggedFriendIds)
                    }
                    }

                    if !wantToTry {
                        VStack(alignment: .leading, spacing: RexSpacing.sm) {
                            Text("Photos").font(RexFont.text(14, weight: .semibold))
                            PhotoPickerView(photoURLs: $photoURLs)
                        }
                    }

                    // #134 — was List-items-only. Anything you've Rex'd can
                    // sit off the main feed (still on your profile, still on
                    // the item's own page) without needing to delete it.
                    if !wantToTry {
                        Toggle(isOn: $showInFeed) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show on feed").font(RexFont.text(14, weight: .semibold))
                                Text("Still shows on your profile and this item's page either way.")
                                    .font(RexFont.text(12))
                                    .foregroundStyle(RexColor.mutedForeground)
                            }
                        }
                        .tint(RexColor.primary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(RexColor.primaryForeground)
                        } else {
                            Text("Save changes")
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(isSaving)

                    Button("Delete this Rex", role: .destructive) { confirmDelete = true }
                        .font(RexFont.text(14, weight: .semibold))
                        .foregroundStyle(RexColor.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, RexSpacing.xl)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Edit Rex")
            .rexDismissableKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Delete this Rex?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { Task { await deleteRex() } }
            } message: {
                Text("This can't be undone.")
            }
        }
        .tint(RexColor.primary)
    }

    /// Same debounced search-as-you-type AddTripStopSheet's own address
    /// field uses. category is always .place or .event here (offersAddress
    /// gates the whole section on exactly those), matching what
    /// RexSearch.search expects.
    private func scheduleAddressSearch() {
        addressSearchTask?.cancel()
        let term = address
        guard term.trimmingCharacters(in: .whitespaces).count >= 2 else { addressHits = []; return }
        addressSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let results = await RexSearch.search(category: category, query: term)
            if Task.isCancelled { return }
            await MainActor.run { addressHits = results }
        }
    }

    /// A picked suggestion already carries real coordinates — no need for
    /// the separate "re-check" geocode round-trip a hand-typed address
    /// still needs.
    private func applyAddressHit(_ hit: RexSearchHit) {
        address = hit.address ?? hit.title
        if let hitLat = hit.lat, let hitLng = hit.lng {
            lat = hitLat
            lng = hitLng
        }
        addressHits = []
        geocodeError = nil
    }

    /// #183 — re-geocodes whatever's currently typed in the address field.
    /// Doesn't save anything itself (that's still "Save changes", same as
    /// every other field here) — just updates lat/lng in memory so you can
    /// see it worked (or didn't) before committing.
    private func recheckLocation() async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isGeocoding = true
        geocodeError = nil
        if let located = await RexSearch.geocode(trimmed) {
            lat = located.lat
            lng = located.lng
        } else {
            geocodeError = "Couldn't find that address. You can still save the text as typed."
        }
        isGeocoding = false
    }

    private func addTag() {
        let t = tagDraft.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard !t.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }), tags.count < 8 else {
            tagDraft = ""
            return
        }
        tags.append(t)
        tagDraft = ""
    }

    private func save() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Title can't be empty."
            return
        }
        // A want turning into a Rex needs an actual rating — otherwise
        // "still want to try" -> "rated" would silently create a Rex nobody
        // rated, which is exactly the state this switch is meant to avoid.
        if wantRowId != nil, !wantToTry, rating <= 0 {
            errorMessage = "Pick a rating to mark this as done."
            return
        }
        isSaving = true
        errorMessage = nil
        // Commit a tag the user typed but didn't submit, so it isn't silently lost.
        addTag()
        do {
            // Only actually hits the network if it changed — every other
            // card sharing this item doesn't need a write on every save.
            if let item = rec.items, trimmedTitle != item.title {
                try await RexAPI.shared.updateItemTitle(itemId: rec.item_id, title: trimmedTitle)
            }
            let newThumbnail = thumbnailURLs.first
            if newThumbnail != rec.items?.image_url {
                try await RexAPI.shared.updateItemImageURL(itemId: rec.item_id, imageURL: newThumbnail)
            }
            if offersLink {
                let trimmedLink = linkURL.trimmingCharacters(in: .whitespaces)
                let newLink = trimmedLink.isEmpty ? nil : trimmedLink
                if newLink != rec.items?.link_url {
                    try await RexAPI.shared.updateItemLinkURL(itemId: rec.item_id, linkURL: newLink)
                }
            }
            if category == .recipe, recipeText != (rec.items?.recipe_text ?? "") {
                try await RexAPI.shared.updateItemRecipeText(itemId: rec.item_id, recipeText: recipeText)
            }
            if offersAddress {
                let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedAddress != (rec.items?.address ?? "") || lat != rec.items?.lat || lng != rec.items?.lng {
                    try await RexAPI.shared.updateItemAddressAndCoords(itemId: rec.item_id, address: trimmedAddress, lat: lat, lng: lng)
                }
            }
            if rexSubcategories[category] != nil {
                let trimmedGenre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedGenre != (rec.items?.genre ?? "") {
                    try await RexAPI.shared.updateItemGenre(itemId: rec.item_id, genre: trimmedGenre)
                }
            }

            switch (wantRowId, wantToTry) {
            case (_?, true):
                // Still a want, nothing to convert — just the note. Upserts
                // on (user_id, item_id), same row as before.
                try await RexAPI.shared.createWant(itemId: rec.item_id, note: note.isEmpty ? nil : note)
            case (let id?, false):
                // Want -> rated: this row moves tables. Create the
                // recommendation first — if that fails, the want is still
                // there rather than the Rex vanishing into neither table.
                let newRecId = try await RexAPI.shared.createRecommendation(
                    itemId: rec.item_id, rating: rating,
                    note: note.isEmpty ? nil : note,
                    photoURLs: photoURLs, tags: tags,
                    showInFeed: showInFeed,
                    returningId: !taggedFriendIds.isEmpty
                )
                if !taggedFriendIds.isEmpty {
                    try? await RexAPI.shared.setTaggedFriends(recommendationId: newRecId, userIds: Array(taggedFriendIds))
                }
                try await RexAPI.shared.deleteWant(id: id)
            case (nil, true):
                // Rated -> want: same ordering logic, create then delete.
                try await RexAPI.shared.createWant(itemId: rec.item_id, note: note.isEmpty ? nil : note)
                try await RexAPI.shared.deleteRecommendation(id: rec.id)
            case (nil, false):
                try await RexAPI.shared.updateRecommendation(
                    id: rec.id, rating: rating,
                    note: note.isEmpty ? nil : note,
                    photoURLs: photoURLs, tags: tags
                )
                // Separate call rather than folding into updateRecommendation
                // — that function is shared with every other Rex edit path
                // (want<->rated conversion aside) and #134 is the first
                // caller that ever needs this column touched.
                if showInFeed != (rec.show_in_feed ?? true) {
                    try await RexAPI.shared.updateShowInFeed(recommendationId: rec.id, showInFeed: showInFeed)
                }
                if taggedFriendIds != Set(rec.taggedFriends.map { $0.id }) {
                    try? await RexAPI.shared.setTaggedFriends(recommendationId: rec.id, userIds: Array(taggedFriendIds))
                }
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteRex() async {
        do {
            if let wantRowId {
                try await RexAPI.shared.deleteWant(id: wantRowId)
            } else {
                try await RexAPI.shared.deleteRecommendation(id: rec.id)
            }
            onDeleted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
