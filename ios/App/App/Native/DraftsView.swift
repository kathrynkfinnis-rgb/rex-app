import SwiftUI

struct DraftsRoute: Hashable {}

/// Your own drafts — anything saved or taken off the feed but not published.
/// Reached from Profile. Only ever shows your own by construction: RLS hides
/// anyone else's drafts before fetchDrafts' query even runs.
struct DraftsView: View {
    @State private var drafts: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var openTrip: TripRoute?
    @State private var openList: ListRoute?
    @State private var openItem: String?
    @State private var publishing: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 76)
                    }
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if drafts.isEmpty {
                    empty()
                } else {
                    ForEach(drafts) { draft in
                        Button {
                            let title = draft.items?.title ?? (isList(draft) ? "List" : "Trip")
                            switch kind(of: draft) {
                            case .list: openList = ListRoute(recommendationId: draft.id, title: title)
                            case .trip: openTrip = TripRoute(recommendationId: draft.id, title: title)
                            // A single Rex has no draft-shaped screen of its
                            // own — its item page is the public one, which is
                            // the wrong thing to open from here. Tapping the
                            // row opens the item anyway, because looking at
                            // what you saved is the obvious thing to want,
                            // and Publish is on the row itself.
                            case .single: openItem = draft.item_id
                            }
                        } label: {
                            row(draft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.vertical, RexSpacing.lg)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Drafts")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openTrip) { TripDetailView(route: $0) }
        .navigationDestination(item: $openList) { ListDetailView(route: $0) }
        .navigationDestination(item: $openItem) { ItemDetailView(itemId: $0) }
        .task { await load() }
    }

    /// Nov 16 — "I want to be able to move a Rex back to drafts and then
    /// repost it."
    ///
    /// Until now this screen held trips and lists only, because those are the
    /// two things with a detail view that carries a Publish button. A single
    /// Rex had nowhere to be published from, which is why unposting one was
    /// not offered at all: it would have gone somewhere nothing could reach.
    ///
    /// So the row publishes it directly. No new screen, and the way back is
    /// in the same place as the draft rather than one tap further in.
    private enum DraftKind { case trip, list, single }

    private func kind(of draft: FeedRecommendation) -> DraftKind {
        switch RexCategory(rawType: draft.items?.type) {
        case .list: return .list
        case .trip: return .trip
        default: return .single
        }
    }

    private func isList(_ draft: FeedRecommendation) -> Bool {
        kind(of: draft) == .list
    }

    private func publish(_ draft: FeedRecommendation) async {
        publishing.insert(draft.id)
        do {
            try await RexAPI.shared.publishDraft(recommendationId: draft.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        publishing.remove(draft.id)
    }

    private func row(_ draft: FeedRecommendation) -> some View {
        let category = RexCategory(rawType: draft.items?.type)
        let single = kind(of: draft) == .single
        return HStack(spacing: RexSpacing.md) {
            ZStack {
                RexColor.muted
                // A single Rex is a thing with a cover — a book, a film, a
                // place — so show it rather than a generic glyph. Trips and
                // lists keep theirs: a trip's "cover" is its first stop's
                // photo, which says nothing about the trip.
                if single, let url = draft.items?.image_url, let parsed = URL(string: url) {
                    AsyncImage(url: parsed) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: category.symbol)
                                .font(.system(size: 18)).foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                } else {
                    Image(systemName: isList(draft) ? "list.bullet" : (single ? category.symbol : "bag"))
                        .font(.system(size: 18)).foregroundStyle(RexColor.mutedForeground)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.items?.title ?? (isList(draft) ? "List" : "Trip"))
                    .font(RexFont.text(15, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(1)
                // "started" is right for something you are building up over
                // time and wrong for a Rex you posted and took down again.
                Text(single
                     ? "Draft — unposted \(relativeDate(draft.created_at))"
                     : "Draft — started \(relativeDate(draft.created_at))")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            Spacer(minLength: RexSpacing.sm)

            if single {
                // The way back, on the draft itself. A trip or a list has
                // Publish inside its own detail view; a single Rex has no
                // such screen, and this is the whole reason unposting one
                // used to be refused.
                Button {
                    Task { await publish(draft) }
                } label: {
                    if publishing.contains(draft.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Publish")
                            .font(RexFont.text(13, weight: .semibold))
                            .foregroundStyle(RexColor.primaryForeground)
                            .padding(.horizontal, RexSpacing.md)
                            .padding(.vertical, 7)
                            .background(RexColor.primary)
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                .disabled(publishing.contains(draft.id))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        }
        .padding(RexSpacing.cardPadding)
        .rexCard()
    }

    private func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            drafts = try await RexAPI.shared.fetchDrafts()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func empty() -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "doc.text").font(.system(size: 28)).foregroundStyle(RexColor.mutedForeground)
            Text("No drafts")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Save a trip or a list to build it up over time, or move a Rex off the feed and keep it here. Publish any of them whenever you're ready.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(RexSpacing.xxl)
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
