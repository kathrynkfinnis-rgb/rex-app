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
    @State private var draftName = ""
    @State private var draftEmoji = ""
    @State private var confirmingDelete = false
    @State private var pushedItemId: String?

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
                        Text("Long-press any Rex in your feed and choose \u{201C}Add to collection\u{201D}.")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.mutedForeground)
                            .multilineTextAlignment(.center)
                    }
                    .padding(RexSpacing.xxl)
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(rows) { row in
                        if let rec = row.recommendations {
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
                                        if route.isMine {
                                            Button(role: .destructive) {
                                                Task { await remove(rec.id) }
                                            } label: {
                                                Label("Remove from collection", systemImage: "minus.circle")
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
        .toolbar {
            // Shown for any collection, not just your own — there's no
            // public web page for a collection yet (task #108), so this is
            // a text summary rather than a link, but sharing a friend's
            // list is just as reasonable as sharing your own.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if route.isMine {
                        Button { startRename() } label: { Label("Rename", systemImage: "pencil") }

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
