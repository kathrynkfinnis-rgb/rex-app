import SwiftUI

/// Like button + comment thread for a single Rex, mirroring the web
/// LikesComments component. Used on the item detail screen.
struct LikesCommentsView: View {
    let recommendationId: String

    @State private var likeCount = 0
    @State private var likedByMe = false
    @State private var comments: [RexComment] = []
    @State private var draft = ""
    @State private var isPosting = false
    @State private var isLoading = true

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
                    .padding(.horizontal, RexSpacing.md)
                    .frame(height: 42)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                            .stroke(RexColor.border, lineWidth: 1)
                    )

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
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        async let likes = try? RexAPI.shared.fetchLikeState(recommendationIds: [recommendationId])
        async let fetched = try? RexAPI.shared.fetchComments(recommendationId: recommendationId)
        let (likeState, loadedComments) = await (likes, fetched)
        if let entry = likeState?[recommendationId] {
            likeCount = entry.count
            likedByMe = entry.likedByMe
        }
        comments = loadedComments ?? []
        isLoading = false
    }

    /// Optimistic — the button responds immediately and rolls back on failure.
    private func toggleLike() async {
        let next = !likedByMe
        likedByMe = next
        likeCount = max(0, likeCount + (next ? 1 : -1))
        do {
            try await RexAPI.shared.setLike(recommendationId: recommendationId, liked: next)
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
            try await RexAPI.shared.addComment(recommendationId: recommendationId, body: text)
            draft = ""
            comments = (try? await RexAPI.shared.fetchComments(recommendationId: recommendationId)) ?? comments
        } catch {
            // Keep the draft so the user doesn't lose what they typed.
        }
        isPosting = false
    }
}
