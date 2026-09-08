import SwiftUI

/// Where extracted-but-unreviewed items land — nothing here is a real Rex
/// yet. Swipe away anything that shouldn't have been picked up (deleted
/// from staging immediately, not just hidden — re-opening this screen
/// shouldn't resurrect something already dismissed), edit anything the AI
/// got wrong, then save what's left as a Trip, a Collection, or a List.
struct ImportReviewView: View {
    let source: String
    var onDone: () -> Void
    /// Sept 5 — hands an extracted trip back up to the Add-a-trip form
    /// that opened this importer, instead of posting it from here. See
    /// the .trip case in save().
    var onExtractedAsTrip: ((String, [ItineraryEntry]) -> Void)? = nil
    /// Same hand-off for a List — see the .list case in save().
    var onExtractedAsList: ((String, String, [ItineraryEntry]) -> Void)? = nil
    /// Sept 8 — "make sure we can upload a doc straight to a collection".
    /// Set when this importer was opened from inside a collection rather
    /// than from Add a Rex: there's no destination left to choose, so the
    /// picker goes away and everything reviewed lands in that collection.
    var intoCollection: (id: String, name: String)? = nil

    @State private var rows: [ImportStagingRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var destination: Destination = .list
    @State private var destinationName = ""
    @State private var listKind = rexListKinds.first ?? "Other"
    @State private var splitBySection = false
    @State private var isSaving = false
    @State private var isRetyping = false
    @State private var editingRow: ImportStagingRow?
    /// Which rows default to visible on the main feed on their own —
    /// List-only, meaningless for Trip/Collection. Every row starts in
    /// here (default visible); swiping the toggle off removes it.
    @State private var showInFeedIds: Set<String> = []

    private enum Destination: String, CaseIterable { case list = "List", collection = "Collection", trip = "Trip" }

    private var hasSections: Bool { rows.contains { $0.raw_section != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if rows.isEmpty {
                    Text("Nothing left to review.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    Text("\(rows.count) found \u{2014} tap the trash icon on anything that shouldn't be here")
                        .font(RexFont.text(13, weight: .medium))
                        .foregroundStyle(RexColor.mutedForeground)

                    bulkTypePicker

                    ForEach(rows) { row in
                        rowCard(row)
                    }

                    if let intoCollection {
                        Text("Everything you keep goes into \u{201C}\(intoCollection.name)\u{201D}.")
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.mutedForeground)
                    } else {
                        destinationPicker
                    }

                    if let errorMessage {
                        Text(errorMessage).font(RexFont.text(13)).foregroundStyle(RexColor.destructive)
                    }
                    if let resultMessage {
                        Text(resultMessage).font(RexFont.text(13, weight: .medium)).foregroundStyle(RexColor.primary)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                        } else {
                            Text(intoCollection.map { "Add \(rows.count) to \u{201C}\($0.name)\u{201D}" }
                                 ?? "Save \(rows.count) as \(destination.rawValue)")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(isSaving || rows.isEmpty
                              || (intoCollection == nil && destinationName.trimmingCharacters(in: .whitespaces).isEmpty))
                    .padding(.bottom, RexSpacing.xxl)
                }
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Review")
        .rexDismissableKeyboard()
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $editingRow) { row in
            EditStagingRowSheet(row: row) { updated in
                if let idx = rows.firstIndex(where: { $0.id == updated.id }) {
                    rows[idx] = updated
                }
            }
        }
    }

    // Live report — "when you are importing from a doc, you can't scroll
    // down to review all the rex before posting." SwipeToRemove's own
    // header comment already spells out why: it uses .highPriorityGesture
    // so a horizontal swipe wins outright over the enclosing ScrollView's
    // pan — but that gesture claims priority for ANY drag direction, not
    // just horizontal ones, so a vertical scroll starting on a row (most
    // of the screen, on a document with many rows) got captured the same
    // way. Feed/Profile get away with it because there's always somewhere
    // to start a scroll that isn't mid-card; a long pasted document
    // doesn't leave much of that, and this screen's whole point is
    // reaching the Save button at the bottom. Rather than touch the
    // shared SwipeToRemove (used everywhere else and hard-won against a
    // real regression — #111/#120), this screen drops the swipe gesture
    // entirely in favor of a plain, always-tappable trash icon: same
    // remove action, zero gesture competition with the ScrollView.
    private func rowCard(_ row: ImportStagingRow) -> some View {
        Group {
            HStack(alignment: .top, spacing: RexSpacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let type = row.suggested_type, let category = RexCategory(rawValue: type) {
                            Text(category.label.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(RexColor.badgeForeground)
                                .padding(.horizontal, RexSpacing.sm)
                                .padding(.vertical, 2)
                                .background(RexColor.badgeBackground)
                                .clipShape(Capsule())
                        }
                        if let section = row.raw_section, !section.isEmpty {
                            Text(section)
                                .font(RexFont.text(11, weight: .medium))
                                .foregroundStyle(RexColor.primary)
                        }
                    }

                    Text(row.raw_title)
                        .font(RexFont.text(15, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)

                    if let creator = row.raw_creator, !creator.isEmpty {
                        Text(creator)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                    }

                    // The whole reason this exists as a review step rather
                    // than posting straight through — the note is exactly
                    // what "must not lose the commentary" meant.
                    if let note = row.raw_note, !note.isEmpty {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.foreground.opacity(0.85))
                            .lineLimit(4)
                    }

                    if let url = row.raw_url, !url.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "link").font(.system(size: 10))
                            Text(url).font(RexFont.text(11)).lineLimit(1)
                        }
                        .foregroundStyle(RexColor.primary)
                    }

                    // Sept 5 — gone for lists too: "only the list will be
                    // visible in the feed", so a per-item feed toggle no
                    // longer has anything to toggle.
                    if false {
                        Divider().padding(.vertical, 2)
                        Toggle(isOn: showInFeedBinding(row.id)) {
                            Text("Show on feed").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
                        }
                        .tint(RexColor.primary)
                    }
                }
                Spacer(minLength: 0)
                VStack(spacing: RexSpacing.md) {
                    Button { editingRow = row } label: {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                    .buttonStyle(.plain)

                    Button { Task { await discard(row) } } label: {
                        Image(systemName: "trash.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(RexColor.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(RexSpacing.cardPadding)
            .rexCard()
            .contentShape(Rectangle())
            .onTapGesture { editingRow = row }
        }
    }

    private func showInFeedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { showInFeedIds.contains(id) },
            set: { on in
                if on { showInFeedIds.insert(id) } else { showInFeedIds.remove(id) }
            }
        )
    }

    /// Sept 7 — "when you import from doc they shouldn't be automatically
    /// tagged as a place". The type is the extractor's guess, and on a
    /// homogeneous document (a gift list, a reading list) one wrong guess is
    /// usually the same wrong guess on every row. The prompt now judges the
    /// document as a whole, but that's a probability, not a guarantee — this
    /// is the deterministic escape hatch: set the lot in one tap.
    private var bulkTypePicker: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            HStack(spacing: 6) {
                Text("These are all")
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                if let mixed = dominantType {
                    Text("\u{2014} currently mostly \(mixed.pluralLabel.lowercased())")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    ForEach([RexCategory.place, .book, .movie, .tv, .podcast, .recipe, .event, .other], id: \.self) { type in
                        Button {
                            Task { await applyTypeToAll(type) }
                        } label: {
                            Text(type.pluralLabel)
                                .font(RexFont.text(12.5, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(RexColor.card)
                                .foregroundStyle(RexColor.foreground)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(RexColor.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isRetyping)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// Whatever the extractor guessed most often, for the hint above.
    private var dominantType: RexCategory? {
        var counts: [String: Int] = [:]
        for row in rows { if let t = row.suggested_type { counts[t, default: 0] += 1 } }
        guard let top = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return RexCategory(rawValue: top)
    }

    private func applyTypeToAll(_ type: RexCategory) async {
        isRetyping = true
        for row in rows {
            try? await RexAPI.shared.updateStagingRowType(id: row.id, type: type.rawValue)
        }
        await load()
        isRetyping = false
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text("Save as").font(RexFont.text(14, weight: .semibold)).foregroundStyle(RexColor.foreground)

            Picker("", selection: $destination) {
                ForEach(Destination.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            TextField(
                destination == .trip ? "Trip name, e.g. \u{201C}Lisbon, 3 days\u{201D}" :
                    destination == .list ? "List name, e.g. \u{201C}Summer reads\u{201D}" : "Collection name",
                text: $destinationName
            )
            .font(RexFont.text(15))
            .padding(.horizontal, RexSpacing.md)
            .frame(height: 46)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )

            // A List's own category — "can be other" per the ask, hence
            // rexListKinds ending in exactly that, same convention every
            // other category's subcategory list already follows.
            if destination == .list {
                Text("What kind of list is this?")
                    .font(RexFont.text(12, weight: .medium))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.top, RexSpacing.xs)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        ForEach(rexListKinds, id: \.self) { kind in
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
                    }
                }
            }

            // Trips already section their stops (raw_section becomes
            // trip_section on every stop) — this toggle only makes sense
            // for Collections, where it's a real choice rather than the
            // default behavior.
            if destination == .collection && hasSections {
                Toggle("Split into a collection per heading", isOn: $splitBySection)
                    .font(RexFont.text(13))
                    .tint(RexColor.primary)
            }
        }
        .padding(.top, RexSpacing.sm)
    }

    private func load() async {
        isLoading = true
        rows = (try? await RexAPI.shared.fetchStagingRows(source: source)) ?? []
        // #166 — used to default every row to "on", so importing a list of
        // 20 books flooded the feed with 20 individual cards unless you
        // remembered to untoggle each one. The list card itself always
        // shows what's inside it; showing on the main feed too should be
        // something you opt a standout item into, not the default for all.
        showInFeedIds = []
        isLoading = false
        // Best-effort match against the app's own catalogues (OpenLibrary,
        // TMDB, Google Places), quietly in the background — approving still
        // works even if a row never resolves, it just creates a plain
        // unlinked item the way manual entry always has.
        for row in rows {
            Task { try? await RexAPI.shared.resolveStagingRow(row) }
        }
    }

    /// Immediate, not deferred to Save — matches SwipeToRemove everywhere
    /// else in the app (delete means delete), and means a half-reviewed
    /// list surviving an interrupted session doesn't resurrect things
    /// already swiped away.
    private func discard(_ row: ImportStagingRow) async {
        rows.removeAll { $0.id == row.id }
        showInFeedIds.remove(row.id)
        try? await RexAPI.shared.deleteStagingRows(ids: [row.id])
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        resultMessage = nil
        do {
            if let intoCollection {
                let result = try await RexAPI.shared.approveStagingIntoCollection(
                    rows: rows, listId: intoCollection.id
                )
                resultMessage = result.failed.isEmpty
                    ? "Added \(result.added) to \u{201C}\(intoCollection.name)\u{201D}."
                    : "Added \(result.added) of \(rows.count) \u{2014} \(result.failed.count) couldn't be added."
                try? await Task.sleep(for: .seconds(1.4))
                onDone()
                isSaving = false
                return
            }
            switch destination {
            case .trip:
                // Sept 5 — a trip no longer posts straight from here. It
                // hands the extracted rows back up to the Add-a-trip form
                // that opened this importer, pre-filled, so the document
                // import ends up in exactly the screen a hand-built trip
                // does: add a stop the document missed, add a heading, drag
                // things around, set a cover photo, save as a draft.
                //
                // Handed *up* rather than presented from here on purpose.
                // This screen is already three presentations deep (the
                // add sheet, then the importer sheet, then this), and
                // presenting AddRexView again from inside it meant
                // presenting that view within itself — which crashed on the
                // first real run. The form we want is already on screen
                // underneath; filling it in beats stacking another copy.
                onExtractedAsTrip?(destinationName, [ItineraryEntry].fromStagingRows(rows))
                isSaving = false
                return
            case .list:
                // Sept 5 — same hand-off a trip gets: land on the real
                // Add-a-list form, pre-filled, rather than posting from
                // here, so headings, reordering and adding items the
                // document missed all work identically.
                if let onExtractedAsList {
                    onExtractedAsList(destinationName, listKind, [ItineraryEntry].fromStagingRows(rows))
                    isSaving = false
                    return
                }
                let result = try await RexAPI.shared.approveStagingAsList(
                    rows: rows, listName: destinationName, kind: listKind, note: nil, showInFeedIds: showInFeedIds
                )
                resultMessage = result.failed.isEmpty
                    ? "Saved \(result.added) into \u{201C}\(destinationName)\u{201D}."
                    : "Saved \(result.added) of \(rows.count) \u{2014} \(result.failed.count) couldn't be saved."
            case .collection:
                let result = try await RexAPI.shared.approveStagingAsCollections(
                    rows: rows, name: destinationName, splitBySection: splitBySection
                )
                resultMessage = result.failed.isEmpty
                    ? "Saved \(result.added) into \(result.collections == 1 ? "\u{201C}\(destinationName)\u{201D}" : "\(result.collections) collections")."
                    : "Saved \(result.added) of \(rows.count) \u{2014} \(result.failed.count) couldn't be saved."
            }
            // Long enough to actually read the result before the sheet closes.
            try? await Task.sleep(for: .seconds(1.4))
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

/// Fixes up one extracted row before it's approved — the AI's guess at
/// title, creator, note, rating, or category isn't always right, and
/// there was previously no way to correct that short of discarding the
/// row and posting everything else as-is.
private struct EditStagingRowSheet: View {
    let row: ImportStagingRow
    var onSaved: (ImportStagingRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var creator: String
    @State private var note: String
    @State private var type: RexCategory
    @State private var hasRating: Bool
    @State private var rating: Double
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let editableTypes: [RexCategory] = [.book, .movie, .tv, .place, .recipe, .event, .podcast, .other]

    init(row: ImportStagingRow, onSaved: @escaping (ImportStagingRow) -> Void) {
        self.row = row
        self.onSaved = onSaved
        _title = State(initialValue: row.raw_title)
        _creator = State(initialValue: row.raw_creator ?? "")
        _note = State(initialValue: row.raw_note ?? "")
        _type = State(initialValue: RexCategory(rawValue: row.suggested_type ?? "other") ?? .other)
        _hasRating = State(initialValue: row.raw_rating != nil)
        _rating = State(initialValue: row.raw_rating ?? 8)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    labeled("Title") {
                        textField("Title", text: $title)
                    }
                    labeled("Creator / detail") {
                        textField("Author, director, cuisine\u{2026}", text: $creator)
                    }
                    labeled("Category") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: RexSpacing.sm) {
                                ForEach(editableTypes, id: \.self) { cat in
                                    let isOn = type == cat
                                    Button(cat.label) { type = cat }
                                        .font(RexFont.text(13, weight: isOn ? .semibold : .regular))
                                        .foregroundStyle(isOn ? RexColor.primaryForeground : RexColor.foreground)
                                        .padding(.horizontal, RexSpacing.md)
                                        .padding(.vertical, 7)
                                        .background(isOn ? RexColor.primary : RexColor.card)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(isOn ? RexColor.primary : RexColor.border, lineWidth: 1))
                                }
                            }
                        }
                    }
                    labeled("Note") {
                        TextEditor(text: $note)
                            .font(RexFont.text(14))
                            .frame(minHeight: 90)
                            .padding(RexSpacing.sm)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                    .stroke(RexColor.border, lineWidth: 1)
                            )
                    }
                    labeled("Rating") {
                        Toggle("Has a rating", isOn: $hasRating.animation())
                            .font(RexFont.text(14))
                            .tint(RexColor.primary)
                        if hasRating {
                            // Same five-tier emoji scale as everywhere else
                            // a rating is set (Add a Rex, Edit a Rex, trip
                            // stops) — this sheet was still on the old
                            // ten-crown slider, the one place in the app
                            // that had fallen out of step.
                            RexRatingPicker(value: $rating)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).font(RexFont.text(13)).foregroundStyle(RexColor.destructive)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                        } else {
                            Text("Save changes").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text(label).font(RexFont.text(13, weight: .semibold)).foregroundStyle(RexColor.foreground)
            content()
        }
    }

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(RexFont.text(15))
            .padding(.horizontal, RexSpacing.md)
            .frame(height: 46)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        do {
            try await RexAPI.shared.updateStagingRow(
                id: row.id, title: trimmedTitle, creator: creator, note: note,
                rating: hasRating ? rating : nil, type: type.rawValue
            )
            let updated = ImportStagingRow(
                id: row.id, source: row.source, raw_title: trimmedTitle,
                raw_creator: creator.isEmpty ? nil : creator,
                raw_note: note.isEmpty ? nil : note,
                raw_rating: hasRating ? rating : nil,
                suggested_type: type.rawValue,
                raw_section: row.raw_section, raw_url: row.raw_url,
                resolved_item_id: nil, resolved_external_id: nil, resolved_external_source: nil,
                resolved_image_url: nil, resolved_subtitle: nil, resolved_genre: nil,
                status: row.status
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
