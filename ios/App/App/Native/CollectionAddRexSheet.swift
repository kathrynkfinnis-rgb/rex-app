import SwiftUI

/// Sept 8 — "Add a Rex" from inside a collection.
///
/// Until now the only way into a collection was long-pressing a card in
/// the feed and choosing "Add to collection", which means the thing you
/// want has to happen to be scrolled past. Filling a collection on purpose
/// — sitting down and putting your six favourite pubs in one place — meant
/// hunting each one down in the feed first. This is the other direction:
/// stand in the collection, search your own Rex, tap what belongs.
///
/// Multi-add rather than pick-one-and-dismiss: nobody opens this to add a
/// single thing, and re-opening the sheet between each one is the whole
/// annoyance being fixed. Rows already in the collection stay visible and
/// marked, so you can see what's in there rather than wondering whether
/// you already added something.
struct CollectionAddRexSheet: View {
    let listId: String
    let collectionName: String
    /// The recommendation ids already in the collection, so they can be
    /// shown as such rather than silently doing nothing when tapped.
    let existingIds: Set<String>
    /// Where the next added row goes. Continues past whatever is already
    /// in the collection — see RexAPI.setCollectionOrder.
    let startingSortOrder: Int
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var addedIds: Set<String> = []
    @State private var pendingId: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    searchField

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }

                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if results.isEmpty {
                        Text(query.isEmpty
                             ? "You haven't Rex'd anything yet."
                             : "Nothing of yours matches \u{201C}\(query)\u{201D}.")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(results) { rec in
                                row(rec)
                            }
                        }
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                    }
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Add to \(collectionName)")
            .navigationBarTitleDisplayMode(.inline)
            .rexDismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // "Done" rather than "Cancel": everything tapped is
                    // already saved, so there's nothing here to cancel.
                    Button("Done") { dismiss() }
                        .font(RexFont.text(15, weight: .semibold))
                }
            }
        }
        .tint(RexColor.primary)
        .task { await search() }
    }

    private var searchField: some View {
        HStack(spacing: RexSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(RexColor.mutedForeground)
            TextField("Search your Rex", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onChange(of: query) { _, _ in scheduleSearch() }
        }
        .padding(11)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
    }

    private func row(_ rec: FeedRecommendation) -> some View {
        let category = RexCategory(rawType: rec.items?.type)
        let alreadyIn = existingIds.contains(rec.id) || addedIds.contains(rec.id)
        return Button {
            guard !alreadyIn else { return }
            Task { await add(rec) }
        } label: {
            HStack(spacing: RexSpacing.sm) {
                Group {
                    if let url = rec.items?.image_url, let parsed = URL(string: url) {
                        AsyncImage(url: parsed) { phase in
                            if let image = phase.image {
                                Color.clear.overlay { image.resizable().scaledToFill() }
                            } else {
                                category.tintColor.opacity(0.18)
                            }
                        }
                    } else {
                        category.tintColor.opacity(0.18)
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(rec.items?.title ?? "Untitled")
                        .font(RexFont.text(14.5, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(category.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(category.tintColor)
                        if let where_ = shortLocality(rec.items?.address) ?? rec.items?.subtitle,
                           !where_.isEmpty {
                            Text(where_)
                                .font(RexFont.text(11.5))
                                .foregroundStyle(RexColor.mutedForeground)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: RexSpacing.sm)

                if pendingId == rec.id {
                    ProgressView().controlSize(.small)
                } else if alreadyIn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(RexColor.primary)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            }
            .padding(.horizontal, RexSpacing.md)
            .padding(.vertical, RexSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyIn || pendingId != nil)
        .overlay(alignment: .top) { Rectangle().fill(RexColor.divider).frame(height: 1) }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        isLoading = true
        errorMessage = nil
        do {
            results = try await RexAPI.shared.searchMyRecommendations(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func add(_ rec: FeedRecommendation) async {
        pendingId = rec.id
        errorMessage = nil
        do {
            try await RexAPI.shared.addToCollection(
                recommendationId: rec.id,
                listId: listId,
                // Appended, not inserted: the collection's existing
                // arrangement is something you decided, and shouldn't be
                // rearranged by adding to it.
                sortOrder: startingSortOrder + addedIds.count
            )
            addedIds.insert(rec.id)
            onAdded()
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingId = nil
    }
}
