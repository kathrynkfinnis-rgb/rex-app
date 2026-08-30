import SwiftUI

/// "Use the little rex icon to indicate how many others have Rex'd it —
/// should be clickable so you can see a list." The count itself already
/// existed (rexCounts, computed from fetchRexCounts) — this is the missing
/// list behind it, presented as a plain sheet rather than a full push since
/// it's a quick glance, not a page you navigate around in.
struct RexersSheetView: View {
    let itemId: String
    let itemTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var rexers: [RexerInfo] = []
    @State private var isLoading = true

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rexers.isEmpty {
                    Text("Nobody's Rex'd this yet.")
                        .font(.footnote)
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rexers) { rexer in
                                row(rexer)
                                if rexer.id != rexers.last?.id {
                                    Rectangle().fill(RexColor.divider).frame(height: 1)
                                        .padding(.leading, 52)
                                }
                            }
                        }
                    }
                }
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Rex'd \(itemTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func row(_ rexer: RexerInfo) -> some View {
        HStack(spacing: RexSpacing.sm) {
            if rexer.is_anonymous == true {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 14))
                    .foregroundStyle(RexColor.mutedForeground)
                    .frame(width: 36, height: 36)
                    .background(RexColor.muted)
                    .clipShape(Circle())
                Text("Anonymous")
                    .font(RexFont.text(15, weight: .medium))
                    .foregroundStyle(RexColor.mutedForeground)
            } else if let profile = rexer.profiles {
                UserAvatarView(
                    url: profile.avatar_url,
                    name: profile.display_name ?? profile.username,
                    size: 36
                )
                Text(profile.display_name ?? profile.username)
                    .font(RexFont.text(15, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
            } else {
                Image(systemName: "person.fill")
                    .frame(width: 36, height: 36)
                    .background(RexColor.muted)
                    .clipShape(Circle())
                Text("Someone")
                    .font(RexFont.text(15, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
            }

            Spacer()

            if rexer.rating > 0 {
                RexRatingBadge(raw: rexer.rating, compact: true)
            }
        }
        .padding(.horizontal, RexSpacing.cardPadding)
        .padding(.vertical, RexSpacing.sm + 2)
    }

    private func load() async {
        rexers = (try? await RexAPI.shared.fetchRexers(itemId: itemId)) ?? []
        isLoading = false
    }
}
