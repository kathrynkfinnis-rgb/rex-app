import SwiftUI
import UIKit

/// Adds one stop/item directly to an already-published trip or list — the
/// "add" half of #122's trip editing (add/remove/reorder stops per heading,
/// edit headings), and (Aug 28) ListDetailView's equivalent, which never got
/// it the first time around — "editing the heading doesn't work" and "I want
/// to add a heading between cards ... but I can't" were both really "a List
/// only ever got TripStopsBuilderView's up-front builder, never #122's
/// after-the-fact editing tools at all." Mirrors TripStopsBuilderView's own
/// add-form (search, geocode, rating, note, heading) but posts straight to
/// the server instead of appending to a draft array, since this trip/list
/// already exists and has its own id.
struct AddTripStopSheet: View {
    enum Container { case trip(String), list(String) }
    let container: Container
    /// The trip or list's own name — "Lisbon, a long weekend". The only clue
    /// we have to which city a hand-typed stop is in, and the difference
    /// between finding Calma in Lisbon and finding it in South Korea.
    var containerName: String?
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var type: RexCategory = .place
    @State private var title = ""
    @State private var address = ""
    @State private var section: String
    @State private var rating: Double = 0
    @State private var note = ""
    @State private var picked: RexSearchHit?
    @State private var hits: [RexSearchHit] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var isGeocoding = false
    @State private var errorMessage: String?

    /// A list can hold anything TripStopsBuilderView already offers a list
    /// (#109/#118); a trip's stops are almost always a place. Same category
    /// set TripStopsBuilderView itself uses per container.
    private var stopTypes: [RexCategory] {
        switch container {
        case .trip: return [.place, .event, .recipe, .other]
        case .list: return [.place, .event, .book, .movie, .tv, .podcast, .recipe, .other]
        }
    }
    private var noun: String { if case .trip = container { return "stop" } else { return "item" } }

    init(tripId: String, tripName: String? = nil, initialSection: String? = nil, onAdded: @escaping () -> Void) {
        self.container = .trip(tripId)
        self.containerName = tripName
        self.onAdded = onAdded
        _section = State(initialValue: initialSection ?? "")
    }

    init(listId: String, listName: String? = nil, initialSection: String? = nil, onAdded: @escaping () -> Void) {
        self.container = .list(listId)
        self.containerName = listName
        self.onAdded = onAdded
        _section = State(initialValue: initialSection ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
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

                    if picked == nil && !hits.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(hits.prefix(5)) { hit in
                                Button {
                                    // Sept 23 — "you always have to click twice on the
                                    // suggestion". Setting the title here fires the
                                    // field's own onChange, and a search already in
                                    // flight could still land afterwards and put the
                                    // list straight back — so the second tap was
                                    // dismissing a list the first tap had reopened.
                                    // Cancel what's running, and see searchTask below
                                    // for the late-arrival guard.
                                    searchTask?.cancel()
                                    searchTask = nil
                                    picked = hit
                                    title = hit.title
                                    address = hit.address ?? ""
                                    hits = []
                                    UIApplication.shared.sendAction(
                                        #selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil
                                    )
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
                    input("e.g. Brunch", text: $section)

                    Text("Rating (optional)")
                        .font(RexFont.text(13, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    RexRatingPicker(value: $rating, clearable: true)

                    input("Why are you Rexing it?", text: $note)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving || isGeocoding {
                            HStack(spacing: RexSpacing.sm) {
                                ProgressView().tint(RexColor.primaryForeground)
                                if isGeocoding { Text("Locating…") }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Add \(noun)").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(isSaving || isGeocoding || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Add \(noun == "stop" ? "a" : "an") \(noun)")
            .rexDismissableKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
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
            await MainActor.run {
                // Picked while this was in flight: the answer is no longer
                // wanted, and showing it would reopen the list under the
                // user's finger.
                guard picked == nil else { return }
                hits = results
            }
        }
    }

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        var lat = picked?.lat
        var lng = picked?.lng

        // #135's rule applies here too — a stop typed by hand (no search
        // suggestion tapped) needs geocoding or it never gets a map pin.
        //
        // Sept 28: through locate() rather than the bare geocoder, with the
        // trip's name as context. That does two things this used to get
        // wrong. It finds the right "Calma" when there are several in the
        // world, because it knows we mean the Lisbon one. And it refuses an
        // answer that lands nowhere near, so a stop ends up with no pin
        // rather than a pin in South Korea.
        //
        // It also stops a second problem: a stop saved with no coordinates
        // is a stub, and the next person to add the same place individually
        // creates a SECOND row for it — 41 of those in the catalogue today.
        // Geocoding it properly here means there's one row with a location,
        // which findNearbyItem can then match against.
        if picked == nil, lat == nil, (type == .place || type == .event),
           !(trimmedAddress.isEmpty && trimmed.isEmpty) {
            isGeocoding = true
            let located = await RexSearch.locate(
                name: trimmed.isEmpty ? nil : trimmed,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                context: [containerName]
            )
            lat = located?.lat
            lng = located?.lng
            isGeocoding = false
        }

        isSaving = true
        do {
            let itemId = try await RexAPI.shared.createItem(
                type: type.rawValue,
                title: trimmed,
                subtitle: nil,
                address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                genre: picked?.genre,
                externalId: picked?.externalId,
                externalSource: picked?.externalSource,
                imageURL: picked?.imageURL,
                lat: lat,
                lng: lng
            )
            let trimmedSection = section.trimmingCharacters(in: .whitespaces)
            switch container {
            case .trip(let tripId):
                try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
                    tripId: tripId,
                    tripSection: trimmedSection.isEmpty ? nil : trimmedSection
                )
            case .list(let listId):
                // #118 — every list item defaults visible on the feed, same
                // as a fresh import; the toggle to hide one after the fact
                // lives in ListDetailView itself.
                try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
                    listId: listId,
                    listSection: trimmedSection.isEmpty ? nil : trimmedSection,
                    showInFeed: true
                )
            }
            onAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
