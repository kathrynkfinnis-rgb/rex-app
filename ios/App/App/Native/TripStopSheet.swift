import SwiftUI

/// Sept 2 trips rebuild — the "Add a stop" sheet.
///
/// Differences from the inline form it replaces (TripStopsBuilderView's
/// own `adding` state) and from AddTripStopSheet:
///
///   - Sub-category chips (Restaurant / Bar / Café …) instead of category
///     chips (Place / Event / Recipe / Other). A trip stop is essentially
///     always a place, so choosing "Place" every time was a wasted step;
///     what actually varies is what kind of place. Multi-select, and you
///     can add your own if none fit.
///   - No heading field — headings are their own button on the trip screen.
///   - "Why are you Rexing it" sits directly under the name, not below the
///     rating.
///   - One photo, which flows into the trip's carousel.
///   - The name field searches your own Rex as well as the wider internet,
///     so re-Rexing somewhere reuses the catalogue entry.
struct TripStopSheet: View {
    /// Which sub-categories to offer. Passed in rather than read here so
    /// this stays usable if trips ever want a different set.
    var subcategories: [String]
    /// Editing an existing stop rather than adding a new one.
    var existing: DraftStop? = nil
    var onSave: (DraftStop) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var picked: RexSearchHit?
    @State private var title = ""
    @State private var note = ""
    @State private var address = ""
    @State private var chosenSubcategories: Set<String> = []
    @State private var customSubcategory = ""
    @State private var showingCustomField = false
    @State private var rating: Double = 0
    @State private var photoURLs: [String] = []

    @State private var myHits: [MyRexHit] = []
    @State private var webHits: [RexSearchHit] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var isGeocoding = false

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !isGeocoding
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    subcategoryChips

                    field("Name") {
                        TextField("Search or type a name", text: $title)
                            .textFieldStyle(.plain)
                            .onChange(of: title) { _, _ in scheduleSearch() }
                    }
                    searchResults

                    field("Why are you Rexing it?") {
                        TextField("Best carbonara in Rome, book ahead", text: $note, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2...4)
                    }

                    VStack(alignment: .leading, spacing: RexSpacing.xs) {
                        Text("Photo").font(RexFont.text(13, weight: .semibold))
                        PhotoPickerView(photoURLs: $photoURLs, maxPhotos: 1)
                        Text("Also joins this trip's photos.")
                            .font(RexFont.text(11.5))
                            .foregroundStyle(RexColor.mutedForeground)
                    }

                    VStack(alignment: .leading, spacing: RexSpacing.xs) {
                        Text("Rating").font(RexFont.text(13, weight: .semibold))
                            + Text("  optional").font(RexFont.text(13)).foregroundColor(RexColor.placeholder)
                        RexRatingPicker(value: $rating, clearable: true)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isGeocoding {
                            ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                        } else {
                            Text(existing == nil ? "Add stop" : "Save stop").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle(existing == nil ? "New stop" : "Edit stop")
            .rexDismissableKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .onAppear(perform: prefill)
    }

    // MARK: - Pieces

    private var subcategoryChips: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    ForEach(offeredSubcategories, id: \.self) { name in
                        chip(name, isOn: chosenSubcategories.contains(name)) {
                            if chosenSubcategories.contains(name) {
                                chosenSubcategories.remove(name)
                            } else {
                                chosenSubcategories.insert(name)
                            }
                        }
                    }
                    chip("+ Add your own", isOn: false) { showingCustomField = true }
                }
                .padding(.horizontal, 1)
            }
            if showingCustomField {
                HStack(spacing: RexSpacing.sm) {
                    TextField("e.g. Wine bar", text: $customSubcategory)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                    Button("Add") {
                        let trimmed = customSubcategory.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        chosenSubcategories.insert(trimmed)
                        customSubcategory = ""
                        showingCustomField = false
                    }
                    .font(RexFont.text(14, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                }
            }
        }
    }

    /// The standard list, plus anything custom already chosen, so a custom
    /// tag stays visible (and removable) as a chip like any other.
    private var offeredSubcategories: [String] {
        let extras = chosenSubcategories.filter { !subcategories.contains($0) }.sorted()
        return subcategories + extras
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(RexFont.text(12.5, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isOn ? RexColor.primary : RexColor.card)
                .foregroundStyle(isOn ? RexColor.primaryForeground : RexColor.foreground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(RexColor.border, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.xs) {
            Text(label).font(RexFont.text(13, weight: .semibold)).foregroundStyle(RexColor.foreground)
            content()
                .padding(11)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if picked == nil, !myHits.isEmpty || !webHits.isEmpty {
            VStack(spacing: 0) {
                if !myHits.isEmpty {
                    resultHeader("Your Rex")
                    ForEach(myHits) { mine in resultRow(mine.hit, mine: true) { apply(mine) } }
                }
                if !webHits.isEmpty {
                    resultHeader("Search results")
                    ForEach(webHits) { hit in resultRow(hit, mine: false) { apply(hit) } }
                }
            }
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
        } else if isSearching {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching…").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
            }
        }
    }

    private func resultHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(RexColor.badgeForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RexSpacing.md)
            .padding(.vertical, 6)
            .background(RexColor.secondary)
    }

    private func resultRow(_ hit: RexSearchHit, mine: Bool, onPick: @escaping () -> Void) -> some View {
        Button {
            onPick()
        } label: {
            HStack(spacing: RexSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.title)
                        .font(RexFont.text(13.5, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(1)
                    if let sub = hit.address ?? hit.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(RexFont.text(11.5))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: RexSpacing.sm)
                if mine {
                    Text("Already Rex'd")
                        .font(RexFont.text(10, weight: .semibold))
                        .foregroundStyle(RexColor.badgeForeground)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RexColor.badgeBackground)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, RexSpacing.md)
            .padding(.vertical, RexSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(RexColor.divider).frame(height: 1) }
    }

    // MARK: - Behaviour

    private func prefill() {
        guard let existing, title.isEmpty else { return }
        title = existing.title
        note = existing.note
        address = existing.address ?? ""
        rating = existing.rating
        photoURLs = [existing.photoURL].compactMap { $0 }
        chosenSubcategories = Set(splitGenres(existing.genre))
    }

    private func scheduleSearch() {
        picked = nil
        searchTask?.cancel()
        let q = title.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { myHits = []; webHits = []; isSearching = false; return }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            async let mine = (try? await RexAPI.shared.searchMyRexItems(query: q)) ?? []
            async let web = RexSearch.search(category: .place, query: q)
            let (m, w) = await (mine, web)
            guard !Task.isCancelled else { return }
            myHits = m
            // Anything already in your own list shouldn't also appear as a
            // fresh search result underneath it.
            let mineTitles = Set(m.map { $0.hit.title.lowercased() })
            webHits = w.filter { !mineTitles.contains($0.title.lowercased()) }.prefix(6).map { $0 }
            isSearching = false
        }
    }

    /// Sept 7 — "comes up with my Rex but when I click on it it doesn't
    /// auto populate with the previous Rex". Picking one of your own now
    /// brings your rating and your note over too, not just the name — the
    /// point of recognising it as already yours.
    private func apply(_ mine: MyRexHit) {
        apply(mine.hit)
        if mine.rating > 0 { rating = mine.rating }
        if let previous = mine.note, !previous.isEmpty, note.isEmpty { note = previous }
    }

    private func apply(_ hit: RexSearchHit) {
        picked = hit
        title = hit.title
        if let address = hit.address { self.address = address }
        if let genre = hit.genre {
            for part in splitGenres(genre) { chosenSubcategories.insert(part) }
        }
        myHits = []
        webHits = []
        isSearching = false
    }

    private func save() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        var lat = picked?.lat
        var lng = picked?.lng
        // Typed by hand rather than picked, so it has no coordinates yet —
        // geocode before saving so it lands on the map like any other stop.
        if lat == nil, !address.trimmingCharacters(in: .whitespaces).isEmpty {
            isGeocoding = true
            if let coords = await RexSearch.geocode("\(trimmedTitle), \(address)") {
                lat = coords.lat
                lng = coords.lng
            }
            isGeocoding = false
        }

        let genre = chosenSubcategories.isEmpty ? nil : chosenSubcategories.sorted().joined(separator: ", ")
        let stop = DraftStop(
            type: .place,
            title: trimmedTitle,
            subtitle: picked?.subtitle,
            address: address.isEmpty ? picked?.address : address,
            lat: lat,
            lng: lng,
            genre: genre,
            imageURL: picked?.imageURL,
            externalId: picked?.externalSource == "rex" ? nil : picked?.externalId,
            externalSource: picked?.externalSource == "rex" ? nil : picked?.externalSource,
            rating: rating,
            note: note.trimmingCharacters(in: .whitespaces),
            section: existing?.section,
            photoURL: photoURLs.first
        )
        onSave(stop)
        dismiss()
    }
}
