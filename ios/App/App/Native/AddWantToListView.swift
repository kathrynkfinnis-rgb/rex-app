import SwiftUI

/// Put a "want to try" into one of your collections, or take it back out.
///
/// Unlike a Rex — which can sit in several collections at once via
/// saved_posts — a want only ever belongs to one, directly via
/// wants.list_id. That column already existed in the schema; nothing in
/// either client ever read or wrote it until now, which is why there was no
/// way to do this at all.
struct AddWantToListView: View {
    let want: WantRow
    /// Called with the want's new list_id (nil if removed) so the caller
    /// can update its own local copy without a full reload.
    var onChange: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var lists: [RexList] = []
    @State private var isLoading = true
    @State private var selectedListId: String?
    @State private var busyId: String?
    @State private var newName = ""
    @State private var creating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    if let title = want.items?.title {
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
                            Button {
                                Task { await select(list) }
                            } label: {
                                HStack(spacing: RexSpacing.md) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                            .fill(RexColor.badgeBackground)
                                        Text(list.emoji ?? "\u{1F4D2}").font(.system(size: 18))
                                    }
                                    .frame(width: 40, height: 40)

                                    Text(list.name)
                                        .font(RexFont.text(15, weight: .medium))
                                        .foregroundStyle(RexColor.foreground)

                                    Spacer()

                                    if busyId == list.id {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: selectedListId == list.id ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20))
                                            .foregroundStyle(selectedListId == list.id ? RexColor.primary : RexColor.border)
                                    }
                                }
                                .padding(RexSpacing.md)
                                .rexCard()
                            }
                            .buttonStyle(.plain)
                            .disabled(busyId != nil)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        selectedListId = want.list_id
        lists = (try? await RexAPI.shared.fetchLists()) ?? []
        isLoading = false
    }

    /// Tapping the collection it's already in takes it back out — same
    /// clearable pattern as the rating picker.
    private func select(_ list: RexList) async {
        busyId = list.id
        errorMessage = nil
        let next = selectedListId == list.id ? nil : list.id
        do {
            try await RexAPI.shared.setWantList(wantId: want.id, listId: next)
            selectedListId = next
            onChange(next)
        } catch {
            errorMessage = error.localizedDescription
        }
        busyId = nil
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        creating = true
        errorMessage = nil
        do {
            let id = try await RexAPI.shared.createCollection(
                name: name, emoji: nil,
                itemType: want.items?.type ?? "other"
            )
            try await RexAPI.shared.setWantList(wantId: want.id, listId: id)
            selectedListId = id
            onChange(id)
            newName = ""
            lists = (try? await RexAPI.shared.fetchLists()) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        creating = false
    }
}
