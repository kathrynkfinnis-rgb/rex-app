import SwiftUI

/// Like / comment / save / want / share, shown on every feed card.
/// Deliberately quiet: icon-only, muted until acted on, so the row doesn't
/// compete with the content above it.
struct RexCardActions: View {
    let rec: FeedRecommendation
    /// How many people (including the author) have Rex'd this item. Passed
    /// in rather than fetched here — every screen that shows this card
    /// already batch-fetches counts for a whole page at once (RexAPI.
    /// fetchRexCounts) rather than one row at a time.
    var rexCount: Int = 0
    /// #130 — where tapping the comment icon should go. The card is one
    /// tap target (so swipe-to-delete works), so this can't be its own
    /// NavigationLink; the parent hands the same push it uses for the
    /// card itself back in through here, same pattern as onAuthorTap.
    var onCommentTap: (() -> Void)? = nil

    @State private var liked = false
    @State private var likeCount = 0
    @State private var wanted = false
    @State private var commentCount = 0
    @State private var busy = false
    /// "Use the little rex icon to indicate how many others have Rex'd it —
    /// should be clickable so you can see a list."
    @State private var showingRexers = false

    /// #177 — used to share plain text with no link at all, so there was
    /// nothing for the recipient to actually open. `/r/$id` is a real public
    /// page the web app already serves (OG tags, sign-up prompt, "Open in
    /// REX" deep link) — same URL shape ShareButton uses on web already.
    private var shareURL: URL {
        URL(string: "https://pocket-app-pioneers.lovable.app/r/\(rec.id)")!
    }

    private var shareText: String {
        let title = rec.items?.title ?? "this"
        let who = rec.profiles?.display_name ?? rec.profiles?.username ?? "A friend"
        return "\(who) Rex'd \(title) on REX"
    }

    var body: some View {
        // .md rather than .lg between icons — at 16pt-per-gap this row was
        // routinely 130pt+ wide (4 icons, some with counts/labels) and won
        // the fight against the poster's name on the other end of the row,
        // which is what actually truncated first since Text compresses
        // before a Button's intrinsic icon size does.
        HStack(spacing: RexSpacing.md) {
            // Shown always, count included, same as the reference design —
            // unlike heart/comment (which hide a zero count), this one's
            // whole point is to always be a visible, tappable "who's Rex'd
            // this" entry point, not just an active-state indicator.
            Button {
                showingRexers = true
            } label: {
                HStack(spacing: 3) {
                    Image("RexDinoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 16)
                    Text("\(rexCount)")
                        .font(RexFont.text(11))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            }
            .buttonStyle(.plain)
            .disabled(rexCount == 0)
            .accessibilityLabel(rexCount > 0 ? "\(rexCount) people have Rex'd this — see who" : "Nobody else has Rex'd this yet")

            // Both key off a real recommendation row (rec.id) — a want has
            // no such row (it's a separate, simpler `wants` table keyed by
            // item, not a recommendation), so there's nowhere to attach a
            // like or a comment to one yet. Kathryn's call: hide these two
            // rather than show an icon that does nothing when tapped: the
            // dino-count and bookmark below both key off the item instead,
            // so those stay fully functional either way.
            if !rec.isWant {
                action(
                    // .destructive (the spec's Error red), not .accent — accent
                    // is gold now, reserved for premium/award/featured contexts,
                    // and a liked heart isn't one of those.
                    icon: liked ? "heart.fill" : "heart",
                    tint: liked ? RexColor.destructive : RexColor.mutedForeground,
                    count: likeCount,
                    label: liked ? "Unlike" : "Like"
                ) {
                    Task { await toggleLike() }
                }

                // Comments live on the detail screen. #130 — this used to rely
                // on allowsHitTesting(false) letting the tap fall through to
                // the card's own onTap; that didn't reliably happen on a card
                // this gesture-laden (feed/profile, wrapped in SwipeToRemove),
                // so callers that pass onCommentTap now get an explicit push
                // instead, same as the like/save buttons next to it. Screens
                // that haven't wired it (a friend's profile, a collection —
                // both wrap the whole card in their own NavigationLink already)
                // keep the old pass-through so they're untouched by this fix.
                action(icon: "bubble.left", tint: RexColor.mutedForeground,
                       count: commentCount, label: "Comments") {
                    onCommentTap?()
                }
                .allowsHitTesting(onCommentTap != nil)
            }

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

            // `/r/$id` is a real public page, but it's built specifically
            // for a recommendation id — a want has no equivalent page
            // (that'd need a web-side route + RPC of its own), so sharing
            // one right now would just hand out a dead link. Held back for
            // wants until that exists, rather than ship a broken share.
            if !rec.isWant {
                ShareLink(item: shareURL, message: Text(shareText)) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 15))
                        .foregroundStyle(RexColor.mutedForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share with friends")
            }
        }
        .sheet(isPresented: $showingRexers) {
            RexersSheetView(itemId: rec.item_id, itemTitle: rec.items?.title ?? "this")
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
                    // Text wraps by default once an HStack runs short on
                    // room — "Saved" was wrapping one letter per line. This
                    // pins it to its natural single-line width instead.
                    Text(activeLabel)
                        .font(RexFont.text(11, weight: .medium))
                        .foregroundStyle(tint)
                        .fixedSize()
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
        wanted = (try? await RexAPI.shared.isWanted(itemId: rec.item_id)) ?? false
        // rec.id is a synthetic "want-<uuid>" for a want, not a real
        // recommendations.id — these two are keyed to that real row, so
        // there's nothing meaningful to fetch (see the `!rec.isWant` guards
        // around their icons above).
        guard !rec.isWant else { return }
        if let entry = try? await RexAPI.shared.fetchLikeState(recommendationIds: [rec.id])[rec.id] {
            likeCount = entry.count
            liked = entry.likedByMe
        }
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
