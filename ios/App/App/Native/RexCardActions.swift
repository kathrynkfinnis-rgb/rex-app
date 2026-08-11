import SwiftUI

/// Like / comment / save / want / share, shown on every feed card.
/// Deliberately quiet: icon-only, muted until acted on, so the row doesn't
/// compete with the content above it.
struct RexCardActions: View {
    let rec: FeedRecommendation

    @State private var liked = false
    @State private var likeCount = 0
    @State private var wanted = false
    @State private var commentCount = 0
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
                count: likeCount,
                label: liked ? "Unlike" : "Like"
            ) {
                Task { await toggleLike() }
            }

            // Comments live on the detail screen; this is a visual affordance
            // that the card is tappable through to them.
            action(icon: "bubble.left", tint: RexColor.mutedForeground,
                   count: commentCount, label: "Comments") {}
                .allowsHitTesting(false)

            // A single save action. There used to be two (bookmark and +)
            // writing to different tables, which testers found confusing —
            // "what does that tick mean?". Everything saved now lands in
            // My list.
            action(
                icon: wanted ? "bookmark.fill" : "bookmark",
                tint: wanted ? RexColor.primary : RexColor.mutedForeground,
                count: 0,
                label: wanted ? "Remove from my list" : "Save to my list",
                activeLabel: "Saved",
                isActive: wanted
            ) {
                Task { await toggleWant() }
            }

            ShareLink(item: shareText) {
                Image(systemName: "paperplane")
                    .font(.system(size: 15))
                    .foregroundStyle(RexColor.mutedForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share with friends")
        }
        .task { await loadState() }
    }

    /// `label` doubles as the accessibility label and, when the action is on,
    /// a short caption — "what does that tick mean?" was real feedback.
    private func action(
        icon: String,
        tint: Color,
        count: Int,
        label: String,
        activeLabel: String? = nil,
        isActive: Bool = false,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                if isActive, let activeLabel {
                    Text(activeLabel)
                        .font(RexFont.text(11, weight: .medium))
                        .foregroundStyle(tint)
                } else if count > 0 {
                    Text("\(count)")
                        .font(RexFont.text(11))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(label)
    }

    private func loadState() async {
        if let entry = try? await RexAPI.shared.fetchLikeState(recommendationIds: [rec.id])[rec.id] {
            likeCount = entry.count
            liked = entry.likedByMe
        }
        wanted = (try? await RexAPI.shared.isWanted(itemId: rec.item_id)) ?? false
        commentCount = (try? await RexAPI.shared.fetchCommentCounts(recommendationIds: [rec.id])[rec.id]) ?? 0
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
