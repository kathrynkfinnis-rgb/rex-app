import SwiftUI

/// Route marker so a List card can navigate to its own page rather than the
/// generic item screen — mirrors TripRoute exactly. Addressed by the list's
/// own *recommendation* id, since that's what an item's list_id points at.
struct ListRoute: Hashable, Identifiable {
    let recommendationId: String
    let title: String

    var id: String { recommendationId }
}

/// A List's own page: every item, grouped under its optional heading, in
/// the order it was added. Mirrors TripDetailView, with one addition that
/// Trip doesn't have — each item stays editable indefinitely (not just
/// during the original import review), and its "show on feed" visibility
/// can be flipped here too.
///
/// Aug 28 — "editing the heading doesn't work" and "I want to add a heading
/// between cards two and three ... but I can't" were both this: a List only
/// ever got TripStopsBuilderView's up-front builder, never #122's
/// after-the-fact editing tools (rename heading, reorder, add mid-list)
/// TripDetailView got at the same time. Ported over, same shapes.
struct ListDetailView: View {
    let route: ListRoute

    @State private var items: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Sept 9 — one sheet modifier, not several. Stacking `.sheet`
    /// modifiers on the same view silently drops all but one of them; see
    /// FeedView.ActiveSheet.
    private enum ActiveSheet: Identifiable {
        case addItem
        case edit(FeedRecommendation)
        var id: String {
            switch self {
            case .addItem: return "addItem"
            case .edit(let rec): return "edit-\(rec.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    @State private var isOwner = false
    @State private var isEditing = false
    @State private var isMutating = false
    @State private var mutationError: String?
    @State private var renamingHeading: String?
    @State private var renameDraft = ""
    @State private var addItemSection = ""
    /// Aug 29 — "Phoebe's list has adopted the subtitle of a draft trip and
    /// she can't edit it": a list's underlying item can carry a subtitle
    /// (shown right under the title on its feed card, same as any other
    /// category), but nothing anywhere ever gave a List its own field to set
    /// or clear one — see AddRexView.resetDraftFields for how a stale one
    /// gets there in the first place. This is that missing field.
    @State private var listItemId: String?
    @State private var subtitle = ""
    @State private var editingSubtitle = false
    @State private var subtitleDraft = ""

    /// Items grouped by heading, preserving the order both groups and items
    /// first appear in — same rule TripDetailView's groups already follow.
    private var groups: [(heading: String, items: [FeedRecommendation])] {
        var result: [(heading: String, items: [FeedRecommendation])] = []
        for item in items {
            let heading = (item.list_section ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let idx = result.firstIndex(where: { $0.heading.caseInsensitiveCompare(heading) == .orderedSame }) {
                result[idx].items.append(item)
            } else {
                result.append((heading: heading, items: [item]))
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
                } else if items.isEmpty {
                    Text("Nothing on this list yet.")
                        .font(.footnote)
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    if isEditing {
                        addItemButton(heading: "")
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
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                VStack(alignment: .leading, spacing: 4) {
                                    if isEditing {
                                        HStack(spacing: RexSpacing.lg) {
                                            Button {
                                                Task { await moveItem(item, in: group, direction: -1) }
                                            } label: {
                                                Image(systemName: "chevron.up")
                                            }
                                            .disabled(isMutating || index == 0)
                                            Button {
                                                Task { await moveItem(item, in: group, direction: 1) }
                                            } label: {
                                                Image(systemName: "chevron.down")
                                            }
                                            .disabled(isMutating || index == group.items.count - 1)
                                            Spacer()
                                            Button(role: .destructive) {
                                                Task { await removeItem(item) }
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .disabled(isMutating)
                                        }
                                        .font(.system(size: 14))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .padding(.horizontal, RexSpacing.sm)
                                    }
                                    itemRow(item)
                                }
                            }
                            if isEditing {
                                addItemButton(heading: group.heading)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                // Sept 5 — "a dedicated 'add a Rex' button inside a list".
                // Adding an item used to mean entering Edit mode first and
                // finding the inline button under a heading; this is the
                // same action, always one tap away.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addItemSection = ""
                        activeSheet = .addItem
                    } label: {
                        Image(systemName: "plus")
                    }
                }
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
            Text("Applies to every item under this heading.")
        }
        .alert("Edit subtitle", isPresented: $editingSubtitle) {
            TextField("Subtitle", text: $subtitleDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await saveSubtitle() } }
        } message: {
            Text("Shown under the list's title, including on its feed card.")
        }
        .sheet(item: $activeSheet, onDismiss: { Task { await load() } }) { sheet in
            switch sheet {
            case .addItem:
                AddTripStopSheet(listId: route.recommendationId, initialSection: addItemSection, onAdded: {})
            case .edit(let rec):
                EditRexView(
                    rec: rec,
                    onSaved: { Task { await load() } },
                    onDeleted: { Task { await load() } }
                )
            }
        }
    }

    private func addItemButton(heading: String) -> some View {
        Button {
            addItemSection = heading
            activeSheet = .addItem
        } label: {
            Label(heading.isEmpty ? "Add an item" : "Add to \(heading)", systemImage: "plus")
                .font(RexFont.text(13, weight: .medium))
        }
        .padding(.top, 2)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: RexCategory.list.symbol).font(.system(size: 10))
                Text("LIST").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(RexColor.primary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RexColor.primary.opacity(0.1))
            .clipShape(Capsule())

            Text(route.title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(RexColor.foreground)

            if !isLoading, !subtitle.isEmpty || isOwner {
                HStack(spacing: 6) {
                    Text(subtitle.isEmpty ? "Add a subtitle" : subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(subtitle.isEmpty ? RexColor.mutedForeground.opacity(0.7) : RexColor.mutedForeground)
                        .italic(subtitle.isEmpty)
                    if isOwner {
                        Button {
                            subtitleDraft = subtitle
                            editingSubtitle = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                }
            }

            if !isLoading {
                Text("\(items.count) \(items.count == 1 ? "item" : "items")")
                    .font(.footnote)
                    .foregroundStyle(RexColor.mutedForeground)
            }
        }
    }

    private func itemRow(_ item: FeedRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: item.item_id) {
                RecommendationCardView(rec: item)
            }
            .buttonStyle(.plain)

            // Sept 7 — "I can still edit the individual items on someone
            // else's list, there shouldn't be a pencil icon. There is also a
            // 'show on feed' button — this should be removed."
            //
            // The row was drawn the same for everyone: the whole block had
            // no isOwner check, so a friend's list offered you an Edit
            // button on every item. The toggle is gone outright — list items
            // no longer post to the feed individually, so it had nothing
            // left to control.
            //
            // Edit stays available forever on your own list, not just during
            // the original import review — "need to be able to edit the Rex
            // within the import once they are live" was explicit in the ask.
            if isOwner {
                HStack {
                    Spacer()
                    Button {
                        activeSheet = .edit(item)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                        .font(RexFont.text(12, weight: .semibold))
                        .foregroundStyle(RexColor.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, RexSpacing.cardPadding)
                .padding(.vertical, RexSpacing.sm)
            }
        }
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
    }

    private func showInFeedBinding(_ item: FeedRecommendation) -> Binding<Bool> {
        Binding(
            get: { item.show_in_feed ?? true },
            set: { newValue in
                guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
                items[idx] = FeedRecommendation(
                    id: item.id, rating: item.rating, note: item.note, created_at: item.created_at,
                    photo_url: item.photo_url, photo_urls: item.photo_urls, tags: item.tags,
                    user_id: item.user_id, item_id: item.item_id, items: item.items,
                    profiles: item.profiles, creators: item.creators, trip_section: item.trip_section,
                    is_anonymous: item.is_anonymous, list_section: item.list_section, show_in_feed: newValue,
                    recommendation_tags: item.recommendation_tags
                )
                Task { try? await RexAPI.shared.updateShowInFeed(recommendationId: item.id, showInFeed: newValue) }
            }
        )
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await RexAPI.shared.fetchListItems(listRecommendationId: route.recommendationId)
            // Best-effort, same reasoning as TripDetailView's ownerTask —
            // not knowing who owns this list should hide the Edit button,
            // not break loading the page.
            let listRec = try? await RexAPI.shared.fetchRecommendation(id: route.recommendationId)
            isOwner = listRec?.user_id == RexAPI.shared.currentUserId
            listItemId = listRec?.item_id
            subtitle = listRec?.items?.subtitle ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Bulk-renames a heading across every item under it (see
    /// RexAPI.renameListSection — a heading is just a repeated string, not
    /// its own row).
    private func renameHeading() async {
        guard let from = renamingHeading else { return }
        let to = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingHeading = nil
        guard to.caseInsensitiveCompare(from) != .orderedSame else { return }
        isMutating = true
        mutationError = nil
        do {
            try await RexAPI.shared.renameListSection(
                listId: route.recommendationId,
                from: from.isEmpty ? nil : from,
                to: to.isEmpty ? nil : to
            )
            await load()
        } catch {
            mutationError = error.localizedDescription
        }
        isMutating = false
    }

    private func saveSubtitle() async {
        guard let listItemId else { return }
        let trimmed = subtitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != subtitle else { return }
        isMutating = true
        mutationError = nil
        do {
            try await RexAPI.shared.updateItemSubtitle(itemId: listItemId, subtitle: trimmed)
            subtitle = trimmed
        } catch {
            mutationError = error.localizedDescription
        }
        isMutating = false
    }

    private func removeItem(_ item: FeedRecommendation) async {
        isMutating = true
        mutationError = nil
        do {
            try await RexAPI.shared.deleteRecommendation(id: item.id)
            await load()
        } catch {
            mutationError = error.localizedDescription
        }
        isMutating = false
    }

    /// Swaps this item's created_at with its neighbour — same trick
    /// TripDetailView's moveStop uses, see its own doc comment.
    private func moveItem(_ item: FeedRecommendation, in group: (heading: String, items: [FeedRecommendation]), direction: Int) async {
        guard let idx = group.items.firstIndex(where: { $0.id == item.id }) else { return }
        let otherIdx = idx + direction
        guard group.items.indices.contains(otherIdx) else { return }
        let a = group.items[idx]
        let b = group.items[otherIdx]
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
