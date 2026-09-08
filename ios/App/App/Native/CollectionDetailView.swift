import SwiftUI
import UniformTypeIdentifiers

struct CollectionRoute: Hashable, Identifiable {
    let listId: String
    let name: String
    let isMine: Bool

    var id: String { listId }
}

/// One collection, opened up. Yours can be renamed, shared wider, or emptied;
/// someone else's is read-only.
struct CollectionDetailView: View {
    let route: CollectionRoute

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var emoji: String
    @State private var visibility: String = "draft"
    @State private var rows: [SavedPost] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var renaming = false
    /// One sheet modifier, not two — stacking `.sheet(item:)` and
    /// `.sheet(isPresented:)` on the same view silently drops all but one
    /// of them, which is what made the list page's own import button do
    /// nothing on 5 Sept.
    private enum ActiveSheet: Identifiable {
        case edit(FeedRecommendation)
        case documentImport
        case addRex
        var id: String {
            switch self {
            case .edit(let rec): return "edit-\(rec.id)"
            case .documentImport: return "documentImport"
            case .addRex: return "addRex"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var draftName = ""
    @State private var draftEmoji = ""
    @State private var confirmingDelete = false
    @State private var pushedItemId: String?

    /// Sept 8 — collections gained headings and a real order, so they need
    /// the two things trips already have: somewhere to put a heading, and
    /// a way to move something up.
    ///
    /// Chevrons rather than drag, deliberately, and the same choice
    /// TripDetailView made: a card in here is already draggable — that's
    /// how you copy it into another collection — and already carries a
    /// horizontal swipe to remove. A third gesture on the same card would
    /// be fighting the other two for every touch. The drag-and-drop
    /// arranging lives in the importer, where a row is only a row.
    @State private var isArranging = false
    @State private var isMutating = false
    @State private var mutationError: String?
    @State private var renamingSection: String?
    @State private var sectionDraft = ""

    /// Rows in stored order, grouped under their headings. Sections come
    /// out in the order they're first encountered rather than
    /// alphabetically, so the arrangement you saved is the one you see.
    private var groups: [(heading: String, rows: [SavedPost])] {
        var order: [String] = []
        var byHeading: [String: [SavedPost]] = [:]
        for row in rows {
            let heading = row.section?.trimmingCharacters(in: .whitespaces) ?? ""
            if byHeading[heading] == nil { order.append(heading) }
            byHeading[heading, default: []].append(row)
        }
        return order.map { ($0, byHeading[$0] ?? []) }
    }

    init(route: CollectionRoute) {
        self.route = route
        _name = State(initialValue: route.name)
        _emoji = State(initialValue: "\u{1F4D2}")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                headerBlock

                // A failed refresh shouldn't wipe out what's already on screen —
                // show it as a line above the contents, not instead of them.
                if let errorMessage {
                    HStack(spacing: RexSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(errorMessage)
                        Spacer()
                        Button("Retry") { Task { await load() } }
                            .font(RexFont.text(13, weight: .semibold))
                    }
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.destructive)
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 88)
                    }
                } else if rows.isEmpty && errorMessage == nil {
                    VStack(spacing: RexSpacing.sm) {
                        Text("Nothing in here yet")
                            .font(RexFont.display(20, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text(route.isMine
                             ? "Add one of your own, import a document, or long-press any Rex in your feed."
                             : "Nothing's been added to this one yet.")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.mutedForeground)
                            .multilineTextAlignment(.center)
                        if route.isMine {
                            Button { activeSheet = .addRex } label: {
                                Text("Add a Rex").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(RexPrimaryButtonStyle())
                            .padding(.top, RexSpacing.sm)
                        }
                    }
                    .padding(RexSpacing.xxl)
                    .frame(maxWidth: .infinity)
                } else {
                    if let mutationError {
                        Text(mutationError)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.destructive)
                    }
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                      VStack(alignment: .leading, spacing: RexSpacing.md) {
                        if !group.heading.isEmpty || isArranging {
                            HStack(spacing: RexSpacing.sm) {
                                Text(group.heading.isEmpty ? "No heading" : group.heading)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundStyle(group.heading.isEmpty ? RexColor.mutedForeground : RexColor.foreground)
                                if isArranging {
                                    // Naming the "No heading" group is also
                                    // how you create the first one — there's
                                    // no separate "add a heading" step,
                                    // because there's nothing to add it to
                                    // until something sits under it.
                                    Button {
                                        renamingSection = group.heading
                                        sectionDraft = group.heading
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 12))
                                            .foregroundStyle(RexColor.mutedForeground)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.top, RexSpacing.xs)
                        }
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                        if let rec = row.recommendations {
                            if isArranging {
                                HStack(spacing: RexSpacing.lg) {
                                    Button {
                                        Task { await move(row, by: -1) }
                                    } label: { Image(systemName: "chevron.up") }
                                    .disabled(isMutating || rows.first?.id == row.id)
                                    Button {
                                        Task { await move(row, by: 1) }
                                    } label: { Image(systemName: "chevron.down") }
                                    .disabled(isMutating || rows.last?.id == row.id)
                                    Spacer()
                                    Text(rec.items?.title ?? "Untitled")
                                        .font(RexFont.text(13, weight: .medium))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .lineLimit(1)
                                }
                                .font(.system(size: 14))
                                .foregroundStyle(RexColor.mutedForeground)
                                .padding(.horizontal, RexSpacing.sm)
                                .padding(.top, index == 0 ? 0 : RexSpacing.sm)
                            }
                            SwipeToRemove(
                                label: "Remove",
                                systemImage: "minus.circle",
                                onTap: { pushedItemId = rec.item_id },
                                action: {
                                    guard route.isMine else { return }
                                    await remove(rec.id)
                                }
                            ) {
                                RecommendationCardView(rec: rec)
                                    // Drag a card out to drop it into another
                                    // collection. Dropping copies — a Rex can
                                    // live in several lists.
                                    .draggable(rec.id) {
                                        dragPreview(rec)
                                    }
                                    .contextMenu {
                                        // Sept 7 — "if I open my own collection
                                        // I can't update the location, so some
                                        // don't appear on the map". A card in a
                                        // collection had no way into the editor
                                        // at all; a wrong address could only be
                                        // fixed by finding the Rex somewhere
                                        // else. Only your own Rex — a
                                        // collection can hold other people's.
                                        if rec.user_id == RexAPI.shared.currentUserId {
                                            Button {
                                                activeSheet = .edit(rec)
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                        }
                                        if route.isMine {
                                            Button(role: .destructive) {
                                                Task { await remove(rec.id) }
                                            } label: {
                                                Label("Remove from collection", systemImage: "minus.circle")
                                            }
                                        }
                                    }
                                    // The same affordance the feed and profile
                                    // use, so it's discoverable without
                                    // knowing to long-press.
                                    .overlay(alignment: .topTrailing) {
                                        if rec.user_id == RexAPI.shared.currentUserId {
                                            Button {
                                                activeSheet = .edit(rec)
                                            } label: {
                                                Image(systemName: "pencil")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(RexColor.mutedForeground)
                                                    .padding(8)
                                                    .background(RexColor.card)
                                                    .clipShape(Circle())
                                                    .overlay(Circle().stroke(RexColor.border, lineWidth: 1))
                                                    .frame(width: 44, height: 44)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .padding(2)
                                        }
                                    }
                            }
                        }
                        }
                      }
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.bottom, RexSpacing.xxxl)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushedItemId) { ItemDetailView(itemId: $0) }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit(let rec):
                EditRexView(
                    rec: rec,
                    onSaved: { Task { await load() } },
                    onDeleted: { Task { await load() } }
                )
            case .documentImport:
                // Sept 8 — "make sure we can upload a doc straight to a
                // collection, [with] the same import style that we have
                // just built for trips and lists". Same two screens a trip
                // or a list import goes through — paste, then review each
                // row and fix whatever the extraction got wrong — with the
                // destination already decided, since you're standing in it.
                ListsImportView(
                    onDone: { Task { await load() } },
                    intoCollection: (id: route.id, name: name)
                )
            case .addRex:
                CollectionAddRexSheet(
                    listId: route.id,
                    collectionName: name,
                    existingIds: Set(rows.map { $0.recommendation_id }),
                    startingSortOrder: (rows.compactMap { $0.sort_order }.max() ?? -1) + 1,
                    onAdded: { Task { await load() } }
                )
            }
        }
        .toolbar {
            // Shown for any collection, not just your own — there's no
            // public web page for a collection yet (task #108), so this is
            // a text summary rather than a link, but sharing a friend's
            // list is just as reasonable as sharing your own.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if route.isMine {
                        Button { startRename() } label: { Label("Rename", systemImage: "pencil") }

                        Button { activeSheet = .addRex } label: {
                            Label("Add a Rex", systemImage: "plus")
                        }

                        Button { activeSheet = .documentImport } label: {
                            Label("Import from doc", systemImage: "doc.text")
                        }

                        Button {
                            withAnimation(.snappy) { isArranging.toggle() }
                        } label: {
                            Label(isArranging ? "Done arranging" : "Add headings & reorder",
                                  systemImage: isArranging ? "checkmark" : "arrow.up.arrow.down")
                        }

                        Menu("Who can see it") {
                            visibilityButton("draft", "Only me", "lock")
                            visibilityButton("friends", "Friends", "person.2")
                            visibilityButton("public", "Anyone on REX", "globe")
                        }
                    }

                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    if route.isMine {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label("Delete collection", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Heading", isPresented: Binding(
            get: { renamingSection != nil },
            set: { if !$0 { renamingSection = nil } }
        )) {
            TextField("Heading", text: $sectionDraft)
            Button("Cancel", role: .cancel) { renamingSection = nil }
            Button("Save") { Task { await renameSection() } }
        } message: {
            Text("Applies to everything under this heading. Leave it empty to remove it.")
        }
        .alert("Rename collection", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            TextField("Emoji", text: $draftEmoji)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await saveName() } }
        }
        .alert("Delete \u{201C}\(name)\u{201D}?", isPresented: $confirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await deleteCollection() } }
        } message: {
            Text("The Rex themselves stay put — only the collection goes.")
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private var headerBlock: some View {
        HStack(spacing: RexSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                    .fill(RexColor.badgeBackground)
                Text(emoji).font(.system(size: 26))
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(RexFont.display(24, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Text("\(rows.count) \(rows.count == 1 ? "Rex" : "Rex") \u{00B7} \(visibilityLabel)")
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.mutedForeground)
            }
            Spacer()
        }
        .padding(.top, RexSpacing.sm)
    }

    /// A text summary rather than a link — there's no public web page for a
    /// collection to point at (see the toolbar comment). Good enough for
    /// "hey, check out this list of restaurants" over WhatsApp/iMessage/etc,
    /// which was the actual ask; a real shareable link is separate follow-up
    /// work if it turns out people want to open it back up in-app.
    private var shareText: String {
        var lines = ["\(emoji) \(name) on REX"]
        let titles = rows.compactMap { $0.recommendations?.items?.title }
        lines.append(contentsOf: titles.prefix(12).map { "\u{2022} \($0)" })
        if titles.count > 12 {
            lines.append("...and \(titles.count - 12) more")
        }
        return lines.joined(separator: "\n")
    }

    private var visibilityLabel: String {
        switch visibility {
        case "public": return "Anyone on REX"
        case "friends": return "Friends"
        default: return "Only me"
        }
    }

    private func visibilityButton(_ value: String, _ label: String, _ symbol: String) -> some View {
        Button {
            Task { await setVisibility(value) }
        } label: {
            Label(visibility == value ? "\(label) \u{2713}" : label, systemImage: symbol)
        }
    }

    private func dragPreview(_ rec: FeedRecommendation) -> some View {
        HStack(spacing: RexSpacing.sm) {
            Image(systemName: RexCategory(rawType: rec.items?.type).symbol)
                .foregroundStyle(RexColor.primary)
            Text(rec.items?.title ?? "Rex")
                .font(RexFont.text(14, weight: .medium))
                .lineLimit(1)
        }
        .padding(RexSpacing.sm)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
    }

    // MARK: - Actions

    private func startRename() {
        draftName = name
        draftEmoji = emoji
        renaming = true
    }

    private func saveName() async {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let newEmoji = draftEmoji.trimmingCharacters(in: .whitespaces)
        do {
            try await RexAPI.shared.renameCollection(id: route.listId, name: trimmed, emoji: newEmoji)
            name = trimmed
            if !newEmoji.isEmpty { emoji = newEmoji }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setVisibility(_ value: String) async {
        let previous = visibility
        visibility = value
        do {
            try await RexAPI.shared.setCollectionVisibility(id: route.listId, visibility: value)
        } catch {
            visibility = previous
            errorMessage = error.localizedDescription
        }
    }

    /// Moves one row one place through the collection's flat order,
    /// crossing a heading boundary if that's where the next slot is —
    /// which is also how you move something into a heading, without a
    /// separate "change section" control for it.
    private func move(_ row: SavedPost, by direction: Int) async {
        guard let from = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let to = from + direction
        guard rows.indices.contains(to) else { return }

        var reordered = rows
        let moved = reordered.remove(at: from)
        // Crossing into the neighbour's group takes its heading; staying
        // put keeps your own.
        let neighbourSection = rows[to].section
        var landed = moved
        if neighbourSection != moved.section { landed.section = neighbourSection }
        reordered.insert(landed, at: to)
        for index in reordered.indices { reordered[index].sort_order = index }

        let previous = rows
        withAnimation(.snappy) { rows = reordered }
        isMutating = true
        mutationError = nil
        do {
            try await RexAPI.shared.setCollectionOrder(
                reordered.map { (savedPostId: $0.id, section: $0.section, sortOrder: $0.sort_order ?? 0) }
            )
        } catch {
            // Put it back rather than showing an order that isn't saved.
            rows = previous
            mutationError = error.localizedDescription
        }
        isMutating = false
    }

    private func renameSection() async {
        guard let renamingSection else { return }
        let to = sectionDraft.trimmingCharacters(in: .whitespaces)
        self.renamingSection = nil
        isMutating = true
        mutationError = nil
        do {
            try await RexAPI.shared.renameCollectionSection(
                listId: route.id, from: renamingSection, to: to
            )
            await load()
        } catch {
            mutationError = error.localizedDescription
        }
        isMutating = false
    }

    private func remove(_ recommendationId: String) async {
        rows.removeAll { $0.recommendations?.id == recommendationId }
        try? await RexAPI.shared.removeFromCollection(recommendationId: recommendationId, listId: route.listId)
    }

    private func deleteCollection() async {
        do {
            try await RexAPI.shared.deleteCollection(id: route.listId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = rows.isEmpty
        errorMessage = nil
        do {
            rows = try await RexAPI.shared.fetchCollectionItems(listId: route.listId)
            // The list's own name/emoji can have changed on another device.
            if let mine = try? await RexAPI.shared.fetchLists(),
               let match = mine.first(where: { $0.id == route.listId }) {
                name = match.name
                emoji = match.emoji ?? "\u{1F4D2}"
                visibility = match.visibility ?? "draft"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
