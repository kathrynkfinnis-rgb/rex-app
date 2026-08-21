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
    @State private var isSaving = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

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
                            Text("Photos").font(RexFont.text(14, weight: .semibold))
                            PhotoPickerView(photoURLs: $photoURLs)
                        }
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

            switch (wantRowId, wantToTry) {
            case (_?, true):
                // Still a want, nothing to convert — just the note. Upserts
                // on (user_id, item_id), same row as before.
                try await RexAPI.shared.createWant(itemId: rec.item_id, note: note.isEmpty ? nil : note)
            case (let id?, false):
                // Want -> rated: this row moves tables. Create the
                // recommendation first — if that fails, the want is still
                // there rather than the Rex vanishing into neither table.
                try await RexAPI.shared.createRecommendation(
                    itemId: rec.item_id, rating: rating,
                    note: note.isEmpty ? nil : note,
                    photoURLs: photoURLs, tags: tags
                )
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
