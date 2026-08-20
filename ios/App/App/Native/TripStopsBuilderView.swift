import SwiftUI

/// A stop being added to a trip before the trip is posted.
struct DraftStop: Identifiable, Equatable {
    let id = UUID()
    var type: RexCategory
    var title: String
    var subtitle: String?
    var address: String?
    var lat: Double?
    var lng: Double?
    var genre: String?
    var imageURL: String?
    var externalId: String?
    var externalSource: String?
    /// 0 means unrated — ratings are optional on stops.
    var rating: Double
    var note: String
    /// Optional heading, e.g. "Brunch".
    var section: String?

    static func == (a: DraftStop, b: DraftStop) -> Bool { a.id == b.id }
}

let rexSectionSuggestions = [
    "Breakfast", "Brunch", "Lunch", "Dinner", "Coffee", "Drinks",
    "Museums", "Sights", "Shopping", "Stay", "Nightlife",
]

/// Build a trip's itinerary inline, mirroring the web TripStopsBuilder:
/// stops grouped under optional headings, Google search per stop, optional
/// ratings.
///
/// Reused as-is for a manually-built List (#118 follow-up) via the wording
/// and `itemTypes` parameters below — a List's items are exactly the same
/// shape as a Trip's stops (grouped under optional headings, own rating,
/// own note), so this stayed one view with the trip-specific strings
/// swappable rather than forking a near-identical copy.
struct TripStopsBuilderView: View {
    @Binding var stops: [DraftStop]

    /// Singular word for one entry — "stop" for a trip, "item" for a list.
    /// Drives the header count, the "Add a ___" button, and the "New ___"
    /// form title; all pluralize by appending "s".
    var singularNoun: String = "stop"
    /// What the entries belong to, for the header and footnote — "trip" or
    /// "list".
    var containerNoun: String = "trip"
    /// Only the categories offered for this container's entries. A trip's
    /// stops are almost always a place; a list can hold anything.
    var itemTypes: [RexCategory] = [.place, .event, .recipe, .other]
    /// The document-import hand-off only exists for trips today (#38) — a
    /// List already has its own "Import from doc" entry point one screen up
    /// in AddRexView, so this would just be a confusing second link there.
    var showImportLink: Bool = true

    @State private var adding = false
    @State private var type: RexCategory = .place
    @State private var title = ""
    @State private var subtitle = ""
    @State private var address = ""
    @State private var section = ""
    @State private var rating: Double = 0
    @State private var note = ""
    @State private var picked: RexSearchHit?
    @State private var hits: [RexSearchHit] = []
    @State private var searchTask: Task<Void, Never>?
    /// #135 — true while a manually-typed place/event is being geocoded
    /// before it's actually added.
    @State private var isGeocoding = false

    private var stopTypes: [RexCategory] { itemTypes }

    /// "a stop" vs "an item" — the only two nouns this view is ever asked
    /// to pluralize, but a hard-coded "a" broke the moment "item" showed up.
    private var singularNounWithArticle: String {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        let article = vowels.contains(singularNoun.lowercased().first ?? " ") ? "an" : "a"
        return "\(article) \(singularNoun)"
    }

    /// Group stops under their heading, keeping first-appearance order.
    private var groups: [(heading: String, stops: [DraftStop])] {
        var result: [(heading: String, stops: [DraftStop])] = []
        for stop in stops {
            let h = (stop.section ?? "").trimmingCharacters(in: .whitespaces)
            if let i = result.firstIndex(where: { $0.heading.caseInsensitiveCompare(h) == .orderedSame }) {
                result[i].stops.append(stop)
            } else {
                result.append((heading: h, stops: [stop]))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            HStack {
                Text("\(singularNoun.capitalized)s on this \(containerNoun)")
                    .font(RexFont.text(14, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Spacer()
                Text("\(stops.count) \(stops.count == 1 ? singularNoun : "\(singularNoun)s")")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: RexSpacing.sm) {
                    if !group.heading.isEmpty {
                        Text(group.heading)
                            .font(RexFont.display(17, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                    }
                    ForEach(group.stops) { stop in
                        HStack(alignment: .top, spacing: RexSpacing.md) {
                            Image(systemName: stop.type.symbol)
                                .font(.system(size: 14))
                                .foregroundStyle(RexColor.primary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.title)
                                    .font(RexFont.text(15, weight: .medium))
                                    .foregroundStyle(RexColor.foreground)
                                if let sub = stop.address ?? stop.subtitle, !sub.isEmpty {
                                    Text(sub)
                                        .font(RexFont.text(12))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .lineLimit(1)
                                }
                                if !stop.note.isEmpty {
                                    Text(stop.note)
                                        .font(RexFont.text(13))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if stop.rating > 0 {
                                Text(String(format: "%.0f", stop.rating))
                                    .font(RexFont.text(12, weight: .semibold))
                                    .foregroundStyle(RexColor.primary)
                            }
                            Button {
                                stops.removeAll { $0.id == stop.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11))
                                    .foregroundStyle(RexColor.mutedForeground)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(RexSpacing.md)
                        .rexCard()
                    }
                }
            }

            if adding {
                addForm
            } else {
                Button {
                    adding = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add \(singularNounWithArticle)")
                    }
                }
                .buttonStyle(RexSecondaryButtonStyle())
            }

            Text("Each \(singularNoun) becomes its own Rex as well as part of the \(containerNoun).")
                .font(RexFont.text(11))
                .foregroundStyle(RexColor.mutedForeground)

            // Importing a curated itinerary means picking a Word/Excel file and
            // parsing it — something you'd realistically do at a desk. Rather
            // than rebuild that on the phone, hand off to the web importer,
            // which already handles headings and links. Lists have no
            // equivalent web hand-off yet, hence showImportLink.
            if showImportLink {
                Link(destination: URL(string: "https://kathrynkfinnis-rgb-rex-app.kathryn-k-finnis.workers.dev/import")!) {
                    HStack(spacing: RexSpacing.sm) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 13))
                        Text("Import a \(containerNoun) from a document")
                            .font(RexFont.text(13, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(RexColor.primary)
                    .padding(RexSpacing.md)
                    .background(RexColor.badgeBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                }
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            HStack {
                Text("New \(singularNoun)").font(RexFont.text(14, weight: .semibold))
                Spacer()
                Button("Cancel") { resetForm(); adding = false }
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    ForEach(stopTypes, id: \.self) { t in
                        Button {
                            type = t; picked = nil; hits = []; title = ""
                        } label: {
                            Text(t.label)
                                .font(RexFont.text(13, weight: type == t ? .semibold : .regular))
                                .foregroundStyle(type == t ? RexColor.primaryForeground : RexColor.mutedForeground)
                                .padding(.horizontal, RexSpacing.md)
                                .padding(.vertical, 6)
                                .background(type == t ? RexColor.primary : RexColor.card)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(type == t ? RexColor.primary : RexColor.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            input("Name", text: $title)
                .onChange(of: title) { _, _ in scheduleSearch() }

            // Google suggestions for places and events.
            if picked == nil && !hits.isEmpty {
                VStack(spacing: 0) {
                    ForEach(hits.prefix(5)) { hit in
                        Button {
                            picked = hit
                            title = hit.title
                            address = hit.address ?? ""
                            hits = []
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
                        if hit.id != hits.prefix(5).last?.id {
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

            Text("Heading (optional)")
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    ForEach(rexSectionSuggestions, id: \.self) { s in
                        Button {
                            section = section.caseInsensitiveCompare(s) == .orderedSame ? "" : s
                        } label: {
                            Text(s)
                                .font(RexFont.text(12))
                                .foregroundStyle(section.caseInsensitiveCompare(s) == .orderedSame
                                                 ? RexColor.primaryForeground : RexColor.mutedForeground)
                                .padding(.horizontal, RexSpacing.md)
                                .padding(.vertical, 5)
                                .background(section.caseInsensitiveCompare(s) == .orderedSame
                                            ? RexColor.primary : RexColor.card)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(RexColor.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            input("Or type your own heading", text: $section)

            Text("Rating (optional)")
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            RexRatingPicker(value: $rating, clearable: true)

            input("Why are you Rexing it?", text: $note)

            Button {
                addStop()
            } label: {
                if isGeocoding {
                    HStack(spacing: RexSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Locating…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Add \(singularNoun)").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(RexPrimaryButtonStyle())
            .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .disabled(isGeocoding || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(RexSpacing.cardPadding)
        .rexCard()
    }

    private func input(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(RexFont.text(15))
            .padding(RexSpacing.md)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard picked == nil, type == .place || type == .event else { hits = []; return }
        let term = title
        guard term.trimmingCharacters(in: .whitespaces).count >= 2 else { hits = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let results = await RexSearch.search(category: type, query: term)
            if Task.isCancelled { return }
            await MainActor.run { hits = results }
        }
    }

    private func addStop() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        var lat = picked?.lat
        var lng = picked?.lng

        func finish() {
            stops.append(DraftStop(
                type: type,
                title: trimmed,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                lat: lat,
                lng: lng,
                genre: picked?.genre,
                imageURL: picked?.imageURL,
                externalId: picked?.externalId,
                externalSource: picked?.externalSource,
                rating: rating,
                note: note.trimmingCharacters(in: .whitespaces),
                // Heading persists so several stops can be added under one.
                section: section.trimmingCharacters(in: .whitespaces).isEmpty ? nil : section.trimmingCharacters(in: .whitespaces)
            ))
            resetForm(keepSection: true)
            adding = false
        }

        // #135 — a stop typed by hand (no search suggestion tapped) had no
        // coordinates at all and so never got a map pin. Geocode it from
        // whatever's most specific — the address if one was given, else
        // the name — before adding it. Only for place/event: a recipe or
        // "other" stop was never going to have a pin anyway.
        guard picked == nil, lat == nil, (type == .place || type == .event),
              !(trimmedAddress.isEmpty && trimmed.isEmpty) else {
            finish()
            return
        }
        isGeocoding = true
        Task {
            let located = await RexSearch.geocode(trimmedAddress.isEmpty ? trimmed : trimmedAddress)
            lat = located?.lat
            lng = located?.lng
            isGeocoding = false
            finish()
        }
    }

    private func resetForm(keepSection: Bool = false) {
        title = ""; subtitle = ""; address = ""; note = ""
        rating = 0; picked = nil; hits = []; type = .place
        if !keepSection { section = "" }
    }
}
