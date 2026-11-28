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
    /// Oct 18 — "perhaps here it should say 'Kathryn and X others' so that
    /// it's easier to click on the hyperlink. At the moment, hard to press on
    /// the number to see who's liked it."
    ///
    /// The number sat inside the heart button, so pressing it liked the post
    /// rather than showing who had. A line of its own, with a name on it, is
    /// both a real target and something you can read at a glance. Empty for a
    /// want, whose likes live in their own table and carry no names yet, and
    /// for anyone whose profile is hidden — then the row stays as it was.
    @State private var likerNames: [String] = []
    @State private var showingLikers = false
    @State private var wanted = false
    @State private var commentCount = 0
    @State private var busy = false
    /// "Use the little rex icon to indicate how many others have Rex'd it —
    /// should be clickable so you can see a list."

    /// #177 — used to share plain text with no link at all, so there was
    /// nothing for the recipient to actually open. The link opens a real
    /// public page on find-rex.com: the Rex itself, whoever posted it, and a
    /// way in for someone who hasn't got the app yet.
    private var shareURL: URL? {
        // Oct 5 — "want to be able to send 'want to try' via WhatsApp."
        // A want's feed row carries the want's own id behind a "want-" prefix
        // (FeedRecommendation.isWant), and /w/<id> is its public page.
        if rec.isWant {
            return RexShareLink.wantURL(wantId: String(rec.id.dropFirst("want-".count)))
        }
        return RexShareLink.url(recommendationId: rec.id, type: rec.items?.type)
    }

    /// A trip lives at /t/ rather than /r/, so the code has to carry which
    /// page it leads to — share_links.kind, matching the migration's check.
    private var shareKind: String {
        if rec.isWant { return "want" }
        return RexCategory(rawType: rec.items?.type) == .trip ? "trip" : "rec"
    }

    private var shareTargetId: String {
        rec.isWant ? String(rec.id.dropFirst("want-".count)) : rec.id
    }

    private var shareText: String {
        let title = rec.items?.title ?? "this"
        let who = rec.profiles?.display_name ?? rec.profiles?.username ?? "A friend"
        // Oct 5 — the link and the invitation come from RexShareLink.message
        // so every share in the app reads the same in a chat thread.
        let lead = rec.isWant
            ? "\(who) wants to try \(title) on Rex"
            : "\(who) Rex'd \(title) on Rex"
        return RexShareLink.message(lead, url: shareURL)
    }

    var body: some View {
        // .md rather than .lg between icons — at 16pt-per-gap this row was
        // routinely 130pt+ wide (4 icons, some with counts/labels) and won
        // the fight against the poster's name on the other end of the row,
        // which is what actually truncated first since Text compresses
        // before a Button's intrinsic icon size does.
        VStack(alignment: .leading, spacing: RexSpacing.xs) {
        HStack(spacing: RexSpacing.md) {
            // Nov 22 — "can we remove the Rex icon to give more space to
            // the name, and then move the 'liked by' up a bit."
            //
            // The dino and its count used to sit here, always visible. It
            // was the widest thing in the row after the name — a 15pt glyph,
            // a count pinned to its natural width, 12pt of padding and 12pt
            // of stack spacing, about 52pt in all — and this row has been
            // over budget on a 390pt phone all day. Taking it out is both
            // what was asked for and what stops the card demanding more
            // width than the screen has.
            //
            // Nothing is lost: "Also Rex'd by N friends" already says the
            // same thing higher up the card, in words, and it is the thing
            // people actually tapped.

            // Sept 5 — these two used to be hidden on a want, because a
            // want has no recommendation row for a like or comment to hang
            // off. want_likes / want_comments (migration 20260905140000)
            // give it one of its own, so they're back for everything.
            do {
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

            // A want shares too now: /w/<id> renders it the same way /r/<id>
            // renders a Rex, so the link is live either way. A blast is still
            // held back — it's a question put to your friends, and a public
            // page for one would be addressed to nobody.
            if !rec.isBlast, let shareURL {
                RexShareButton(
                    kind: shareKind,
                    targetId: shareTargetId,
                    fallbackURL: shareURL,
                    message: shareText
                ) {
                    Image(systemName: "paperplane")
                        // Same step down as the other three — this row is one
                        // row, and a send icon two points larger than the
                        // heart beside it is what "uniform" was about.
                        .font(.system(size: 15))
                        .foregroundStyle(RexColor.mutedForeground)
                        // Height only — see action() below for why a minWidth
                        // here broke the feed.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        // Same target as the three built by action() above —
                        // share is not built by that helper, so it has to say
                        // so itself or it stays a 15pt dot between two 44pt
                        // neighbours.
                        // Nov 22 — vertical padding gone. The 44pt frame
                        // above already is the target, so this only made the
                        // row 20pt taller than it needed to be, which is what
                        // pushed "liked by" so far down the card.
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Share with friends")
            }
        }
        if !likerNames.isEmpty {
            Button { showingLikers = true } label: {
                Text(likedByLine)
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(1)
                    // Nov 22 — pinned to the leading edge. It was drifting
                    // out to the right, because the row above is as wide as
                    // the card and this inherited that width without saying
                    // where in it to sit.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("See who liked this")
        }
        }
        .sheet(isPresented: $showingLikers) {
            LikersSheetView(recommendationId: rec.id)
        }
        .task { await loadState() }
    }

    /// "Liked by Phoebe", "Liked by Phoebe and 3 others". Your own like is
    /// never the name — the filled heart beside it already says that.
    private var likedByLine: String {
        guard let first = likerNames.first else { return "" }
        let others = likeCount - 1
        if others <= 0 { return "Liked by \(first)" }
        return "Liked by \(first) and \(others) \(others == 1 ? "other" : "others")"
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
                    // Nov 28 — "make the font uniform in the profile and the
                    // heart, comment etc. section, making that part smaller."
                    // 17 was the same size as the title's body text; the deck
                    // sets this row a step below everything above it.
                    .font(.system(size: 15))
                    .foregroundStyle(tint)
                    // Nov 22 — height only, deliberately. This was
                    // minWidth: 44 for one build and it broke the feed:
                    // "there is no margin at the side of the screen any
                    // more, or buffer between items."
                    //
                    // The width was already handled by the .padding below,
                    // so a 44pt minWidth was 44 PLUS 12 of padding — 56pt
                    // per action. Five actions, the avatar, the poster's
                    // name and the counts come to roughly 350pt of minimum
                    // width against the ~315 a card offers on a 393pt
                    // phone. An HStack that cannot fit does not shrink; it
                    // reports the width it needs, which made the card wider
                    // than the screen. A vertical ScrollView centres
                    // oversized content, so the rail and the left margin
                    // went off the left edge and the thumbnail and rating
                    // badge were clipped off the right — margins gone from
                    // both sides at once, which is what she saw.
                    //
                    // 44 tall is free: nothing competes for vertical room.
                    // 44 wide is not available here at any price, and the
                    // glyph plus its padding is about 29pt, which is what
                    // the row can actually afford.
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
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
                        .fixedSize()
                }
            }
            // Nov 22 — "need to make sure the buttons are tappable, so need
            // to be bigger and with slightly bigger gaps, esp the
            // like/save/share on the feed."
            //
            // The padding is the fix rather than the icon size. A 15pt glyph
            // with no padding is a 15pt target, well under the 44pt Apple
            // asks for and well under what a thumb hits while scrolling —
            // which is why a like sometimes did nothing and sometimes opened
            // the card underneath. contentShape makes the padded area
            // tappable; without it the hit test still follows the glyph.
            //
            // Vertical padding is free, horizontal costs row width. The note
            // on the HStack above explains why this row cannot grow much:
            // past about 130pt it wins the fight with the poster's name and
            // truncates it. Hence 6 each side rather than the .lg gap, which
            // buys 12pt between adjacent targets without that.
            //
            // Nov 22 — the vertical 10 came out. Free is not the same as
            // wanted: the glyph already sits in a 44pt-tall frame, so this
            // was 20pt of nothing on top of a target that was already big
            // enough, and it is what put "liked by" so far below the row.
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(label)
    }

    private func loadState() async {
        wanted = (try? await RexAPI.shared.isWanted(itemId: rec.item_id)) ?? false
        // A want's likes and comments live in their own tables keyed by the
        // real wants.id, which is rec.id minus its "want-" prefix.
        if let wantId {
            if let entry = try? await RexAPI.shared.fetchWantLikeState(wantIds: [wantId])[wantId] {
                likeCount = entry.count
                liked = entry.likedByMe
            }
            commentCount = (try? await RexAPI.shared.fetchWantCommentCounts(wantIds: [wantId])[wantId]) ?? 0
            return
        }
        if let entry = try? await RexAPI.shared.fetchLikeState(recommendationIds: [rec.id])[rec.id] {
            likeCount = entry.count
            liked = entry.likedByMe
            likerNames = entry.names
        }
        commentCount = (try? await RexAPI.shared.fetchCommentCounts(recommendationIds: [rec.id])[rec.id]) ?? 0
    }

    /// The real `wants.id` behind a want card, or nil for a normal Rex.
    private var wantId: String? {
        guard rec.isWant else { return nil }
        return String(rec.id.dropFirst("want-".count))
    }

    /// Optimistic, rolling back if the write fails.
    private func toggleLike() async {
        let next = !liked
        liked = next
        likeCount = max(0, likeCount + (next ? 1 : -1))
        do {
            if let wantId {
                try await RexAPI.shared.setWantLike(wantId: wantId, liked: next)
            } else {
                try await RexAPI.shared.setLike(recommendationId: rec.id, liked: next)
            }
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

/// Oct 18 — who liked this, opened from the "Liked by…" line on a card.
///
/// LikesCommentsView has had a likers sheet since 3 October ("You can't see
/// who liked a post", reported twice), but only reachable from inside that
/// screen. The card now has a line worth tapping, so it needs somewhere to
/// go without first opening comments.
struct LikersSheetView: View {
    let recommendationId: String

    @Environment(\.dismiss) private var dismiss
    @State private var likers: [RexProfileDetail] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && likers.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if likers.isEmpty {
                    Text("Nobody yet.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(likers) { person in
                                NavigationLink(value: UserProfileRoute(
                                    userId: person.id,
                                    name: person.display_name ?? person.username
                                )) {
                                    HStack(spacing: RexSpacing.md) {
                                        UserAvatarView(
                                            url: person.avatar_url,
                                            name: person.display_name ?? person.username,
                                            size: 34
                                        )
                                        Text(person.display_name ?? person.username)
                                            .font(RexFont.text(15, weight: .medium))
                                            .foregroundStyle(RexColor.foreground)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, RexSpacing.page)
                                    .padding(.vertical, RexSpacing.md)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(RexColor.divider)
                                    .padding(.leading, RexSpacing.page)
                            }
                        }
                    }
                }
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle(likers.count == 1 ? "1 like" : "\(likers.count) likes")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UserProfileRoute.self) { UserProfileView(route: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(RexColor.primary)
        .task {
            likers = (try? await RexAPI.shared.fetchLikers(recommendationId: recommendationId)) ?? []
            isLoading = false
        }
    }
}
