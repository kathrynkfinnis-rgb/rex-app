import SwiftUI

/// Sept 28 — "@-tagging people in comments".
///
/// The server half of this has worked since 30 July: a trigger reads
/// `@username` out of every comment and sends the person a "tagged you"
/// notification, gated on their own mention preference. What was missing was
/// any way to write one on purpose — you had to know someone's exact username
/// and type it from memory — and any sign, once posted, that a mention was a
/// mention rather than an ordinary run of text.
///
/// So this is the client half, and only the client half: a picker while you
/// type, and highlighting afterwards. Nothing new server-side.

/// The `@word` being typed right now, if the cursor is inside one.
///
/// Deliberately conservative about what counts. A mention has to start at the
/// beginning or after a space, so an email address doesn't open the picker
/// halfway through someone typing it.
enum MentionDraft {
    static func inProgress(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        let before = text.index(before: at)
        if at != text.startIndex, !text[before].isWhitespace { return nil }
        let word = text[text.index(after: at)...]
        // A space ends it: "@phoebe was right" is finished, not in progress.
        guard !word.contains(where: { $0.isWhitespace }) else { return nil }
        // The username rule the trigger itself uses.
        guard word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return String(word)
    }

    /// Swaps the half-typed `@word` for the username that was picked, and
    /// leaves a trailing space so the next word doesn't join onto it.
    static func complete(_ text: String, with username: String) -> String {
        guard let at = text.lastIndex(of: "@") else { return text }
        return String(text[text.startIndex..<at]) + "@" + username + " "
    }
}

/// The list of friends that drops in under the comment box while you're
/// mid-mention. Only friends: mentioning someone who can't see the Rex would
/// send a notification about something they can't open.
struct MentionPicker: View {
    let query: String
    let friends: [RexProfileDetail]
    var onPick: (RexProfileDetail) -> Void

    private var matches: [RexProfileDetail] {
        let term = query.lowercased()
        let pool = term.isEmpty ? friends : friends.filter {
            $0.username.lowercased().hasPrefix(term)
                || ($0.display_name ?? "").lowercased().contains(term)
        }
        return Array(pool.prefix(5))
    }

    var body: some View {
        if !matches.isEmpty {
            VStack(spacing: 0) {
                ForEach(matches) { friend in
                    Button {
                        onPick(friend)
                    } label: {
                        HStack(spacing: RexSpacing.sm) {
                            UserAvatarView(
                                url: friend.avatar_url,
                                name: friend.display_name ?? friend.username,
                                size: 26
                            )
                            VStack(alignment: .leading, spacing: 0) {
                                Text(friend.display_name ?? friend.username)
                                    .font(RexFont.text(14, weight: .medium))
                                    .foregroundStyle(RexColor.foreground)
                                Text("@\(friend.username)")
                                    .font(RexFont.text(12))
                                    .foregroundStyle(RexColor.mutedForeground)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, RexSpacing.md)
                        .padding(.vertical, RexSpacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) {
                        if friend.id != matches.first?.id {
                            Rectangle().fill(RexColor.divider).frame(height: 1)
                        }
                    }
                }
            }
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
        }
    }
}

/// A comment with its mentions picked out, so "@phoebebragg" reads as a
/// person rather than as punctuation. Built with AttributedString rather than
/// a row of Texts so the paragraph still wraps as one piece of prose.
struct MentionedText: View {
    let text: String
    var font: Font = RexFont.text(14)

    /// Same pattern as the database trigger, so what's highlighted here is
    /// exactly what will have notified someone.
    private var attributed: AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = RexColor.foreground.opacity(0.9)
        var searchStart = text.startIndex
        while let at = text[searchStart...].firstIndex(of: "@") {
            var end = text.index(after: at)
            while end < text.endIndex, text[end].isLetter || text[end].isNumber || text[end] == "_" {
                end = text.index(after: end)
            }
            let name = text[text.index(after: at)..<end]
            // The trigger's own rule: two to thirty characters.
            if name.count >= 2, name.count <= 30,
               let range = Range(at..<end, in: result) {
                result[range].foregroundColor = RexColor.primary
                result[range].font = font.weight(.semibold)
            }
            guard end < text.endIndex else { break }
            searchStart = end
        }
        return result
    }

    var body: some View {
        Text(attributed)
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
    }
}
