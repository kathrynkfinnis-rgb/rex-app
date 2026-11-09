import SwiftUI

/// Put a Rex into one or more of your collections, or make a new one.
/// This is the only path that fills a collection.
struct AddToCollectionView: View {
    let rec: FeedRecommendation
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var lists: [RexList] = []
    /// Nov 9 — "can we use the little images from the collections page for
    /// the 'add to collection' page? so it's a bit more engaging?"
    ///
    /// The same 2x2 of what is actually inside each one that CollectionsView
    /// draws on its shelf tiles, via the same ThumbnailGridView. Loaded after
    /// the rows are already on screen — it is one request per collection, and
    /// nothing here should wait on them: a row shows its emoji and swaps to
    /// the real thing when it arrives.
    @State private var contents: [String: [SavedPost]] = [:]
    @State private var inLists: Set<String> = []
    @State private var isLoading = true
    @State private var newName = ""
    @State private var creating = false
    @State private var busyIds: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    if let title = rec.items?.title {
                        Text(title)
                            .font(RexFont.display(20, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                            .lineLimit(2)
                    }

                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: RexRadius.card)
                                .fill(RexColor.muted)
                                .frame(height: 60)
                        }
                    } else {
                        if lists.isEmpty {
                            Text("You haven't made a collection yet. Create one below — like \u{201C}My favourite pubs in London\u{201D}.")
                                .font(RexFont.text(14))
                                .foregroundStyle(RexColor.mutedForeground)
                        }

                        ForEach(lists) { list in
                            let isIn = inLists.contains(list.id)
                            let category = RexCategory(rawType: list.item_type)
                            Button {
                                Task { await toggle(list) }
                            } label: {
                                let thumbs = (contents[list.id] ?? [])
                                    .compactMap { $0.recommendations?.items?.image_url }
                                HStack(spacing: RexSpacing.md) {
                                    Group {
                                        if thumbs.isEmpty {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                                    .fill(category.tintColor.opacity(0.14))
                                                // Still the fallback, for a
                                                // collection that is empty or
                                                // whose items have no artwork.
                                                Text(list.emoji ?? category.emoji).font(.system(size: 20))
                                            }
                                        } else {
                                            ThumbnailGridView(urls: thumbs)
                                        }
                                    }
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(list.name)
                                            .font(RexFont.text(15, weight: .medium))
                                            .foregroundStyle(RexColor.foreground)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        // The count beats the category name:
                                        // it is what CollectionsView shows,
                                        // and "20 items" tells you which
                                        // collection this is in a way that
                                        // "Movies" does not.
                                        Text(itemCountLabel(for: list, category: category))
                                            .font(RexFont.text(12))
                                            .foregroundStyle(RexColor.mutedForeground)
                                    }

                                    Spacer()

                                    if busyIds.contains(list.id) {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20))
                                            .foregroundStyle(isIn ? RexColor.primary : RexColor.border)
                                    }
                                }
                                .padding(RexSpacing.md)
                                .rexCard()
                                // A filled circle alone was the only thing
                                // separating in from out, at the far edge of
                                // the row from the name it belongs to.
                                .overlay(
                                    RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                                        .stroke(isIn ? RexColor.primary : .clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .animation(.snappy(duration: 0.2), value: isIn)
                        }

                        VStack(alignment: .leading, spacing: RexSpacing.sm) {
                            Text("New collection")
                                .font(RexFont.text(14, weight: .semibold))
                                .foregroundStyle(RexColor.foreground)
                            HStack(spacing: RexSpacing.sm) {
                                TextField("e.g. Best pubs in London", text: $newName)
                                    .font(RexFont.text(15))
                                    .padding(.horizontal, RexSpacing.md)
                                    .frame(height: 48)
                                    .background(RexColor.card)
                                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                            .stroke(RexColor.border, lineWidth: 1)
                                    )
                                Button {
                                    Task { await createAndAdd() }
                                } label: {
                                    if creating {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "plus")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(RexColor.primaryForeground)
                                            .frame(width: 48, height: 48)
                                            .background(RexColor.primary)
                                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(creating || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(.top, RexSpacing.sm)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Add to collection")
            .rexDismissableKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { onDone(); dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .task { await load() }
    }

    /// "20 items" where we know, the category where we don't yet — the counts
    /// arrive after the rows, and a row that flashes "0 items" before
    /// correcting itself is worse than one that says what kind it is.
    private func itemCountLabel(for list: RexList, category: RexCategory) -> String {
        guard let rows = contents[list.id] else { return category.pluralLabel }
        return rows.count == 1 ? "1 item" : "\(rows.count) items"
    }

    private func load() async {
        isLoading = true
        lists = (try? await RexAPI.shared.fetchLists()) ?? []
        inLists = (try? await RexAPI.shared.collectionsContaining(recommendationId: rec.id)) ?? []
        isLoading = false
        // After the rows are drawn: one request per collection, and the sheet
        // is usable without any of them. Same shape as CollectionsView.
        let all = lists
        contents = await withTaskGroup(of: (String, [SavedPost]).self) { group in
            for list in all {
                group.addTask {
                    (list.id, (try? await RexAPI.shared.fetchCollectionItems(listId: list.id)) ?? [])
                }
            }
            var result: [String: [SavedPost]] = [:]
            for await (id, rows) in group { result[id] = rows }
            return result
        }
    }

    private func toggle(_ list: RexList) async {
        busyIds.insert(list.id)
        errorMessage = nil
        let wasIn = inLists.contains(list.id)
        do {
            if wasIn {
                try await RexAPI.shared.removeFromCollection(recommendationId: rec.id, listId: list.id)
                inLists.remove(list.id)
            } else {
                try await RexAPI.shared.addToCollection(recommendationId: rec.id, listId: list.id)
                inLists.insert(list.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        busyIds.remove(list.id)
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        creating = true
        errorMessage = nil
        do {
            // Type the collection by whatever's going into it first, and
            // give it that type's emoji rather than nothing. Passing nil
            // here is what made every row in this sheet identical.
            let type = rec.items?.type ?? "other"
            let id = try await RexAPI.shared.createCollection(
                name: name, emoji: RexCategory(rawType: type).emoji, itemType: type
            )
            try await RexAPI.shared.addToCollection(recommendationId: rec.id, listId: id)
            newName = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        creating = false
    }
}
