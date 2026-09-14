import SwiftUI

/// Like button + comment thread for a single Rex, mirroring the web
/// LikesComments component. Used on the item detail screen, list and trip
/// pages, and the comments sheet the feed's comment icon opens.
struct LikesCommentsView: View {
    let recommendationId: String
    /// Sept 14 — put the cursor in the comment box on arrival. The feed's
    /// comment icon opens this in a sheet, and someone who tapped "comment"
    /// wants to type, not find the box.
    var focusOnAppear: Bool = false

    /// Wants keep their likes and comments in their own tables
    /// (want_likes / want_comments, 5 Sept) — the synthetic "want-<id>"
    /// recommendation id the feed gives a want says which kind this is.
    private var wantId: String? {
        recommendationId.hasPrefix("want-") ? String(recommendationId.dropFirst("want-".count)) : nil
    }

    @State private var likeCount = 0
    @State private var likedByMe = false
    @State private var comments: [RexComment] = []
    @State private var draft = ""
    @State private var isPosting = false
    @State private var isLoading = true
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            HStack(spacing: RexSpacing.xl) {
                Button {
                    Task { await toggleLike() }
                } label: {
                    HStack(spacing: RexSpacing.sm) {
                        Image(systemName: likedByMe ? "heart.fill" : "heart")
                            .font(.system(size: 17))
                            .foregroundStyle(likedByMe ? RexColor.destructive : RexColor.mutedForeground)
                        if likeCount > 0 {
                            Text("\(likeCount)")
                                .font(RexFont.text(14, weight: .medium))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                }
                .buttonStyle(.plain)

                // #130 — this had no action at all, unlike the like button
                // right next to it: "Clicking on 'comment' isn't
                // registering so I can't comment on the Rex." Comments
                // already show inline below, so tapping this just focuses
                // the comment field and brings up the keyboard, same as
                // tapping the field itself.
                Button {
                    draftFocused = true
                } label: {
                    HStack(spacing: RexSpacing.sm) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16))
                            .foregroundStyle(RexColor.mutedForeground)
                        if !comments.isEmpty {
                            Text("\(comments.count)")
                                .font(RexFont.text(14, weight: .medium))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if !comments.isEmpty {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    ForEach(comments) { comment in
                        HStack(alignment: .top, spacing: RexSpacing.sm) {
                            UserAvatarView(
                                url: comment.profiles?.avatar_url,
                                name: comment.profiles?.display_name ?? comment.profiles?.username ?? "?",
                                size: 26
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(comment.profiles?.display_name ?? comment.profiles?.username ?? "Someone")
                                    .font(RexFont.text(13, weight: .semibold))
                                    .foregroundStyle(RexColor.foreground)
                                Text(comment.body)
                                    .font(RexFont.text(14))
                                    .foregroundStyle(RexColor.foreground.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                    }
                }
            } else if !isLoading {
                Text("No comments yet — be the first.")
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            HStack(spacing: RexSpacing.sm) {
                TextField("Add a comment…", text: $draft)
                    .font(RexFont.text(14))
                    .focused($draftFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await post() } }
                    .padding(.horizontal, RexSpacing.md)
                    .frame(height: 42)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                            .stroke(RexColor.border, lineWidth: 1)
                    )
                    // The keyboard could otherwise sit over the Post button
                    // with no way to reach it — this toolbar gives an explicit
                    // way to dismiss it, and Return now posts directly too.
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { draftFocused = false }
                        }
                    }

                Button {
                    Task { await post() }
                } label: {
                    if isPosting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(
                                draft.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? RexColor.disabled : RexColor.primary
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isPosting || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task {
            await load()
            // Focus set while a sheet is still animating in is dropped, so
            // wait for it to settle first.
            if focusOnAppear {
                try? await Task.sleep(nanoseconds: 450_000_000)
                draftFocused = true
            }
        }
    }

    private func load() async {
        isLoading = true
        if let wantId {
            async let likes = try? RexAPI.shared.fetchWantLikeState(wantIds: [wantId])
            async let fetched = try? RexAPI.shared.fetchWantComments(wantId: wantId)
            let (likeState, loadedComments) = await (likes, fetched)
            if let entry = likeState?[wantId] {
                likeCount = entry.count
                likedByMe = entry.likedByMe
            }
            comments = loadedComments ?? []
        } else {
            async let likes = try? RexAPI.shared.fetchLikeState(recommendationIds: [recommendationId])
            async let fetched = try? RexAPI.shared.fetchComments(recommendationId: recommendationId)
            let (likeState, loadedComments) = await (likes, fetched)
            if let entry = likeState?[recommendationId] {
                likeCount = entry.count
                likedByMe = entry.likedByMe
            }
            comments = loadedComments ?? []
        }
        isLoading = false
    }

    /// Optimistic — the button responds immediately and rolls back on failure.
    private func toggleLike() async {
        let next = !likedByMe
        likedByMe = next
        likeCount = max(0, likeCount + (next ? 1 : -1))
        do {
            if let wantId {
                try await RexAPI.shared.setWantLike(wantId: wantId, liked: next)
            } else {
                try await RexAPI.shared.setLike(recommendationId: recommendationId, liked: next)
            }
        } catch {
            likedByMe = !next
            likeCount = max(0, likeCount + (next ? -1 : 1))
        }
    }

    private func post() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isPosting = true
        do {
            if let wantId {
                try await RexAPI.shared.addWantComment(wantId: wantId, body: text)
                draft = ""
                comments = (try? await RexAPI.shared.fetchWantComments(wantId: wantId)) ?? comments
            } else {
                try await RexAPI.shared.addComment(recommendationId: recommendationId, body: text)
                draft = ""
                comments = (try? await RexAPI.shared.fetchComments(recommendationId: recommendationId)) ?? comments
            }
        } catch {
            // Keep the draft so the user doesn't lose what they typed.
        }
        isPosting = false
    }
}


/// Sept 14 — "I pressed the comment icon on the feed and it didn't work".
/// It opened the Rex's page, where the comment box sits at the bottom
/// under every friend's Rex of the same thing — or, for a list or trip
/// before build 38, nowhere at all. Now it opens this: the one Rex, its
/// comments, and the cursor already in the box.
struct CommentsSheet: View {
    let rec: FeedRecommendation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    HStack(spacing: RexSpacing.sm) {
                        UserAvatarView(
                            url: rec.profiles?.avatar_url,
                            name: rec.profiles?.display_name ?? rec.profiles?.username ?? "?",
                            size: 28
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rec.items?.title ?? "")
                                .font(RexFont.display(17, weight: .semibold))
                                .foregroundStyle(RexColor.foreground)
                                .lineLimit(2)
                            Text(rec.profiles?.display_name ?? rec.profiles?.username ?? "")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                    if let note = rec.note, !note.isEmpty {
                        Text("\u{201C}\(note)\u{201D}")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.foreground.opacity(0.88))
                    }
                    Rectangle().fill(RexColor.divider).frame(height: 1)
                    LikesCommentsView(recommendationId: rec.id, focusOnAppear: true)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .presentationDetents([.medium, .large])
    }
}
