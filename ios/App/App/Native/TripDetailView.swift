import SwiftUI

/// Route marker so a trip card can navigate to the itinerary rather than the
/// generic item screen. Trips are addressed by their *recommendation* id,
/// because that's what a stop's trip_id points at.
struct TripRoute: Hashable, Identifiable {
    let recommendationId: String
    let title: String

    var id: String { recommendationId }
}

/// The itinerary for a trip: every stop, grouped under its optional heading,
/// in the order it was added. Mirrors the web trip page.
///
/// #122: the trip's own author can also edit it here — add/remove stops,
/// reorder them within a heading, and rename headings — rather than only
/// being able to build the itinerary once up front in TripStopsBuilderView.
struct TripDetailView: View {
    let route: TripRoute

    @State private var stops: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isDraft = false
    @State private var isPublishing = false
    @State private var publishError: String?

    @State private var isOwner = false
    @State private var isEditing = false
    @State private var isMutating = false
    @State private var mutationError: String?
    @State private var renamingHeading: String?
    @State private var renameDraft = ""
    @State private var showingAddStop = false
    @State private var addStopSection = ""
    /// #170 — the trip's own free-text note (separate from any stop's).
    @State private var tripNote: String?
    @State private var editingNote = false
    @State private var noteDraft = ""
    @State private var isSavingNote = false
    /// #183 — the trip is itself an item (its own recommendation just
    /// points at it, same as every stop points at its own item), so
    /// renaming it is exactly EditRexView's existing updateItemTitle path —
    /// this just needs the trip's own item_id, which route only ever
    /// carried a display title for, not an id.
    @State private var tripItemId: String?
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var displayTitle: String
    /// #183 — a stop's own title/note/address/subcategories etc, via the
    /// same EditRexView every other Rex is edited through. Trip stops
    /// never had any edit entry point of their own before this — only
    /// reorder/remove, added by #122.
    @State private var editingStop: FeedRecommendation?

    init(route: TripRoute) {
        self.route = route
        _displayTitle = State(initialValue: route.title)
    }

    /// Stops grouped by heading, preserving the order both groups and stops
    /// first appear in — same rule as the web's groupStops().
    private var groups: [(heading: String, stops: [FeedRecommendation])] {
        var result: [(heading: String, stops: [FeedRecommendation])] = []
        for stop in stops {
            let heading = (stop.trip_section ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let idx = result.firstIndex(where: { $0.heading.caseInsensitiveCompare(heading) == .orderedSame }) {
                result[idx].stops.append(stop)
            } else {
                result.append((heading: heading, stops: [stop]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16).fill(RexColor.muted).frame(height: 90)
                    }
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if stops.isEmpty {
                    Text("No stops on this trip yet.")
                        .font(.footnote)
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    if isEditing {
                        addStopButton(heading: "")
                    }
                } else {
                    if let mutationError {
                        Text(mutationError)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.destructive)
                    }
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 8) {
                            if !group.heading.isEmpty || isEditing {
                                HStack(spacing: RexSpacing.sm) {
                                    Text(group.heading.isEmpty ? "No heading" : group.heading)
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .foregroundStyle(group.heading.isEmpty ? RexColor.mutedForeground : RexColor.foreground)
                                        .padding(.top, 4)
                                    if isEditing {
                                        Button {
                                            renamingHeading = group.heading
                                            renameDraft = group.heading
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 12))
                                                .foregroundStyle(RexColor.mutedForeground)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            ForEach(Array(group.stops.enumerated()), id: \.element.id) { index, stop in
                                VStack(alignment: .leading, spacing: 4) {
                                    if isEditing {
                                        HStack(spacing: RexSpacing.lg) {
                                            Button {
                                                Task { await moveStop(stop, in: group, direction: -1) }
                                            } label: {
                                                Image(systemName: "chevron.up")
                                            }
                                            .disabled(isMutating || index == 0)
                                            Button {
                                                Task { await moveStop(stop, in: group, direction: 1) }
                                            } label: {
                                                Image(systemName: "chevron.down")
                                            }
                                            .disabled(isMutating || index == group.stops.count - 1)
                                            Spacer()
                                            // #183 — title, note, address/
                                            // geocoding, subcategories:
                                            // every field EditRexView
                                            // already handles for any other
                                            // Rex, now reachable for a trip
                                            // stop too instead of only
                                            // reorder/remove.
                                            Button {
                                                editingStop = stop
                                            } label: {
                                                Image(systemName: "pencil")
                                            }
                                            .disabled(isMutating)
                                            Button(role: .destructive) {
                                                Task { await removeStop(stop) }
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .disabled(isMutating)
                                        }
                                        .font(.system(size: 14))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .padding(.horizontal, RexSpacing.sm)
                                    }
                                    NavigationLink(value: stop.item_id) {
                                        RecommendationCardView(rec: stop)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if isEditing {
                                addStopButton(heading: group.heading)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation { isEditing.toggle() }
                    }
                }
            }
        }
        .task { await load() }
        .alert("Rename heading", isPresented: Binding(
            get: { renamingHeading != nil },
            set: { if !$0 { renamingHeading = nil } }
        )) {
            TextField("Heading", text: $renameDraft)
            Button("Cancel", role: .cancel) { renamingHeading = nil }
            Button("Save") { Task { await renameHeading() } }
        } message: {
            Text("Applies to every stop under this heading.")
        }
        .sheet(isPresented: $showingAddStop, onDismiss: { Task { await load() } }) {
            AddTripStopSheet(tripId: route.recommendationId, initialSection: addStopSection, onAdded: {})
        }
        .sheet(item: $editingStop) { stop in
            EditRexView(
                rec: stop,
                onSaved: { Task { await load() } },
                onDeleted: { Task { await load() } }
            )
        }
    }

    private func addStopButton(heading: String) -> some View {
        Button {
            addStopSection = heading
            showingAddStop = true
        } label: {
            Label(heading.isEmpty ? "Add a stop" : "Add to \(heading)", systemImage: "plus")
                .font(RexFont.text(13, weight: .medium))
        }
        .padding(.top, 2)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "bag").font(.system(size: 10))
                Text("TRIP").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(RexColor.primary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RexColor.primary.opacity(0.1))
            .clipShape(Capsule())

            HStack(spacing: RexSpacing.sm) {
                Text(displayTitle)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(RexColor.foreground)
                // #183 — was static (route.title, whatever the card you
                // came from happened to show) with no way to fix a typo
                // short of deleting and rebuilding the whole trip.
                if isOwner && isEditing {
                    Button {
                        titleDraft = displayTitle
                        editingTitle = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                }
            }

            if !isLoading {
                Text("\(stops.count) \(stops.count == 1 ? "stop" : "stops")")
                    .font(.footnote)
                    .foregroundStyle(RexColor.mutedForeground)
            }

            if let tripNote, !tripNote.isEmpty {
                noteRow(tripNote)
            } else if isOwner && !isLoading {
                Button {
                    noteDraft = ""
                    editingNote = true
                } label: {
                    Label("Add a note", systemImage: "text.badge.plus")
                        .font(RexFont.text(13, weight: .medium))
                        .foregroundStyle(RexColor.mutedForeground)
                }
                .padding(.top, 2)
            }

            if isDraft {
                draftBanner
            }
        }
        .alert("Rename trip", isPresented: $editingTitle) {
            TextField("Trip title", text: $titleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await renameTrip() } }
        }
        .alert("Trip note", isPresented: $editingNote) {
            TextField("What's this trip about?", text: $noteDraft, axis: .vertical)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await saveNote() } }
        }
    }

    /// #170 — the trip's own note, same quoted styling RecommendationCardView
    /// uses for a stop's note. Tapping it (owner only) reopens the editor.
    private func noteRow(_ note: String) -> some View {
        Text("\u{201C}\(note)\u{201D}")
            .font(RexFont.text(14))
            .foregroundStyle(RexColor.foreground.opacity(0.88))
            .padding(.top, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isOwner else { return }
                noteDraft = note
                editingNote = true
            }
    }

    private func saveNote() async {
        let next = noteDraft
        isSavingNote = true
        do {
            try await RexAPI.shared.updateNote(recommendationId: route.recommendationId, note: next)
            tripNote = next.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            mutationError = error.localizedDescription
        }
        isSavingNote = false
    }

    /// Only ever shown to the trip's own author — RLS hides a draft from
    /// anyone else before this view could even load it.
    private var draftBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.system(size: 12))
                Text("Draft — only you can see this")
                    .font(RexFont.text(13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(RexColor.mutedForeground)

            Button {
                Task { await publish() }
            } label: {
                if isPublishing {
                    ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                } else {
                    Text("Publish trip").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44)
            .background(RexColor.primary)
            .foregroundStyle(RexColor.primaryForeground)
            .clipShape(Capsule())
            .disabled(isPublishing || stops.isEmpty)

            if stops.isEmpty {
                Text("Add at least one stop before publishing.")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            if let publishError {
                Text(publishError)
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.destructive)
            }
        }
        .padding(12)
        .background(RexColor.badgeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func publish() async {
        isPublishing = true
        publishError = nil
        do {
            try await RexAPI.shared.publishTrip(tripRecommendationId: route.recommendationId)
            isDraft = false
        } catch {
            publishError = error.localizedDescription
        }
        isPublishing = false
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let stopsTask = RexAPI.shared.fetchTripStops(tripRecommendationId: route.recommendationId)
            async let draftTask = RexAPI.shared.isDraft(recommendationId: route.recommendationId)
            // Best-effort, same as isDraft below — not knowing who owns this
            // trip should hide the Edit button, not break loading the page.
            async let ownerTask: FeedRecommendation? = try? RexAPI.shared.fetchRecommendation(id: route.recommendationId)
            stops = try await stopsTask
            isDraft = (try? await draftTask) ?? false
            let tripRec = await ownerTask
            isOwner = tripRec?.user_id == RexAPI.shared.currentUserId
            tripNote = tripRec?.note
            tripItemId = tripRec?.item_id
            if let title = tripRec?.items?.title { displayTitle = title }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// #183 — same shared-catalogue updateItemTitle every other Rex's
    /// title goes through, just needs the trip's own item_id rather than a
    /// stop's.
    private func renameTrip() async {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tripItemId, !trimmed.isEmpty, trimmed != displayTitle else { return }
        isMutating = true
        mutationError = nil
        do {
            try await RexAPI.shared.updateItemTitle(itemId: tripItemId, title: trimmed)
            displayTitle = trimmed
        } catch {
            mutationError = error.localizedDescription
        }
        isMutating = false
    }

    /// Bulk-renames a heading across every stop under it (see
    /// RexAPI.renameTripSection — a heading is just a repeated string, not
    /// its own row).
    private func renameHeading() async {
        guard let from = renamingHeading else { return }
        let to = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingHeading = nil
        guard to.caseInsensitiveCompare(from) != .orderedSame else { return }
        isMutating = true
        mutationError = nil
        do {
            try await RexAPI.shared.renameTripSection(
                tripId: route.recommendationId,
                from: from.isEmpty ? nil : from,
                to: to.isEmpty ? nil : to
            )
            await load()
        } catch {
            mutationError = error.localizedDescription
        }
        isMutating = false
    }

    private func removeStop(_ stop: FeedRecommendation) async {
        isMutating = true
        mutationError = nil
        do {
            try await RexAPI.shared.deleteRecommendation(id: stop.id)
            await load()
        } catch {
            mutationError = error.localizedDescription
        }
        isMutating = false
    }

    /// Swaps this stop's created_at with its neighbour — the only "sort
    /// order" a stop has is where its created_at falls among its trip
    /// siblings (fetchTripStops orders by created_at.asc), and swapping
    /// keeps both timestamps inside this heading's own original range, so a
    /// reorder can never bleed a stop into a different heading's position.
    private func moveStop(_ stop: FeedRecommendation, in group: (heading: String, stops: [FeedRecommendation]), direction: Int) async {
        guard let idx = group.stops.firstIndex(where: { $0.id == stop.id }) else { return }
        let otherIdx = idx + direction
        guard group.stops.indices.contains(otherIdx) else { return }
        let a = group.stops[idx]
        let b = group.stops[otherIdx]
        isMutating = true
        mutationError = nil
        do {
            try await RexAPI.shared.setRecommendationCreatedAt(id: a.id, createdAt: b.created_at)
            try await RexAPI.shared.setRecommendationCreatedAt(id: b.id, createdAt: a.created_at)
            await load()
        } catch {
            mutationError = error.localizedDescription
        }
        isMutating = false
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(.footnote).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.footnote.weight(.semibold)).foregroundStyle(RexColor.primary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
