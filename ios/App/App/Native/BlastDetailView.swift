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

struct BlastDetailView: View {
    let route: BlastRoute

    @State private var responses: [RequestComment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var draft = ""
    @State private var isSending = false

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
                            ForEach(responses) { response in
                                responseRow(response)
                            }
                        }
                    }
                }
                .padding(RexSpacing.page)
            }

            Divider().overlay(RexColor.border)
            composer
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Blast")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
    }

    private func responseRow(_ response: RequestComment) -> some View {
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
                Text(response.body)
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.foreground.opacity(0.9))
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

    private var composer: some View {
        HStack(spacing: RexSpacing.sm) {
            TextField("Suggest something…", text: $draft, axis: .vertical)
                .font(RexFont.text(15))
                .lineLimit(1...4)
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, RexSpacing.sm)
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
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(RexSpacing.page)
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
        guard !trimmed.isEmpty else { return }
        isSending = true
        do {
            try await RexAPI.shared.createRequestComment(requestId: route.requestId, body: trimmed)
            draft = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
