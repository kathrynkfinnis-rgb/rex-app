import SwiftUI

/// Sept 17 — "please can we build the report or block functionality."
///
/// Reporting and blocking, and the list of who you've blocked. Both are
/// App Store requirements for user-generated content (Guideline 1.2), and
/// both are reachable from the same place people already look for actions:
/// the "…" on a card, and a person's profile.

/// What's being reported, carried through to the sheet.
struct ReportSubject: Identifiable {
    let kind: RexAPI.ReportTarget
    let id: String
    /// Who posted it — so repeat offenders are visible without chasing
    /// each report back to its content.
    let authorId: String?
    /// For the sheet's own copy: "this Rex", "Phoebe's comment"…
    let describedAs: String

    static func rex(_ rec: FeedRecommendation) -> ReportSubject {
        ReportSubject(
            kind: RexCategory(rawType: rec.items?.type) == .trip ? .trip
                : RexCategory(rawType: rec.items?.type) == .list ? .list
                : .recommendation,
            id: rec.id,
            authorId: rec.user_id,
            describedAs: rec.items.map { "\u{201C}\($0.title)\u{201D}" } ?? "this Rex"
        )
    }

    static func person(_ id: String, name: String) -> ReportSubject {
        ReportSubject(kind: .profile, id: id, authorId: id, describedAs: name)
    }

    static func comment(_ comment: RexComment) -> ReportSubject {
        ReportSubject(kind: .comment, id: comment.id, authorId: comment.user_id, describedAs: "this comment")
    }
}

struct ReportSheet: View {
    let subject: ReportSubject
    /// Offered at the end: reporting and blocking usually go together.
    var onBlocked: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var reason: String?
    @State private var detail = ""
    @State private var isSending = false
    @State private var sent = false
    @State private var alsoBlock = false
    @State private var errorMessage: String?

    /// Plain words, not policy language — someone reporting something
    /// unpleasant shouldn't have to work out which clause it breaches.
    private let reasons: [(value: String, label: String)] = [
        ("harassment", "Bullying or harassment"),
        ("hate", "Hate speech or discrimination"),
        ("sexual", "Nudity or sexual content"),
        ("violence", "Violence or graphic content"),
        ("self_harm", "Self-harm or suicide"),
        ("spam", "Spam or a scam"),
        ("impersonation", "Pretending to be someone else"),
        ("intellectual_property", "Uses my photo or work without permission"),
        ("misinformation", "False or misleading"),
        ("other", "Something else"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if sent {
                    thanks
                } else {
                    form
                }
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle(sent ? "" : "Report")
            .navigationBarTitleDisplayMode(.inline)
            .rexDismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }.disabled(isSending)
                }
            }
        }
        .tint(RexColor.primary)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: RexSpacing.lg) {
            Text("What's wrong with \(subject.describedAs)?")
                .font(RexFont.display(22, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(reasons, id: \.value) { option in
                    Button {
                        reason = option.value
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(RexFont.text(15))
                                .foregroundStyle(RexColor.foreground)
                            Spacer()
                            if reason == option.value {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(RexColor.primary)
                            }
                        }
                        .padding(RexSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rectangle().fill(RexColor.divider).frame(height: 1) }
                }
            }
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous).stroke(RexColor.border, lineWidth: 1))

            VStack(alignment: .leading, spacing: RexSpacing.xs) {
                Text("Anything else we should know? (optional)")
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                TextField("", text: $detail, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
            }

            if subject.authorId != nil, subject.authorId != RexAPI.shared.currentUserId {
                Toggle(isOn: $alsoBlock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also block them")
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text("You won't see each other's Rex, and any friendship between you ends.")
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(RexColor.primary)
            }

            if let errorMessage {
                Text(errorMessage).font(RexFont.text(13)).foregroundStyle(RexColor.destructive)
            }

            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                } else {
                    Text("Send report").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(RexPrimaryButtonStyle())
            .disabled(reason == nil || isSending)
            .opacity(reason == nil ? 0.5 : 1)

            Text("Reports go to the Rex team. We look at every one, usually the same day, and can remove content or suspend accounts.")
                .font(RexFont.text(12))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RexSpacing.page)
    }

    private var thanks: some View {
        VStack(spacing: RexSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(RexColor.primary)
            Text("Thanks for telling us")
                .font(RexFont.display(24, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text(alsoBlock
                 ? "We'll review this within a day. You won't see each other on Rex any more."
                 : "We'll review this within a day. If it breaks our rules we'll remove it.")
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { dismiss() }
                .buttonStyle(RexPrimaryButtonStyle())
                .padding(.top, RexSpacing.md)
        }
        .padding(RexSpacing.page)
        .padding(.top, RexSpacing.xxl)
    }

    private func send() async {
        guard let reason else { return }
        isSending = true
        errorMessage = nil
        do {
            try await RexAPI.shared.reportContent(
                kind: subject.kind, targetId: subject.id,
                targetUserId: subject.authorId, reason: reason, detail: detail
            )
            if alsoBlock, let authorId = subject.authorId {
                try await RexAPI.shared.blockUser(id: authorId)
                onBlocked?()
            }
            withAnimation { sent = true }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}

/// Settings → Your data & privacy → Blocked accounts.
struct BlockedAccountsView: View {
    @State private var blocked: [RexProfileDetail] = []
    @State private var isLoading = true
    @State private var busyIds: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if blocked.isEmpty {
                    Text("You haven't blocked anyone.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    Text("Blocked people can't see your Rex, and you can't see theirs.")
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.bottom, RexSpacing.xs)
                    ForEach(blocked) { person in
                        HStack(spacing: RexSpacing.md) {
                            UserAvatarView(url: person.avatar_url, name: person.display_name ?? person.username, size: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.display_name ?? person.username)
                                    .font(RexFont.text(14, weight: .semibold))
                                    .foregroundStyle(RexColor.foreground)
                                Text("@\(person.username)")
                                    .font(RexFont.text(12))
                                    .foregroundStyle(RexColor.mutedForeground)
                            }
                            Spacer()
                            Button {
                                Task { await unblock(person) }
                            } label: {
                                if busyIds.contains(person.id) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Unblock").font(RexFont.text(13, weight: .semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(RexColor.primary)
                        }
                        .padding(RexSpacing.md)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous).stroke(RexColor.border, lineWidth: 1))
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(RexFont.text(13)).foregroundStyle(RexColor.destructive)
                }
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Blocked accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            blocked = try await RexAPI.shared.fetchBlockedUsers()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func unblock(_ person: RexProfileDetail) async {
        busyIds.insert(person.id)
        do {
            try await RexAPI.shared.unblockUser(id: person.id)
            blocked.removeAll { $0.id == person.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        busyIds.remove(person.id)
    }
}

struct BlockedAccountsRoute: Hashable {}
