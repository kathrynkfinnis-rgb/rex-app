import SwiftUI

/// Oct 7 — "when you go back to edit a book you can't amend the link, you can
/// only amend the title by hand. Should be able to amend the link."
///
/// Search the catalogue again and point an existing Rex at the right entry.
/// Retyping the title never fixed a wrong match: the cover, the author, the
/// page count and the genre all come from the catalogue entry, so a Rex
/// attached to the wrong book stayed attached to it under a corrected name.
///
/// Deliberately a picker rather than a form. Everything about the thing comes
/// from the entry you choose; there is nothing here to fill in, and the one
/// decision — which of these is it — is the whole screen.
struct RepickItemSheet: View {
    let category: RexCategory
    /// What it currently points at, so the search starts somewhere useful and
    /// the sheet can say what is being replaced.
    let currentTitle: String
    /// What picking one of these will do, in the user's terms. Defaults to the
    /// edit-a-Rex case; the find-a-missing-pin screen passes its own.
    var blurb: String? = nil
    /// The title shown in the navigation bar.
    var heading: String = "Change what this is"
    var onPick: (RexSearchHit) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var hits: [RexSearchHit] = []
    @State private var isSearching = false
    @State private var saving = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    init(
        category: RexCategory,
        currentTitle: String,
        blurb: String? = nil,
        heading: String = "Change what this is",
        onPick: @escaping (RexSearchHit) async -> Void
    ) {
        self.category = category
        self.currentTitle = currentTitle
        self.blurb = blurb
        self.heading = heading
        self.onPick = onPick
        _query = State(initialValue: currentTitle)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    Text(blurb ?? "Currently \u{201C}\(currentTitle)\u{201D}. Pick the right one and this Rex moves to it \u{2014} your rating, note and photos come with it.")
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    searchField

                    if isSearching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Searching\u{2026}")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    } else if !hits.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(hits) { hit in
                                resultRow(hit)
                                if hit.id != hits.last?.id {
                                    Divider().padding(.leading, RexSpacing.md)
                                }
                            }
                        }
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                    }
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .rexDismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(saving)
            .task {
                focused = true
                await runSearch()
            }
        }
        .tint(RexColor.primary)
    }

    private var searchField: some View {
        HStack(spacing: RexSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(RexColor.mutedForeground)
            TextField("Search", text: $query)
                .font(RexFont.text(15))
                .focused($focused)
                .autocorrectionDisabled()
                .submitLabel(.search)
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

    private func resultRow(_ hit: RexSearchHit) -> some View {
        Button {
            guard !saving else { return }
            saving = true
            Task {
                await onPick(hit)
                dismiss()
            }
        } label: {
            HStack(spacing: RexSpacing.sm) {
                Group {
                    if let url = hit.imageURL, let parsed = URL(string: url) {
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
                .frame(width: 38, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(RexFont.text(14.5, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let sub = hit.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RexColor.placeholder)
            }
            .padding(RexSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { hits = []; isSearching = false; return }
        isSearching = true
        let found = await RexSearch.search(category: category, query: q)
        guard !Task.isCancelled else { return }
        hits = Array(found.prefix(12))
        isSearching = false
    }
}
