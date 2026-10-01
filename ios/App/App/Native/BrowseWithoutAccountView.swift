import SwiftUI

/// Oct 1 — App Store review, Guideline 5.1.1(v): "the app requires users to
/// register or log in to access features that are not account based."
///
/// Fair. Almost everything in REX genuinely is account-based — the feed, the
/// map, collections and Talk to Rex all show what people you are friends with
/// have recommended, and none of that can exist without an account. But the
/// Rexperts material is REX's own curated shelves and what the whole app has
/// Rex'd most this week. That is editorial. It doesn't depend on who you are,
/// and it was sitting behind a sign-up wall for no reason.
///
/// So this is the welcome screen's third door: look around first. It shows
/// exactly the content that isn't anyone's personal recommendation, and asks
/// for an account only when you want the thing an account is actually for —
/// what the people you know think.
///
/// Deliberately its own screen rather than a mode inside ExploreView. Explore
/// is wired through friends' collections, your own recent Rex, filters derived
/// from them and the Talk to Rex bar; threading "but signed out" through all
/// of that would be a lot of new ways to accidentally show a stranger
/// somebody's recommendation. A separate screen can only show what it is
/// given.
struct BrowseWithoutAccountView: View {
    /// Both routes out: the welcome screen's two buttons, handed in so this
    /// screen doesn't have to know how sign-up is presented.
    var onSignUp: () -> Void
    var onSignIn: () -> Void

    @State private var trending: [TrendingItem] = []
    @State private var editorial: [EditorialCollection] = []
    @State private var isLoading = true
    @State private var showingJoinPrompt = false
    @State private var promptSubject: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.xl) {
                header

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 120)
                    }
                } else {
                    ForEach(editorial) { shelf in
                        editorialShelf(shelf)
                    }

                    if !trending.isEmpty {
                        trendingShelf
                    }

                    if trending.isEmpty && editorial.isEmpty {
                        Text("Nothing to show just yet — check back soon.")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                }

                joinCard
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.vertical, RexSpacing.lg)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Have a look around")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Join REX to see more", isPresented: $showingJoinPrompt) {
            Button("Not now", role: .cancel) {}
            Button("Create an account") { onSignUp() }
        } message: {
            Text(promptSubject.map {
                "\($0) is on REX. Sign up to see what your friends think of it, and add your own."
            } ?? "Sign up to see what your friends recommend, and add your own.")
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text("What REX is Rexing")
                .font(RexFont.display(26, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("""
                 A look at what's being recommended across REX right now. The real \
                 thing is seeing what the people you actually know think — that bit \
                 needs an account.
                 """)
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shelves

    private var trendingShelf: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            shelfHeading("Most Rex'd this week", tag: "ACROSS REX")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: RexSpacing.md) {
                    ForEach(trending, id: \.item_id) { item in
                        Button {
                            promptSubject = item.title
                            showingJoinPrompt = true
                        } label: {
                            tile(
                                title: item.title,
                                subtitle: item.rex_count == 1
                                    ? "1 Rex this week"
                                    : "\(item.rex_count) Rex this week",
                                imageURL: item.image_url,
                                type: item.type
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func editorialShelf(_ shelf: EditorialCollection) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            shelfHeading(shelf.title, tag: shelf.source_label.uppercased())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: RexSpacing.md) {
                    ForEach(shelf.items) { entry in
                        Button {
                            promptSubject = entry.title
                            showingJoinPrompt = true
                        } label: {
                            tile(
                                title: entry.title,
                                subtitle: entry.subtitle,
                                imageURL: entry.image_url,
                                type: shelf.category
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func shelfHeading(_ title: String, tag: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RexSpacing.sm) {
            Text(title)
                .font(RexFont.display(19, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text(tag)
                .font(RexFont.text(10, weight: .semibold))
                .foregroundStyle(RexColor.primary)
                .padding(.horizontal, RexSpacing.sm)
                .padding(.vertical, 3)
                .background(RexColor.badgeBackground)
                .clipShape(Capsule())
            Spacer(minLength: 0)
        }
    }

    private func tile(title: String, subtitle: String?, imageURL: String?, type: String?) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                    .fill(RexColor.muted)
                if let imageURL, let url = URL(string: imageURL) {
                    GoogleSafeAsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: RexCategory(rawType: type).symbol)
                            .font(.system(size: 22))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                } else {
                    Image(systemName: RexCategory(rawType: type).symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            }
            .frame(width: 150, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))

            Text(title)
                .font(RexFont.text(14, weight: .medium))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(1)
            }
        }
        .frame(width: 150, alignment: .leading)
    }

    // MARK: - The ask

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            Text("See what your friends think")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("""
                 REX is recommendations from people you actually know — where they \
                 ate, what they read, the trips worth copying. That needs an account, \
                 because it's about your friends and not ours.
                 """)
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onSignUp) {
                Text("Create an account").frame(maxWidth: .infinity)
            }
            .buttonStyle(RexPrimaryButtonStyle())

            Button(action: onSignIn) {
                Text("I already have an account")
                    .font(RexFont.text(15, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(RexSpacing.lg)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
    }

    private func load() async {
        async let trendingTask = RexAPI.shared.fetchTrendingItems(limit: 20)
        async let editorialTask = RexAPI.shared.fetchEditorialCollections()
        trending = (try? await trendingTask) ?? []
        editorial = (try? await editorialTask) ?? []
        isLoading = false
    }
}
