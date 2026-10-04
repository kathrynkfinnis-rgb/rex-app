import SwiftUI

/// Oct 3 — "when you reply to a blast, you should be able to tag REX to the
/// response."
///
/// Picks one of your own Rex to attach to a reply. Deliberately only your own,
/// and deliberately not a catalogue search: a blast is someone asking what you
/// would recommend, and the answer is something you have actually been to.
/// Pointing them at a place you have never visited is what a web search is
/// for, and it isn't what they asked.
struct AttachRexSheet: View {
    var onPick: (RexItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MyRexHit] = []
    @State private var recent: [MyRexHit] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var shown: [MyRexHit] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? recent : results
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.sm) {
                    TextField("Search your Rex", text: $query)
                        .font(RexFont.text(15))
                        .padding(.horizontal, RexSpacing.md)
                        .frame(height: 44)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                        .onChange(of: query) { _, _ in scheduleSearch() }

                    if isSearching {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, RexSpacing.md)
                    } else if shown.isEmpty {
                        Text(query.isEmpty
                             ? "Nothing Rex'd yet — anything you add will show up here."
                             : "Nothing of yours matches that.")
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.mutedForeground)
                            .padding(.top, RexSpacing.md)
                    }

                    ForEach(shown, id: \.hit.id) { mine in
                        Button {
                            onPick(item(from: mine))
                            dismiss()
                        } label: {
                            HStack(spacing: RexSpacing.md) {
                                Image(systemName: RexCategory(rawType: mine.type).symbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(RexColor.primary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mine.hit.title)
                                        .font(RexFont.text(14, weight: .medium))
                                        .foregroundStyle(RexColor.foreground)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(1)
                                    if let sub = mine.hit.address ?? mine.hit.subtitle, !sub.isEmpty {
                                        Text(sub)
                                            .font(RexFont.text(12))
                                            .foregroundStyle(RexColor.mutedForeground)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                if mine.rating > 0 { RexRatingBadge(raw: mine.rating) }
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
            .navigationTitle("Attach one of your Rex")
            .navigationBarTitleDisplayMode(.inline)
            .rexDismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .task { await loadRecent() }
        }
        .tint(RexColor.primary)
    }

    /// The hit carries everything the reply needs; this is the shape the rest
    /// of the app passes around.
    private func item(from mine: MyRexHit) -> RexItem {
        RexItem(
            id: mine.itemId,
            type: mine.type,
            title: mine.hit.title,
            subtitle: mine.hit.subtitle,
            image_url: mine.hit.imageURL,
            genre: mine.hit.genre,
            address: mine.hit.address
        )
    }

    /// Your most recent Rex, so the common case — answering about somewhere
    /// you went last week — needs no typing at all.
    private func loadRecent() async {
        recent = (try? await RexAPI.shared.searchMyRexItems(query: "")) ?? []
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let found = (try? await RexAPI.shared.searchMyRexItems(query: term)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }
}
