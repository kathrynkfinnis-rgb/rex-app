import SwiftUI

/// Sept 29 — "Talk to Rex", Kathryn's name for it. Oct 3 — back to "Ask Rex",
/// which is what it was called first. Only the user-facing strings changed;
/// the file and the edge function keep their names so the history stays
/// followable.
///
/// Explore keeps everything it had; this sits above it. The bar on Explore
/// opens this screen, and this screen opens on prompts rather than an empty
/// box, because nobody knows what to type into an empty box.
///
/// The prompts that matter name a person — "what are Phoebe's favourite
/// places" — and they're built from your real friends. Every other app's
/// version of this screen has to ask about taste in the abstract; REX can ask
/// about people, because it knows who your friends are and what they've Rex'd.
///
/// The one rule the design has to hold: a friend's Rex and a web find never
/// look alike. A friend's is the ordinary feed card — rail, face, their own
/// words, their rating. A web find is dashed, tinted, globed, and has none of
/// those things, because nobody you know has vouched for it.
struct TalkToRexRoute: Hashable {}

struct TalkToRexView: View {
    /// Tapping a friend's card should open it, which the caller owns.
    var onOpenItem: (String) -> Void

    @State private var question = ""
    @State private var answers: [AskRexAnswer] = []
    @State private var isThinking = false
    /// The question currently in flight, so it can stay on screen.
    @State private var pending: String?
    @State private var errorMessage: String?
    @State private var friends: [FoundPerson] = []
    @State private var addingFromWeb: RexSearchHit?
    @FocusState private var focused: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    if answers.isEmpty && !isThinking {
                        opener
                    }

                    ForEach(answers) { answer in
                        AskRexAnswerBlock(
                            answer: answer,
                            onOpenItem: onOpenItem,
                            onRexThis: { addingFromWeb = $0 }
                        )
                        .id(answer.id)
                    }

                    // The question stays on screen while Rex thinks about it.
                    // Without this the prompt cards vanish and all that's left
                    // is a spinner, so you can't see what you asked.
                    if isThinking, let pending {
                        Text(pending)
                            .font(RexFont.text(14, weight: .medium))
                            .foregroundStyle(RexColor.primaryForeground)
                            .padding(.horizontal, RexSpacing.md)
                            .padding(.vertical, RexSpacing.sm)
                            .background(RexColor.primary)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if isThinking { thinking }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // So the last answer can scroll clear of the ask bar.
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, RexSpacing.page)
                .padding(.top, RexSpacing.lg)
                .padding(.bottom, RexSpacing.xxl)
            }
            .background(RexColor.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: answers.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: isThinking) { _, thinking in
                if thinking { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom) { askBar }
        .navigationTitle("Ask Rex")
        .navigationBarTitleDisplayMode(.inline)
        .rexDismissableKeyboard()
        .sheet(item: $addingFromWeb) { hit in
            AddRexView(onDone: {}, initialPlaceHit: hit)
        }
        .task { await loadFriends() }
    }

    // MARK: - Opening state

    private var opener: some View {
        VStack(alignment: .leading, spacing: RexSpacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recommendations,\nfrom people you know")
                    .font(RexFont.display(26, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The more your friends Rex, the better this gets.")
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.mutedForeground)
            }
            .padding(.top, RexSpacing.xl)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: RexSpacing.sm),
                                GridItem(.flexible(), spacing: RexSpacing.sm)],
                      spacing: RexSpacing.sm) {
                ForEach(prompts, id: \.text) { prompt in
                    Button {
                        ask(prompt.text)
                    } label: {
                        HStack(alignment: .top, spacing: RexSpacing.sm) {
                            if let friend = prompt.friend {
                                UserAvatarView(
                                    url: friend.avatar_url,
                                    name: friend.display_name ?? friend.username,
                                    size: 20
                                )
                            } else {
                                Text(prompt.emoji).font(.system(size: 15))
                            }
                            Text(prompt.text)
                                .font(RexFont.text(13))
                                .foregroundStyle(RexColor.foreground)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(RexSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }


    private struct Prompt {
        let text: String
        var emoji: String = "✦"
        var friend: FoundPerson? = nil
    }

    /// Built from real friends where there are any. The person-shaped prompts
    /// go first: they're the ones only REX can offer, and they're the ones
    /// that best explain what this screen is for.
    private var prompts: [Prompt] {
        var list: [Prompt] = []
        for friend in friends.prefix(2) {
            let name = (friend.display_name ?? friend.username)
                .split(separator: " ").first.map(String.init) ?? friend.username
            list.append(Prompt(text: "What are \(name)'s favourite places?", friend: friend))
        }
        list.append(Prompt(text: "What should I read next?", emoji: "📖"))
        list.append(Prompt(text: "A funny film, under two hours", emoji: "🍿"))
        list.append(Prompt(text: "Somewhere for dinner this weekend", emoji: "🍽"))
        list.append(Prompt(text: "Three days in Lisbon with two kids", emoji: "🧳"))
        return list
    }

    private var thinking: some View {
        HStack(spacing: RexSpacing.sm) {
            ProgressView().scaleEffect(0.8)
            Text("Looking through your friends' Rex…")
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .padding(.vertical, RexSpacing.sm)
    }

    // MARK: - Asking

    private var askBar: some View {
        HStack(spacing: RexSpacing.sm) {
            TextField("Ask for anything", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .font(RexFont.text(15))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { ask(question) }

            Button {
                ask(question)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RexColor.primaryForeground)
                    .frame(width: 32, height: 32)
                    .background(RexColor.primary)
                    .clipShape(Circle())
            }
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
            .opacity(question.trimmingCharacters(in: .whitespaces).isEmpty || isThinking ? 0.4 : 1)
        }
        .padding(.horizontal, RexSpacing.md)
        .padding(.vertical, RexSpacing.sm)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
        .padding(.horizontal, RexSpacing.page)
        .padding(.bottom, RexSpacing.sm)
        .background(RexColor.background)
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        question = ""
        focused = false
        errorMessage = nil
        pending = trimmed
        isThinking = true

        Task {
            // Only the last few turns — enough for "and something shorter?"
            // to make sense, not so much that the bill grows with the
            // conversation.
            let history = answers.suffix(3).flatMap { answer in
                [AskRexTurn(role: "them", text: answer.question),
                 AskRexTurn(role: "rex", text: answer.prose)]
            }
            do {
                let answer = try await AskRex.ask(trimmed, history: Array(history))
                answers.append(answer)
            } catch {
                errorMessage = error.localizedDescription
            }
            isThinking = false
            pending = nil
        }
    }

    private func loadFriends() async {
        guard friends.isEmpty, let me = RexAPI.shared.currentUserId else { return }
        friends = ((try? await RexAPI.shared.fetchFriendsOf(userId: me)) ?? [])
            .shuffled()
    }
}

/// The rendered form of one answer.
///
/// Its own view, observing the answer, because the web results arrive after
/// the rest of it — see AskRex.ask. A struct passed by value couldn't be
/// updated in place once it was on screen.
struct AskRexAnswerBlock: View {
    @ObservedObject var answer: AskRexAnswer
    var onOpenItem: (String) -> Void
    var onRexThis: (RexSearchHit) -> Void

    var body: some View { content }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            // What they asked, so a scroll-back reads as a conversation.
            Text(answer.question)
                .font(RexFont.text(14, weight: .medium))
                .foregroundStyle(RexColor.primaryForeground)
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, RexSpacing.sm)
                .background(RexColor.primary)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)

            if !answer.prose.isEmpty {
                Text(answer.prose)
                    .font(RexFont.text(15))
                    .foregroundStyle(RexColor.foreground.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(answer.friends) { rec in
                VStack(alignment: .leading, spacing: 4) {
                    // Rex's reason sits ABOVE the card and in Rex's voice, so
                    // it can never be mistaken for the note the friend wrote
                    // inside it.
                    //
                    // And it's dropped when it's just the note again. The
                    // prompt asks for something the note doesn't say, but the
                    // first live answer still handed back Danny's own sentence
                    // verbatim above his own card — which reads as two people
                    // agreeing when it's one person quoted twice.
                    if let why = answer.reasons[rec.id], !echoesNote(why, rec.note) {
                        Text(why)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                            .padding(.leading, 2)
                    }
                    // The card draws its own interior taps (author, comments);
                    // the body of it opens the item, the way the feed does.
                    RecommendationCardView(rec: rec)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenItem(rec.item_id) }
                }
            }

            // Still looking: said plainly, because the alternative is an
            // answer that appears to have finished with nothing in it.
            if answer.isResolvingWeb {
                HStack(spacing: RexSpacing.sm) {
                    ProgressView().scaleEffect(0.7)
                    Text("Looking a few more up\u{2026}")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                }
                .padding(.top, RexSpacing.xs)
            }

            if !answer.web.isEmpty {
                VStack(alignment: .leading, spacing: RexSpacing.sm) {
                    Text(answer.friends.isEmpty
                         ? "Nobody you know has Rex'd this yet — from the web:"
                         : "Not Rex'd by anyone yet — from the web:")
                        .font(RexFont.text(12, weight: .medium))
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.top, RexSpacing.xs)

                    ForEach(answer.web) { result in
                        webCardView(result)
                    }
                }
            }

            if answer.friends.isEmpty && answer.web.isEmpty && !answer.isResolvingWeb {
                Text("Nothing to go on for that one yet. As your friends Rex more, this gets better.")
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Deliberately unlike a feed card in every way that carries meaning: no
    /// rail, no avatar, no rating, a dashed edge and a tint that appears
    /// nowhere else in REX. Nobody you know has vouched for this.
    private func webCardView(_ result: AskRexWebResult) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                Text("From the web · not Rex'd yet")
                    .font(RexFont.text(11, weight: .medium))
            }
            .foregroundStyle(RexColor.mutedForeground)

            Text(result.hit.title)
                .font(RexFont.display(17, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = result.hit.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(2)
            }

            if let why = result.why, !why.isEmpty {
                Text(why)
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.foreground.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: RexSpacing.md) {
                // The whole point of the web tier is that it feeds the thing
                // that replaces it: try it, rate it, and next time it's a
                // friend's Rex rather than a stranger's suggestion.
                Button {
                    onRexThis(result.hit)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 12))
                        Text("Rex this").font(RexFont.text(13, weight: .semibold))
                    }
                    .foregroundStyle(RexColor.primary)
                }
                .buttonStyle(.plain)

                if let link = RexExternalLink.forItem(RexItem(
                    id: result.hit.externalId,
                    type: result.category.rawValue,
                    title: result.hit.title,
                    subtitle: result.hit.subtitle,
                    image_url: result.hit.imageURL,
                    genre: result.hit.genre,
                    address: result.hit.address,
                    external_id: result.hit.externalId,
                    external_source: result.hit.externalSource
                )) {
                    RexOutboundLinkButton(url: link.url) {
                        HStack(spacing: 5) {
                            Image(systemName: link.symbol).font(.system(size: 12))
                            Text("Look it up").font(RexFont.text(13, weight: .semibold))
                        }
                        .foregroundStyle(RexColor.mutedForeground)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(RexSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RexColor.muted.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(RexColor.border)
        )
    }

    /// True when Rex's line is really the friend's note wearing a hat. Compared
    /// on words rather than characters, so a reworded half-sentence is caught
    /// as well as a straight copy: if most of what Rex said is already in the
    /// note, the note can say it by itself.
    private func echoesNote(_ why: String, _ note: String?) -> Bool {
        guard let note, !note.isEmpty else { return false }
        let words = { (text: String) -> Set<String> in
            Set(text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 3 })
        }
        let whyWords = words(why)
        guard whyWords.count >= 3 else { return false }
        let shared = whyWords.intersection(words(note))
        return Double(shared.count) / Double(whyWords.count) > 0.6
    }
}
