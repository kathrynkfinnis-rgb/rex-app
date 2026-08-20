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
struct ListDetailView: View {
    let route: ListRoute

    @State private var items: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var editing: FeedRecommendation?

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
                } else {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 8) {
                            if !group.heading.isEmpty {
                                Text(group.heading)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundStyle(RexColor.foreground)
                                    .padding(.top, 4)
                            }
                            ForEach(group.items) { item in
                                itemRow(item)
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
        .task { await load() }
        .sheet(item: $editing) { rec in
            EditRexView(
                rec: rec,
                onSaved: { Task { await load() } },
                onDeleted: { Task { await load() } }
            )
        }
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

            // Edit stays available forever, not just during the original
            // import review — "need to be able to edit the Rex within the
            // import once they are live" was explicit in the ask.
            HStack {
                Toggle(isOn: showInFeedBinding(item)) {
                    Text("Show on feed").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
                }
                .tint(RexColor.primary)
                .frame(maxWidth: 160)

                Spacer()

                Button {
                    editing = item
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
                    is_anonymous: item.is_anonymous, list_section: item.list_section, show_in_feed: newValue
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
