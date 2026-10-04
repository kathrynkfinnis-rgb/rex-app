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
    /// Phoebe, 17 Sept: "Can edit or delete comments". Only your own —
    /// the id of the one being edited, and the text as it's being changed.
    @State private var editingId: String?
    @State private var editDraft = ""
    @State private var pendingDelete: RexComment?
    @FocusState private var editFocused: Bool
    /// Sept 28 — "@-tagging people in comments". The server has notified on
    /// @username since July; this is the half that lets you write one without
    /// knowing the spelling by heart.
    @State private var friends: [RexProfileDetail] = []
    /// Oct 3 — who liked this, behind the count.
    @State private var showingLikers = false
    @State private var likers: [RexProfileDetail] = []
    @State private var isLoadingLikers = false

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            HStack(spacing: RexSpacing.xl) {
                Button {
                    Task { await toggleLike() }
                } label: {
                    Image(systemName: likedByMe ? "heart.fill" : "heart")
                        .font(.system(size: 17))
                        .foregroundStyle(likedByMe ? RexColor.destructive : RexColor.mutedForeground)
                }
                .buttonStyle(.plain)

                // Oct 3 — "You can't see who liked a post", twice. The heart
                // toggles your own like; the number beside it now opens the
                // list of who, which is the part people were asking for. Two
                // targets rather than one so tapping the count can't
                // accidentally unlike the post.
                if likeCount > 0 {
                    Button {
                        showingLikers = true
                    } label: {
                        Text("\(likeCount)")
                            .font(RexFont.text(14, weight: .medium))
                            .foregroundStyle(RexColor.mutedForeground)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See who liked this")
                    .padding(.leading, -RexSpacing.md)
                }

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
                                if editingId == comment.id {
                                    editor(for: comment)
                                } else {
                                    MentionedText(text: comment.body)
                                }
                            }
                            Spacer()
                        }
                        // Your own comments only. A long press is where the
                        // app already puts "things you can do to this" —
                        // same as a card in the feed.
                        .contextMenu {
                            if comment.user_id == RexAPI.shared.currentUserId, editingId == nil {
                                Button {
                                    editDraft = comment.body
                                    editingId = comment.id
                                    editFocused = true
                                } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    pendingDelete = comment
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            } else if !isLoading {
                Text("No comments yet — be the first.")
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            if let query = MentionDraft.inProgress(in: draft), !friends.isEmpty {
                MentionPicker(query: query, friends: friends) { friend in
                    draft = MentionDraft.complete(draft, with: friend.username)
                }
            }

            HStack(spacing: RexSpacing.sm) {
                // Oct 4 — "when you comment need to expand the comment bubble
                // down not across." It was a single-line field with a fixed
                // 42pt height, so a comment longer than the box scrolled
                // sideways under the cursor and you could only ever see the
                // tail of what you'd written.
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .font(RexFont.text(14))
                    .focused($draftFocused)
                    .lineLimit(1...6)
                    .submitLabel(.send)
                    .onSubmit { Task { await post() } }
                    .padding(.horizontal, RexSpacing.md)
                    .padding(.vertical, 11)
                    .frame(minHeight: 42)
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
            friends = (try? await RexAPI.shared.fetchAcceptedFriendProfiles()) ?? []
            // Focus set while a sheet is still animating in is dropped, so
            // wait for it to settle first.
            if focusOnAppear {
                try? await Task.sleep(nanoseconds: 450_000_000)
                draftFocused = true
            }
        }
        .confirmationDialog(
            "Delete this comment?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let comment = pendingDelete {
                    pendingDelete = nil
                    Task { await delete(comment) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .sheet(isPresented: $showingLikers) {
            NavigationStack {
                Group {
                    if isLoadingLikers && likers.isEmpty {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if likers.isEmpty {
                        Text("Nobody yet.")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.mutedForeground)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(likers) { profile in
                                    NavigationLink(value: UserProfileRoute(
                                        userId: profile.id,
                                        name: profile.display_name ?? profile.username
                                    )) {
                                        HStack(spacing: RexSpacing.md) {
                                            UserAvatarView(
                                                url: profile.avatar_url,
                                                name: profile.display_name ?? profile.username,
                                                size: 40
                                            )
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(profile.display_name ?? profile.username)
                                                    .font(RexFont.text(15, weight: .medium))
                                                    .foregroundStyle(RexColor.foreground)
                                                Text("@\(profile.username)")
                                                    .font(RexFont.text(12))
                                                    .foregroundStyle(RexColor.mutedForeground)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(RexColor.mutedForeground)
                                        }
                                        .padding(.horizontal, RexSpacing.page)
                                        .padding(.vertical, RexSpacing.sm + 2)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, RexSpacing.sm)
                        }
                    }
                }
                .background(RexColor.background.ignoresSafeArea())
                .navigationTitle(likeCount == 1 ? "1 like" : "\(likeCount) likes")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: UserProfileRoute.self) { UserProfileView(route: $0) }
            }
            .presentationDetents([.medium, .large])
            .tint(RexColor.primary)
            .task {
                isLoadingLikers = true
                likers = (try? await RexAPI.shared.fetchLikers(recommendationId: recommendationId)) ?? []
                isLoadingLikers = false
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
            comments = (loadedComments ?? []).filter { !RexAPI.shared.hiddenUsers.contains($0.user_id) }
        } else {
            async let likes = try? RexAPI.shared.fetchLikeState(recommendationIds: [recommendationId])
            async let fetched = try? RexAPI.shared.fetchComments(recommendationId: recommendationId)
            let (likeState, loadedComments) = await (likes, fetched)
            if let entry = likeState?[recommendationId] {
                likeCount = entry.count
                likedByMe = entry.likedByMe
            }
            comments = (loadedComments ?? []).filter { !RexAPI.shared.hiddenUsers.contains($0.user_id) }
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

    /// An edit happens in place, where the comment already is, rather than
    /// in a sheet that hides the thread you're correcting yourself in.
    @ViewBuilder
    private func editor(for comment: RexComment) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            TextField("Comment", text: $editDraft, axis: .vertical)
                .font(RexFont.text(14))
                .focused($editFocused)
                .lineLimit(1...6)
                .padding(.horizontal, RexSpacing.sm)
                .padding(.vertical, 8)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )
            HStack(spacing: RexSpacing.md) {
                Button("Cancel") { editingId = nil; editDraft = "" }
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.mutedForeground)
                Button("Save") { Task { await saveEdit(comment) } }
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                    .disabled(
                        editDraft.trimmingCharacters(in: .whitespaces).isEmpty
                            || editDraft == comment.body
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func saveEdit(_ comment: RexComment) async {
        let text = editDraft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        do {
            try await RexAPI.shared.updateComment(id: comment.id, body: text, isWant: wantId != nil)
            editingId = nil
            editDraft = ""
            await reloadComments()
        } catch {
            // Leave the editor open with what they typed still in it.
        }
    }

    private func delete(_ comment: RexComment) async {
        // Gone from the thread straight away; the reload confirms it.
        comments.removeAll { $0.id == comment.id }
        try? await RexAPI.shared.deleteComment(id: comment.id, isWant: wantId != nil)
        await reloadComments()
    }

    private func reloadComments() async {
        if let wantId {
            comments = (try? await RexAPI.shared.fetchWantComments(wantId: wantId)) ?? comments
        } else {
            comments = (try? await RexAPI.shared.fetchComments(recommendationId: recommendationId)) ?? comments
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
