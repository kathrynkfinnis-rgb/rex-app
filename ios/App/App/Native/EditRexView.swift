import SwiftUI

/// Edit or delete one of your own Rex — rating, note, tags and photos.
/// Mirrors the web EditRecommendationDialog.
struct EditRexView: View {
    let rec: FeedRecommendation
    var onSaved: () -> Void
    var onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rating: Double
    @State private var note: String
    @State private var photoURLs: [String]
    @State private var tags: [String]
    @State private var tagDraft = ""
    @State private var isSaving = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    init(rec: FeedRecommendation, onSaved: @escaping () -> Void, onDeleted: @escaping () -> Void) {
        self.rec = rec
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _rating = State(initialValue: rec.rating)
        _note = State(initialValue: rec.note ?? "")
        _photoURLs = State(initialValue: rec.photo_urls ?? (rec.photo_url.map { [$0] } ?? []))
        _tags = State(initialValue: rec.tags ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.xl) {
                    if let item = rec.items {
                        Text(item.title)
                            .font(RexFont.display(22, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                    }

                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Your rating").font(RexFont.text(14, weight: .semibold))
                        CrownRatingInput(value: $rating, clearable: true)
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

                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Photos").font(RexFont.text(14, weight: .semibold))
                        PhotoPickerView(photoURLs: $photoURLs)
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
        isSaving = true
        errorMessage = nil
        // Commit a tag the user typed but didn't submit, so it isn't silently lost.
        addTag()
        do {
            try await RexAPI.shared.updateRecommendation(
                id: rec.id, rating: rating,
                note: note.isEmpty ? nil : note,
                photoURLs: photoURLs, tags: tags
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteRex() async {
        do {
            try await RexAPI.shared.deleteRecommendation(id: rec.id)
            onDeleted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
