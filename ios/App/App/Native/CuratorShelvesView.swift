import SwiftUI

/// Oct 1 — "can we find a way to do this for admins in the app, rather than
/// via SQL?".
///
/// The Rexperts shelves have existed since 16 Aug and have never had anything
/// on them, which is not a coincidence: the only way to add one was to write
/// INSERT statements in the Supabase console. A feature whose author has to
/// open a SQL editor is a feature nobody uses.
///
/// The permissions were always there — is_rex_curator() lets Kathryn, Phoebe
/// and Gemma write — so this is a screen and nothing else.
struct CuratorShelvesRoute: Hashable {}

struct CuratorShelvesView: View {
    @State private var shelves: [EditorialCollection] = []
    @State private var isLoading = true
    @State private var editing: EditorialCollection?
    @State private var creatingNew = false
    @State private var errorMessage: String?
    @State private var confirmingDelete: EditorialCollection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                Text("Shelves show on Explore under “Rex from Rexperts”, and to anyone looking around before they sign up.")
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    creatingNew = true
                } label: {
                    HStack(spacing: RexSpacing.sm) {
                        Image(systemName: "plus.circle.fill")
                        Text("New shelf")
                    }
                    .font(RexFont.text(15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(RexPrimaryButtonStyle())

                if let errorMessage {
                    Text(errorMessage)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, RexSpacing.xl)
                } else if shelves.isEmpty {
                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("No shelves yet")
                            .font(RexFont.display(18, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text("A shelf is a handful of picks under a heading — “A long weekend in Lisbon”, “Best Sunday roasts”. Build one from places already in REX.")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, RexSpacing.xl)
                } else {
                    ForEach(shelves) { shelf in
                        Button { editing = shelf } label: { shelfRow(shelf) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.vertical, RexSpacing.lg)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Rexperts shelves")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingNew) {
            EditShelfView(shelf: nil) { Task { await load() } }
        }
        .sheet(item: $editing) { shelf in
            EditShelfView(shelf: shelf) { Task { await load() } }
        }
        .alert("Delete this shelf?", isPresented: Binding(
            get: { confirmingDelete != nil },
            set: { if !$0 { confirmingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
            Button("Delete", role: .destructive) {
                if let shelf = confirmingDelete { Task { await delete(shelf) } }
            }
        } message: {
            Text("Everything on it goes too. This can't be undone.")
        }
        .task { await load() }
    }

    private func shelfRow(_ shelf: EditorialCollection) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: RexSpacing.sm) {
                Text(shelf.title)
                    .font(RexFont.display(17, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Spacer(minLength: 0)
                Text(shelf.source_label.uppercased())
                    .font(RexFont.text(10, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                    .padding(.horizontal, RexSpacing.sm)
                    .padding(.vertical, 3)
                    .background(RexColor.badgeBackground)
                    .clipShape(Capsule())
            }
            Text(shelf.items.isEmpty
                 ? "Empty — tap to add some"
                 : shelf.items.prefix(3).map(\.title).joined(separator: " · "))
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s")")
                .font(RexFont.text(11))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .padding(RexSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
        .contextMenu {
            Button(role: .destructive) { confirmingDelete = shelf } label: {
                Label("Delete shelf", systemImage: "trash")
            }
        }
    }

    private func load() async {
        isLoading = true
        shelves = (try? await RexAPI.shared.fetchEditorialCollections()) ?? []
        isLoading = false
    }

    private func delete(_ shelf: EditorialCollection) async {
        confirmingDelete = nil
        do {
            try await RexAPI.shared.deleteEditorialCollection(id: shelf.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Create or edit one shelf, and what's on it.
private struct EditShelfView: View {
    /// nil when creating.
    let shelf: EditorialCollection?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var sourceLabel = "REX Team"
    @State private var category: RexCategory?
    @State private var items: [EditorialCollectionItem] = []
    @State private var shelfId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var addingItem = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    field("Heading", text: $title, placeholder: "A long weekend in Lisbon")
                    field("Credit", text: $sourceLabel, placeholder: "REX Team")

                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Category")
                            .font(RexFont.text(13, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text("Which filter it shows under. Leave as Any to show under all of them.")
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: RexSpacing.sm) {
                                chip("Any", isOn: category == nil) { category = nil }
                                ForEach(rexAllCategories, id: \.self) { option in
                                    chip(option.label, isOn: category == option) { category = option }
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    if let shelfId {
                        Divider().overlay(RexColor.border)
                        HStack {
                            Text("On this shelf")
                                .font(RexFont.display(17, weight: .semibold))
                                .foregroundStyle(RexColor.foreground)
                            Spacer()
                            Button { addingItem = true } label: {
                                Label("Add", systemImage: "plus")
                                    .font(RexFont.text(14, weight: .semibold))
                            }
                        }

                        if items.isEmpty {
                            Text("Nothing on it yet.")
                                .font(RexFont.text(14))
                                .foregroundStyle(RexColor.mutedForeground)
                        }

                        ForEach(items) { item in
                            HStack(spacing: RexSpacing.md) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(RexFont.text(14, weight: .medium))
                                        .foregroundStyle(RexColor.foreground)
                                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(RexFont.text(12))
                                            .foregroundStyle(RexColor.mutedForeground)
                                    }
                                }
                                Spacer(minLength: 0)
                                Button {
                                    Task { await removeItem(item) }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(RexColor.destructive)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(RexSpacing.md)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        }
                        // Saving the shelf is what creates it; items can only
                        // hang off something that already exists.
                    } else {
                        Text("Save the shelf first, then you can add things to it.")
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.mutedForeground)
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
                            ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                        } else {
                            Text(shelfId == nil ? "Create shelf" : "Save changes").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle(shelf == nil ? "New shelf" : "Edit shelf")
            .navigationBarTitleDisplayMode(.inline)
            .rexDismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { onSaved(); dismiss() }
                }
            }
            .sheet(isPresented: $addingItem) {
                if let shelfId {
                    AddShelfItemView(collectionId: shelfId, nextSortOrder: items.count + 1) {
                        Task { await reloadItems() }
                    }
                }
            }
        }
        .tint(RexColor.primary)
        .onAppear {
            guard let shelf else { return }
            title = shelf.title
            sourceLabel = shelf.source_label
            category = shelf.category.flatMap { RexCategory(rawValue: $0) }
            items = shelf.items
            shelfId = shelf.id
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.xs) {
            Text(label)
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
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
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(RexFont.text(13, weight: .medium))
                .foregroundStyle(isOn ? RexColor.primaryForeground : RexColor.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isOn ? RexColor.primary : RexColor.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(RexColor.border, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        do {
            if let shelfId {
                try await RexAPI.shared.updateEditorialCollection(
                    id: shelfId, title: trimmed, sourceLabel: sourceLabel,
                    category: category?.rawValue, sortOrder: 0
                )
            } else {
                shelfId = try await RexAPI.shared.createEditorialCollection(
                    title: trimmed, sourceLabel: sourceLabel,
                    category: category?.rawValue, sortOrder: 0
                )
            }
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func reloadItems() async {
        guard let shelfId else { return }
        let all = (try? await RexAPI.shared.fetchEditorialCollections()) ?? []
        items = all.first(where: { $0.id == shelfId })?.items ?? items
        onSaved()
    }

    private func removeItem(_ item: EditorialCollectionItem) async {
        do {
            try await RexAPI.shared.deleteEditorialItem(id: item.id)
            items.removeAll { $0.id == item.id }
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Pick something already in REX. Choosing from the catalogue rather than
/// typing a name means the card gets its real photo and subtitle for free,
/// and points at an item people can open.
private struct AddShelfItemView: View {
    let collectionId: String
    let nextSortOrder: Int
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [RexItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    TextField("Search places, books, films already in REX", text: $query)
                        .font(RexFont.text(15))
                        .padding(.horizontal, RexSpacing.md)
                        .frame(height: 46)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                        .onChange(of: query) { _, _ in scheduleSearch() }

                    if isSearching { ProgressView().frame(maxWidth: .infinity) }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }

                    ForEach(results, id: \.id) { item in
                        Button {
                            Task { await add(item) }
                        } label: {
                            HStack(spacing: RexSpacing.md) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(RexFont.text(14, weight: .medium))
                                        .foregroundStyle(RexColor.foreground)
                                        .multilineTextAlignment(.leading)
                                    if let subtitle = item.subtitle ?? item.address, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(RexFont.text(12))
                                            .foregroundStyle(RexColor.mutedForeground)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(RexColor.primary)
                            }
                            .padding(RexSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Add to shelf")
            .navigationBarTitleDisplayMode(.inline)
            .rexDismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .tint(RexColor.primary)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = query
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            results = (try? await RexAPI.shared.searchCatalogue(term)) ?? []
            isSearching = false
        }
    }

    private func add(_ item: RexItem) async {
        do {
            try await RexAPI.shared.addEditorialItem(
                collectionId: collectionId,
                title: item.title,
                subtitle: item.subtitle ?? item.address,
                imageURL: item.image_url,
                itemId: item.id,
                linkURL: nil,
                sortOrder: nextSortOrder
            )
            onAdded()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
