import SwiftUI

/// Weekly leaderboard — who's Rex'd the most in the last seven days.
/// Renders nothing when empty so it never leaves a hole in the feed.
struct TopRexxersView: View {
    @State private var rexxers: [TopRexxer] = []
    @State private var isLoading = true

    var body: some View {
        if !rexxers.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.md) {
                HStack(spacing: RexSpacing.sm) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(RexColor.accent)
                    Text("Top Rexxers this week")
                        .font(RexFont.text(13, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.lg) {
                        ForEach(Array(rexxers.enumerated()), id: \.element.id) { index, person in
                            NavigationLink(value: UserProfileRoute(
                                userId: person.user_id,
                                name: person.display_name ?? person.username
                            )) {
                            VStack(spacing: RexSpacing.xs) {
                                ZStack(alignment: .topTrailing) {
                                    UserAvatarView(
                                        url: person.avatar_url,
                                        name: person.display_name ?? person.username,
                                        size: 46
                                    )
                                    // Only the winner gets the accent colour —
                                    // Oxblood is for emphasis, used sparingly.
                                    if index == 0 {
                                        Circle()
                                            .fill(RexColor.accent)
                                            .frame(width: 16, height: 16)
                                            .overlay(
                                                Text("1")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.white)
                                            )
                                            .offset(x: 3, y: -3)
                                    }
                                }
                                Text(person.display_name ?? person.username)
                                    .font(RexFont.text(11, weight: .medium))
                                    .foregroundStyle(RexColor.foreground)
                                    .lineLimit(1)
                                    .frame(maxWidth: 62)
                                Text("\(person.rex_count)")
                                    .font(RexFont.text(10))
                                    .foregroundStyle(RexColor.mutedForeground)
                            }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(RexSpacing.cardPadding)
            .rexCard()
            .task { await load() }
        } else {
            // Still needs to run the fetch on first appearance.
            Color.clear.frame(height: 0).task { await load() }
        }
    }

    private func load() async {
        guard isLoading else { return }
        rexxers = (try? await RexAPI.shared.fetchTopRexxers(limit: 5)) ?? []
        isLoading = false
    }
}
