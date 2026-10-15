import SwiftUI

struct PersonRoute: Hashable {
    let personId: Int
    let name: String
    /// What you were looking at when you tapped them, so it isn't listed back.
    var excludingTitle: String?
}

/// Oct 15 — "like authors, can we make the cast clickable? So you can see
/// what else they've been in?"
///
/// The film and TV twin of AuthorBooksView, and built the same way: TMDB's
/// whole list of what they have been in, cross-referenced against our own
/// items so anything your friends have Rex'd says so. A credit nobody here
/// has touched is still worth showing — it is how you find the next thing —
/// but the count underneath is what makes this REX's screen rather than a
/// catalogue's.
struct PersonCreditsView: View {
    let route: PersonRoute

    @State private var credits: [RexSearchHit] = []
    @State private var rexCounts: [String: Int] = [:]
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RexBannerBand(category: .movie)
                    .padding(.horizontal, -RexSpacing.page)

                VStack(alignment: .leading, spacing: 0) {
                    RexCategoryPill(category: .movie)
                    Text(route.name)
                        .font(RexFont.display(30))
                        .foregroundStyle(RexColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                    if !credits.isEmpty {
                        Text("\(credits.count) credits \u{00B7} best known first")
                            .font(RexFont.editorial(21))
                            .foregroundStyle(RexColor.primary)
                            .padding(.top, 7)
                    }
                }
                .padding(.top, 10)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if credits.isEmpty {
                    Text("Nothing else listed for \(route.name).")
                        .font(RexFont.text(15))
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.top, RexSpacing.xl)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104), spacing: RexSpacing.md)],
                        alignment: .leading,
                        spacing: RexSpacing.lg
                    ) {
                        ForEach(credits) { credit in
                            creditTile(credit)
                        }
                    }
                    .padding(.top, RexSpacing.lg)
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.bottom, RexSpacing.xxl)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func creditTile(_ credit: RexSearchHit) -> some View {
        let count = rexCounts[credit.externalId] ?? 0
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if let urlString = credit.imageURL, let url = URL(string: urlString) {
                    GoogleSafeAsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { RexColor.muted }
                } else {
                    ZStack {
                        RexColor.badgeBackground
                        Image(systemName: RexCategory.movie.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(RexColor.primary)
                    }
                }
            }
            .frame(width: 104, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(credit.title)
                .font(RexFont.text(12.5, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle = credit.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
                    .lineLimit(1)
            }
            // The whole point of this screen being in REX rather than a
            // catalogue: somebody you know has seen it.
            if count > 0 {
                Text("\(count) Rex")
                    .font(RexFont.text(11, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
            }
        }
        .frame(width: 104, alignment: .leading)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let found = await RexSearch.personCredits(personId: route.personId)
        // Not the thing you tapped them in — you are already looking at it.
        credits = found.filter { credit in
            guard let excluded = route.excludingTitle else { return true }
            return credit.title.caseInsensitiveCompare(excluded) != .orderedSame
        }
        rexCounts = await RexAPI.shared.rexCountsByExternalId(
            externalIds: credits.map(\.externalId)
        )
    }
}

/// One face in the Cast row. A link when TMDB told us who they are, and the
/// same tile unwrapped when it didn't — rather than a tappable-looking thing
/// that goes nowhere.
struct CastTile<Content: View>: View {
    let member: RexSearch.CastMember
    var fromTitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let personId = member.personId {
            NavigationLink(value: PersonRoute(
                personId: personId, name: member.name, excludingTitle: fromTitle
            )) {
                content()
            }
            .buttonStyle(.plain)
        } else {
            content()
        }
    }
}
