import SwiftUI

/// Where tapping a book's author (in a card's subtitle) leads.
struct AuthorRoute: Hashable {
    let author: String
}

/// An author's whole bibliography — not just what's been Rex'd on the app.
/// Pulled from OpenLibrary (same source book search already uses), then
/// cross-referenced against our own items table so entries someone has
/// actually Rex'd here are tappable through to that item's page. The rest
/// are shown but muted — there's nothing to open for a book nobody's posted
/// yet, and pretending otherwise would just be a dead tap.
struct AuthorBooksView: View {
    let route: AuthorRoute

    @State private var books: [RexSearchHit] = []
    /// Title (lowercased) -> item id, for whichever of the author's books
    /// someone has actually Rex'd on the app.
    @State private var rexedItemIds: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pushedItemId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if isLoading {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 76)
                    }
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if books.isEmpty {
                    empty()
                } else {
                    ForEach(books) { book in
                        bookRow(book)
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.vertical, RexSpacing.lg)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(route.author)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushedItemId) { ItemDetailView(itemId: $0) }
        .task { await load() }
    }

    private func bookRow(_ book: RexSearchHit) -> some View {
        let itemId = rexedItemIds[book.title.lowercased()]
        return Button {
            if let itemId { pushedItemId = itemId }
        } label: {
            HStack(spacing: RexSpacing.md) {
                Group {
                    if let urlString = book.imageURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                RexColor.muted
                            }
                        }
                    } else {
                        RexColor.muted.overlay(
                            Image(systemName: "book").foregroundStyle(RexColor.mutedForeground)
                        )
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(RexFont.text(15, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(2)
                    if let subtitle = book.subtitle {
                        Text(subtitle)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: RexSpacing.sm)

                if itemId != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RexColor.mutedForeground)
                } else {
                    Text("Not Rex'd yet")
                        .font(RexFont.text(10, weight: .medium))
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 3)
                        .background(RexColor.muted)
                        .clipShape(Capsule())
                }
            }
            .padding(RexSpacing.cardPadding)
            .rexCard()
            .opacity(itemId == nil ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(itemId == nil)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let catalogue = RexSearch.byAuthor(route.author)
            async let ownItems = RexAPI.shared.fetchBooksByAuthor(route.author)
            books = try await catalogue
            let items = (try? await ownItems) ?? []
            rexedItemIds = Dictionary(items.map { ($0.title.lowercased(), $0.id) }, uniquingKeysWith: { a, _ in a })
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func empty() -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "book").font(.system(size: 28)).foregroundStyle(RexColor.mutedForeground)
            Text("Couldn't find a catalogue for \(route.author)")
                .font(RexFont.display(18, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, RexSpacing.xxl)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(RexFont.text(13)).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}
