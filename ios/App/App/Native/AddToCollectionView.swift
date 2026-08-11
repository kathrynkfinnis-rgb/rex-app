import SwiftUI

/// Put a Rex into one or more of your collections, or make a new one.
/// This is the only path that fills a collection.
struct AddToCollectionView: View {
    let rec: FeedRecommendation
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var lists: [RexList] = []
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
                            Button {
                                Task { await toggle(list) }
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

                                    if busyIds.contains(list.id) {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: inLists.contains(list.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20))
                                            .foregroundStyle(inLists.contains(list.id) ? RexColor.primary : RexColor.border)
                                    }
                                }
                                .padding(RexSpacing.md)
                                .rexCard()
                            }
                            .buttonStyle(.plain)
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
                    Button("Done") { onDone(); dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        lists = (try? await RexAPI.shared.fetchLists()) ?? []
        inLists = (try? await RexAPI.shared.collectionsContaining(recommendationId: rec.id)) ?? []
        isLoading = false
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
            let id = try await RexAPI.shared.createCollection(
                name: name, emoji: nil,
                // Type the collection by whatever's going into it first.
                itemType: rec.items?.type ?? "other"
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
