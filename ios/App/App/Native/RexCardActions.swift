import SwiftUI

/// Like / comment / save / want / share, shown on every feed card.
/// Deliberately quiet: icon-only, muted until acted on, so the row doesn't
/// compete with the content above it.
struct RexCardActions: View {
    let rec: FeedRecommendation

    @State private var liked = false
    @State private var likeCount = 0
    @State private var saved = false
    @State private var wanted = false
    @State private var busy = false

    private var shareText: String {
        let title = rec.items?.title ?? "this"
        let who = rec.profiles?.display_name ?? rec.profiles?.username ?? "A friend"
        return "\(who) Rex'd \(title) on REX"
    }

    var body: some View {
        HStack(spacing: RexSpacing.lg) {
            action(
                icon: liked ? "heart.fill" : "heart",
                tint: liked ? RexColor.accent : RexColor.mutedForeground,
                count: likeCount
            ) {
                Task { await toggleLike() }
            }

            // Comments live on the detail screen; this is a visual affordance
            // that the card is tappable through to them.
            action(icon: "bubble.left", tint: RexColor.mutedForeground, count: 0) {}
                .allowsHitTesting(false)

            action(
                icon: saved ? "bookmark.fill" : "bookmark",
                tint: saved ? RexColor.primary : RexColor.mutedForeground,
                count: 0
            ) {
                Task { await toggleSave() }
            }

            action(
                icon: wanted ? "checkmark.circle.fill" : "plus.circle",
                tint: wanted ? RexColor.primary : RexColor.mutedForeground,
                count: 0
            ) {
                Task { await toggleWant() }
            }

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15))
                    .foregroundStyle(RexColor.mutedForeground)
            }
            .buttonStyle(.plain)
        }
        .task { await loadState() }
    }

    private func action(
        icon: String,
        tint: Color,
        count: Int,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                if count > 0 {
                    Text("\(count)")
                        .font(RexFont.text(11))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func loadState() async {
        if let entry = try? await RexAPI.shared.fetchLikeState(recommendationIds: [rec.id])[rec.id] {
            likeCount = entry.count
            liked = entry.likedByMe
        }
        saved = (try? await RexAPI.shared.isSaved(recommendationId: rec.id)) ?? false
        wanted = (try? await RexAPI.shared.isWanted(itemId: rec.item_id)) ?? false
    }

    /// Optimistic, rolling back if the write fails.
    private func toggleLike() async {
        let next = !liked
        liked = next
        likeCount = max(0, likeCount + (next ? 1 : -1))
        do {
            try await RexAPI.shared.setLike(recommendationId: rec.id, liked: next)
        } catch {
            liked = !next
            likeCount = max(0, likeCount + (next ? -1 : 1))
        }
    }

    private func toggleSave() async {
        busy = true
        let next = !saved
        saved = next
        do {
            try await RexAPI.shared.setSaved(recommendationId: rec.id, saved: next)
        } catch {
            saved = !next
        }
        busy = false
    }

    /// Tapping again removes it — every one of these buttons should undo.
    private func toggleWant() async {
        busy = true
        let next = !wanted
        wanted = next
        do {
            if next {
                try await RexAPI.shared.createWant(itemId: rec.item_id)
            } else {
                try await RexAPI.shared.removeWant(itemId: rec.item_id)
            }
        } catch {
            wanted = !next
        }
        busy = false
    }
}
