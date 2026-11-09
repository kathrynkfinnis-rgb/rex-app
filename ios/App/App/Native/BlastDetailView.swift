import SwiftUI

/// #132 — a blast is a question, not a verdict, and used to have nowhere to
/// go: tapping one in the feed did nothing (FeedView.open() explicitly
/// no-ops for isBlast), and there was no way to reply at all. This is that
/// missing screen: the ask itself, every response so far, and a way to add
/// one.
struct BlastRoute: Hashable, Identifiable {
    let requestId: String
    let title: String
    var id: String { requestId }
}

/// Nov 7 — see openAttached. A distinct type rather than a bare String so it
/// cannot collide with the `String` destination an ancestor may already have.
struct AttachedItemRoute: Hashable, Identifiable {
    let itemId: String
    var id: String { itemId }
}

struct BlastDetailView: View {
    let route: BlastRoute

    @State private var responses: [RequestComment] = []
    /// The suggestion being replied to, if any — the composer answers it
    /// rather than adding a new top-level suggestion.
    @State private var replyingTo: RequestComment?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var draft = ""
    /// Oct 18 — "you should be able to tag someone in comments on blasts
    /// (and all comments everywhere)." A blast is the one place a mention is
    /// most useful: the whole point is "who would know the answer to this",
    /// and naming them is how you ask.
    @State private var friends: [RexProfileDetail] = []
    @State private var mentionedProfile: UserProfileRoute?
    @State private var mentionLookupFailed = false
    /// Oct 3 — one of your own Rex, attached to the reply.
    @State private var attachedRex: RexItem?
    @State private var choosingRex = false
    @State private var isSending = false

    /// Nov 7 — the attached Rex's destination, owned by this screen.
    ///
    /// The chip was a `NavigationLink(value: item.id)`, which relies on some
    /// ancestor having registered `String`. The feed's stack has; the
    /// notifications stack registers nothing at all, so a blast opened from a
    /// notification — which is how most people reach one — drew a chip with a
    /// chevron on it that did nothing when tapped. Its own typed destination
    /// cannot be claimed or forgotten by whatever pushed this screen.
    @State private var openAttached: AttachedItemRoute?

    /// Nov 7 — "you also can't delete or edit comments."
    @State private var editingId: String?
    @State private var editDraft = ""
    @State private var pendingDelete: RequestComment?
    @FocusState private var editFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 10))
                        Text("BLAST").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(RexColor.accent)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RexColor.accent.opacity(0.1))
                    .clipShape(Capsule())

                    Text(route.title)
                        .font(RexFont.display(24, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)

                    Rectangle().fill(RexColor.divider).frame(height: 1)

                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, RexSpacing.xl)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    } else if responses.isEmpty {
                        Text("No responses yet — be the first to help.")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.mutedForeground)
                    } else {
                        VStack(alignment: .leading, spacing: RexSpacing.md) {
                            ForEach(topLevelResponses) { response in
                                responseRow(response)
                            }
                        }
                    }
                }
                .padding(RexSpacing.page)
            }

            Divider().overlay(RexColor.border)
            composer
                .navigationDestination(item: $openAttached) { route in
                    ItemDetailView(itemId: route.itemId)
                }
                .alert(
                    pendingDelete?.parent_id == nil ? "Delete this suggestion?" : "Delete this reply?",
                    isPresented: Binding(
                        get: { pendingDelete != nil },
                        set: { if !$0 { pendingDelete = nil } }
                    )
                ) {
                    Button("Delete", role: .destructive) {
                        if let comment = pendingDelete {
                            pendingDelete = nil
                            Task { await deleteResponse(comment) }
                        }
                    }
                    Button("Cancel", role: .cancel) { pendingDelete = nil }
                } message: {
                    // parent_id cascades, so deleting a suggestion takes the
                    // conversation under it. Say so rather than surprising
                    // somebody who only wanted to fix their own wording.
                    Text(
                        replyCount(of: pendingDelete) > 0
                        ? "The replies to it go too. This can't be undone."
                        : "This can't be undone."
                    )
                }
                .alert("Link \u{201C}\(linkWords)\u{201D}", isPresented: Binding(
                    get: { linkRange != nil },
                    set: { if !$0 { linkRange = nil } }
                )) {
                    TextField("example.com", text: $linkURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Cancel", role: .cancel) { linkRange = nil }
                    Button("Link") {
                        if let range = linkRange, !linkURL.trimmingCharacters(in: .whitespaces).isEmpty {
                            draft = RexLinkableTextEditor.applyLink(
                                to: draft, range: range,
                                url: linkURL.trimmingCharacters(in: .whitespaces)
                            )
                        }
                        linkRange = nil
                    }
                } message: {
                    Text("Those words become the link. Nobody sees the address.")
                }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Blast")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
        .task {
            // The picker's candidates, loaded the same way the Rex comment
            // composer loads them.
            friends = (try? await RexAPI.shared.fetchAcceptedFriendProfiles()) ?? []
        }
        .sheet(item: $mentionedProfile) { route in
            NavigationStack { UserProfileView(route: route) }
                .tint(RexColor.primary)
        }
        .alert("Couldn't open that", isPresented: $mentionLookupFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That username doesn't match anyone you can see.")
        }
    }

    /// Turns a tapped `@name` into the person behind it. A mention is only
    /// text — nothing records which profile it meant — so the username is
    /// resolved on the way. Same as LikesCommentsView.
    private func openMention(_ username: String) async {
        guard let id = await RexAPI.shared.profileId(forUsername: username) else {
            mentionLookupFailed = true
            return
        }
        mentionedProfile = UserProfileRoute(userId: id, name: username)
    }

    /// Sept 7 — "it would be nice to 'like' or reply to someone's Rex on
    /// your blast". A response was read-only: the only way to react was
    /// another top-level suggestion, which reads as a new answer rather than
    /// a reply to one. Replies thread one level under the suggestion they
    /// answer; anything deeper is a lot of interface for "which one did you
    /// mean?" and an answer.
    private func responseRow(_ response: RequestComment) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            HStack(alignment: .top, spacing: RexSpacing.sm) {
                UserAvatarView(
                    url: response.profiles?.avatar_url,
                    name: response.profiles?.display_name ?? response.profiles?.username ?? "?",
                    size: 30
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(response.profiles?.display_name ?? response.profiles?.username ?? "Someone")
                        .font(RexFont.text(13, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    if editingId == response.id {
                        inlineEditor(for: response)
                    } else {
                        MentionedText(text: response.body, font: RexFont.text(15)) { name in
                            Task { await openMention(name) }
                        }
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.foreground.opacity(0.9))
                    }

                    if let item = response.items {
                        attachedChip(item)
                    }
                }
                Spacer(minLength: RexSpacing.sm)

                if response.user_id == RexAPI.shared.currentUserId {
                    ownerMenu(response)
                }
            }

            HStack(spacing: RexSpacing.lg) {
                Button {
                    Task { await toggleLike(response) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: response.likedByMe ? "heart.fill" : "heart")
                            .font(.system(size: 13))
                            .foregroundStyle(response.likedByMe ? RexColor.destructive : RexColor.mutedForeground)
                        if response.likeCount > 0 {
                            Text("\(response.likeCount)")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.snappy) { replyingTo = response }
                } label: {
                    // Oct 18 — "not letting me click reply on comments."
                    //
                    // Twelve-point text with no padding and no contentShape:
                    // a target around thirty-six points by fifteen. The same
                    // fault the Rex comments had on 14 October ("can't reply
                    // to comments even when clicking 'reply' button"), fixed
                    // there and never here.
                    Text("Reply")
                        .font(RexFont.text(12, weight: .semibold))
                        .foregroundStyle(RexColor.primary)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.leading, 38)

            ForEach(replies(to: response)) { reply in
                HStack(alignment: .top, spacing: RexSpacing.sm) {
                    UserAvatarView(
                        url: reply.profiles?.avatar_url,
                        name: reply.profiles?.display_name ?? reply.profiles?.username ?? "?",
                        size: 22
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reply.profiles?.display_name ?? reply.profiles?.username ?? "Someone")
                            .font(RexFont.text(12, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        if editingId == reply.id {
                            inlineEditor(for: reply)
                        } else {
                            MentionedText(text: reply.body, font: RexFont.text(14)) { name in
                                Task { await openMention(name) }
                            }
                                .font(RexFont.text(13))
                                .foregroundStyle(RexColor.foreground.opacity(0.9))
                        }

                        // Nov 7 — the half that was missing. See attachedChip.
                        if let item = reply.items {
                            attachedChip(item)
                        }
                    }
                    Spacer(minLength: RexSpacing.sm)

                    if reply.user_id == RexAPI.shared.currentUserId {
                        ownerMenu(reply)
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(RexSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
    }

    /// Nov 7 — "Phoebe attached a list and it hasn't come up."
    ///
    /// It had come up, in the sense that it was saved: suggested_item_id was
    /// set and fetchRequestComments has always read it back. What it had not
    /// done is appear, because this chip was written inline in the top-level
    /// branch of responseRow and the reply branch below drew an avatar, a
    /// name and the body text — nothing else. Attach something to a reply
    /// rather than to a suggestion of its own and it went in and was never
    /// drawn again, which is indistinguishable from it not having worked.
    ///
    /// A list reaches this the same way anything else does: a list is an item
    /// with type "list", and searchMyRexItems filters by nothing, so it was
    /// always attachable. Same chip, same destination.
    private func attachedChip(_ item: RexItem) -> some View {
        Button {
            openAttached = AttachedItemRoute(itemId: item.id)
        } label: {
            HStack(spacing: RexSpacing.sm) {
                Image(systemName: RexCategory(rawType: item.type).symbol)
                    .font(.system(size: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(RexFont.text(13, weight: .semibold))
                        .lineLimit(1)
                    if let sub = item.address ?? item.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(RexFont.text(11))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
            }
            .foregroundStyle(RexColor.foreground)
            .padding(RexSpacing.sm + 2)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    /// Nov 7 — edit and delete, on your own. The same "…" LikesCommentsView
    /// has had since 17 September, which is where this was asked for first.
    private func ownerMenu(_ comment: RequestComment) -> some View {
        Menu {
            Button {
                editDraft = comment.body
                editingId = comment.id
                editFocused = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingDelete = comment
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(RexColor.mutedForeground)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }

    /// An edit happens where the comment already is, matching how a Rex's
    /// comments do it rather than opening a sheet over the conversation.
    private func inlineEditor(for comment: RequestComment) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            TextField("Your suggestion", text: $editDraft, axis: .vertical)
                .font(RexFont.text(14))
                .focused($editFocused)
                .padding(RexSpacing.sm)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )
            HStack(spacing: RexSpacing.md) {
                Spacer(minLength: 0)
                Button("Cancel") { editingId = nil; editDraft = "" }
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.mutedForeground)
                Button("Save") { Task { await saveEdit(comment) } }
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                    .disabled(editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func saveEdit(_ comment: RequestComment) async {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await RexAPI.shared.updateRequestComment(id: comment.id, body: trimmed)
            editingId = nil
            editDraft = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteResponse(_ comment: RequestComment) async {
        do {
            try await RexAPI.shared.deleteRequestComment(id: comment.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Top-level suggestions only — replies are drawn under their parent.
    private var topLevelResponses: [RequestComment] {
        responses.filter { $0.parent_id == nil }
    }

    /// How much the delete confirmation has to warn about — nothing for a
    /// reply, and for a suggestion whatever cascades with it.
    private func replyCount(of comment: RequestComment?) -> Int {
        guard let comment, comment.parent_id == nil else { return 0 }
        return replies(to: comment).count
    }

    private func replies(to response: RequestComment) -> [RequestComment] {
        responses.filter { $0.parent_id == response.id }
    }

    private func toggleLike(_ response: RequestComment) async {
        guard let index = responses.firstIndex(where: { $0.id == response.id }) else { return }
        let next = !responses[index].likedByMe
        responses[index].likedByMe = next
        responses[index].likeCount = max(0, responses[index].likeCount + (next ? 1 : -1))
        do {
            try await RexAPI.shared.setRequestCommentLike(commentId: response.id, liked: next)
        } catch {
            responses[index].likedByMe = !next
            responses[index].likeCount = max(0, responses[index].likeCount + (next ? -1 : 1))
        }
    }

    /// Oct 14 — the words being linked, and where they sit in the draft.
    @State private var linkRange: NSRange?
    @State private var linkWords = ""
    @State private var linkURL = ""

    private var composer: some View {
        VStack(spacing: RexSpacing.sm) {
            // Oct 3 — "when you reply to a blast, you should be able to tag
            // Rex to the response." A reply that names somewhere is useful; a
            // reply that attaches the actual Rex is what the blast was asking
            // for, and it carries the rating, the note and the way through to
            // the place.
            if let attached = attachedRex {
                HStack(spacing: RexSpacing.sm) {
                    Image(systemName: RexCategory(rawType: attached.type).symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(RexColor.primary)
                    Text(attached.title)
                        .font(RexFont.text(13, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        attachedRex = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, RexSpacing.sm)
                .background(RexColor.badgeBackground)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            }

            // The other half of the same report: replyingTo was set and
            // nothing on screen ever said so, so even a tap that worked
            // looked like one that hadn't.
            if let replyingTo {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 10))
                    Text("Replying to \(replyingTo.profiles?.display_name ?? replyingTo.profiles?.username ?? "someone")")
                        .font(RexFont.text(11.5))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(.snappy) { self.replyingTo = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(RexColor.mutedForeground)
                .padding(.horizontal, RexSpacing.sm)
                .padding(.vertical, 5)
                .background(RexColor.badgeBackground, in: Capsule())
            }

            if let query = MentionDraft.inProgress(in: draft), !friends.isEmpty {
                MentionPicker(query: query, friends: friends) { friend in
                    draft = MentionDraft.complete(draft, with: friend.username)
                }
            }

            HStack(spacing: RexSpacing.sm) {
            Button {
                choosingRex = true
            } label: {
                Image(systemName: attachedRex == nil ? "plus.circle" : "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(RexColor.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attach one of your Rex")

            // Oct 14 — select words, tap Link. See RexLinkableTextEditor for
            // why this is a UITextView and not a TextField.
            RexLinkableTextEditor(
                text: $draft,
                placeholder: "Suggest something\u{2026}",
                onRequestLink: { range, words in
                    linkRange = range
                    linkWords = words
                    linkURL = ""
                }
            )
                .font(RexFont.text(15))
                .frame(minHeight: 38, maxHeight: 110)
                .padding(.horizontal, RexSpacing.sm)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )

            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView().tint(RexColor.primaryForeground)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RexColor.primaryForeground)
                }
            }
            .frame(width: 40, height: 40)
            .background(RexColor.primary)
            .clipShape(Circle())
            // An attached Rex is a complete answer on its own — the words are
            // optional once you've pointed at the thing.
            .disabled(isSending || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachedRex == nil))
            }
        }
        .padding(RexSpacing.page)
        .sheet(isPresented: $choosingRex) {
            AttachRexSheet { picked in attachedRex = picked }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            responses = try await RexAPI.shared.fetchRequestComments(requestId: route.requestId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func send() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || attachedRex != nil else { return }
        isSending = true
        do {
            try await RexAPI.shared.createRequestComment(
                requestId: route.requestId,
                // A reply that's only an attached Rex still needs a body, and
                // the item's own name is the honest thing to put there.
                body: trimmed.isEmpty ? (attachedRex?.title ?? trimmed) : trimmed,
                parentId: replyingTo?.id,
                suggestedItemId: attachedRex?.id
            )
            replyingTo = nil
            draft = ""
            attachedRex = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
