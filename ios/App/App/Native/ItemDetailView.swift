import SwiftUI

struct ItemDetailView: View {
    let itemId: String
    /// Oct 2 — "don't need the heading twice here". Inside the map's place
    /// sheet the item's name is already the first thing in the card, so the
    /// navigation bar repeating it is noise. Pushed as a page it still wants
    /// a title, so this is a parameter rather than a removal.
    var showsTitle: Bool = true

    @State private var item: RexItem?
    /// Sept 17 — synopsis and ratings for films, TV and books, fetched from
    /// the catalogue the item came from. See RexSearch.details.
    @State private var details: RexSearch.ItemDetails?
    /// Oct 2 — "could we have a button here to see more from this author, and
    /// then a list of other works and who has rex'd if any".
    @State private var moreByAuthor: [RexSearchHit] = []
    /// Lowercased title -> the item in REX, for whichever of the author's
    /// books someone here has actually Rex'd.
    @State private var authorBookItems: [String: RexItem] = [:]
    @State private var authorBookRexCounts: [String: Int] = [:]
    @State private var isLoadingDetails = false
    @State private var synopsisExpanded = false
    /// Oct 3 — Google Place Details for a place: its photos, its one-line
    /// description and its opening times. Held here only for the fetch that
    /// populated it; every later visit reads the cached columns off the item.
    @State private var placeDetails: RexPlaceDetails?
    @State private var hoursExpanded = false
    /// Oct 3 — press coverage, under "On Google".
    @State private var articles: [RexArticle] = []
    @State private var recs: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var rating: Double = 10
    @State private var note: String = ""
    @State private var isSaving = false
    /// "When you click into a 'want to try', you should be able to add to
    /// want to try — at the moment, on a TV want, I click in and can only
    /// rate, not add to want to try." A want is its own table/row, separate
    /// from a rated recommendation (see RexCardActions.toggleWant) — this
    /// screen only ever offered the rating form, with no way to see or
    /// toggle the want flag at all once you'd followed a want card in here.
    @State private var wanted = false
    @State private var isTogglingWant = false
    /// The card's own save button merged bookmark ("want to try") and this
    /// into one icon a while back — two save actions there tested as
    /// confusing ("what does that tick mean?"). Kathryn asked for a
    /// dedicated save-to-collection action back, just scoped to here (the
    /// full item page, which has the room) rather than reintroducing that
    /// on the card.
    /// Sept 9 — one sheet modifier, not several. Stacking `.sheet`
    /// modifiers on the same view silently drops all but one of them; see
    /// FeedView.ActiveSheet.
    private enum ActiveSheet: Identifiable {
        case collection(FeedRecommendation)
        case edit(FeedRecommendation)
        var id: String {
            switch self {
            case .collection(let rec): return "collection-\(rec.id)"
            case .edit(let rec): return "edit-\(rec.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    /// "View on map function via a button" — the feed/profile cards
    /// already had one (#133), the full item page never did.
    @Environment(\.viewOnMap) private var viewOnMap

    private var myRec: FeedRecommendation? {
        recs.first { $0.user_id == RexAPI.shared.currentUserId }
    }

    /// Which take a save-to-collection action here actually attaches to —
    /// collections are per-recommendation (saved_posts references one), so
    /// this needs a real rec. Your own take if you have one, otherwise
    /// whichever friend's take is showing — same as saving straight from
    /// their card in the feed.
    private var collectionTargetRec: FeedRecommendation? {
        myRec ?? recs.first
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(.top, 80)
            } else if let errorMessage {
                errorState(errorMessage)
            } else if let item {
                VStack(alignment: .leading, spacing: 0) {
                    header(item: item)
                    googlePhotosSection
                    communityPhotosSection
                    recipeSection(item: item)
                    yourTakeSection
                    friendsSection
                    moreByAuthorSection
                    elsewhereSection
                }
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(showsTitle ? (item?.title ?? "") : "")
        .navigationBarTitleDisplayMode(.inline)
        // A drag can drop the keyboard too, so the comment field and its Post
        // button aren't only reachable via the keyboard's own Done button.
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .collection(let rec):
                AddToCollectionView(rec: rec, onDone: {})
            case .edit(let rec):
                EditRexView(
                    rec: rec,
                    onSaved: { Task { await load() } },
                    onDeleted: { Task { await load() } }
                )
            }
        }
        .task { await load() }
        // Needs the item first, for its author.
        .task(id: item?.id) { await loadMoreByAuthor() }
        .task(id: item?.id) {
            if let item { await loadPlaceDetails(item) }
        }
        .task(id: item?.id) {
            if let item { await loadArticles(item) }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let itemTask = RexAPI.shared.fetchItem(id: itemId)
            async let recsTask = RexAPI.shared.fetchRecommendations(forItem: itemId)
            // Best-effort, same reasoning as everywhere else this is
            // fetched — not knowing your want status shouldn't break
            // loading the rest of the page.
            async let wantedTask = RexAPI.shared.isWanted(itemId: itemId)
            let (fetchedItem, fetchedRecs) = try await (itemTask, recsTask)
            item = fetchedItem
            // Nothing from someone on either side of a block.
            recs = RexAPI.shared.filterHidden(fetchedRecs)
            Task { await loadDetails(fetchedItem) }
            wanted = (try? await wantedTask) ?? false
            if let mine = fetchedRecs.first(where: { $0.user_id == RexAPI.shared.currentUserId }) {
                rating = mine.rating
                note = mine.note ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleWant() async {
        isTogglingWant = true
        let next = !wanted
        wanted = next
        do {
            if next {
                try await RexAPI.shared.createWant(itemId: itemId)
            } else {
                try await RexAPI.shared.removeWant(itemId: itemId)
            }
        } catch {
            wanted = !next
        }
        isTogglingWant = false
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await RexAPI.shared.upsertRecommendation(itemId: itemId, rating: rating, note: note)
                recs = try await RexAPI.shared.fetchRecommendations(forItem: itemId)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    @ViewBuilder
    private func header(item: RexItem) -> some View {
        let category = RexCategory(rawType: item.type)
        VStack(alignment: .leading, spacing: 12) {
            // Oct 3 — "rebuild the place page". A place is a photograph
            // first: you decide whether you want to go by looking at it. A
            // book or a film keeps the small cover beside the title, because
            // a portrait cover blown across the width is worse, not better.
            if usesHeroImage(category: category) {
                heroImage(item: item, category: category)

                VStack(alignment: .leading, spacing: 4) {
                    categoryBadge(category)

                    Text(item.title)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(RexColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)

                    if let summary = placeSummary(item: item, category: category) {
                        Text(summary)
                            .font(.system(size: 13))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                    if let address = item.address, !address.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Image(systemName: "mappin").font(.system(size: 10))
                            Text(address).font(.system(size: 11))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(RexColor.mutedForeground)
                    }

                    openingHoursSection
                        .padding(.top, 2)
                }
            } else {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let urlString = item.image_url, let url = URL(string: urlString) {
                        // GoogleSafeAsyncImage, so a Places photo loads and a
                        // chosen Rex drawing ("rex://icon/…") draws.
                        GoogleSafeAsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RexColor.muted
                        }
                    } else {
                        Image(category.placeholderImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .background(RexColor.muted)
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    categoryBadge(category)

                    Text(item.title)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(RexColor.foreground)

                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 13)).foregroundStyle(RexColor.mutedForeground)
                    }
                    if let address = item.address, !address.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin").font(.system(size: 10))
                            Text(address).font(.system(size: 11))
                        }
                        .foregroundStyle(RexColor.mutedForeground)
                    }
                }
            }
            }

            savedByRow

            detailsSection

            HStack(spacing: RexSpacing.md) {
                if !recs.isEmpty {
                    HStack(spacing: 6) {
                        if recs.count == 1 {
                            RexRatingBadge(raw: recs[0].rating)
                        } else {
                            RexRatingAverageBadge(ratings: recs.map { $0.rating })
                        }
                        // The count used to live here too; the row of faces
                        // above now says it, and saying it twice is noise.

                        // Google's own score has been stored on every place
                        // picked from search since the beginning and has
                        // never once been shown. Clearly marked as Google's,
                        // so it can't be mistaken for what friends thought.
                        if let googleRating = item.google_rating, googleRating > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").font(.system(size: 9))
                                Text(String(format: "%.1f", googleRating))
                                    .font(.system(size: 12, weight: .semibold))
                                if let count = item.google_rating_count, count > 0 {
                                    Text("(\(count))").font(.system(size: 11))
                                }
                                Text("Google").font(.system(size: 10))
                            }
                            .foregroundStyle(RexColor.mutedForeground)
                            .padding(.horizontal, RexSpacing.sm)
                            .padding(.vertical, 4)
                            .background(RexColor.badgeBackground)
                            .clipShape(Capsule())
                        }
                    }
                }

                Spacer(minLength: 0)

                if let viewOnMap, category == .place || category == .event {
                    Button {
                        viewOnMap(itemId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "map").font(.system(size: 12))
                            Text("View on map").font(RexFont.text(12, weight: .semibold))
                        }
                        .foregroundStyle(RexColor.primary)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(RexColor.primary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if let link = item.link_url, let url = URL(string: link), url.scheme?.hasPrefix("http") == true {
                    // Opens in Safari. Labelled with the site's own name so
                    // it's clear where you're going. Sept 21 — goes through
                    // RexOutboundLink, which asks for tracking permission the
                    // first time and only then routes it via the affiliate
                    // redirect; a refusal opens the plain link just as fast.
                    RexOutboundLinkButton(url: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 12))
                            Text(category == .other || category == .list ? "View product" : "Visit website")
                                .font(RexFont.text(12, weight: .semibold))
                        }
                        .foregroundStyle(RexColor.primary)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(RexColor.primary, lineWidth: 1))
                    }
                }

                if let collectionTargetRec {
                    Button {
                        activeSheet = .collection(collectionTargetRec)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus").font(.system(size: 12))
                            Text("Save to collection").font(RexFont.text(12, weight: .semibold))
                        }
                        .foregroundStyle(RexColor.primary)
                        .padding(.horizontal, RexSpacing.sm)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(RexColor.primary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    /// Google's details for this place, whichever way they arrived: the
    /// columns cached on the item, or the fetch this visit just made.
    private var effectivePlaceDetails: RexPlaceDetails? {
        if let placeDetails { return placeDetails }
        guard let item else { return nil }
        let cached = RexPlaceDetails(
            summary: item.summary,
            openingHours: item.opening_hours ?? [],
            photoURLs: item.google_photo_urls ?? [],
            rating: item.google_rating,
            ratingCount: item.google_rating_count,
            websiteURL: item.link_url
        )
        return cached.isEmpty ? nil : cached
    }

    /// Fetches Place Details at most once per place, ever — the guard here is
    /// the whole cost control, so it stays strict: a Google place id, nothing
    /// cached, and nobody has asked in the last ninety days.
    private func loadPlaceDetails(_ item: RexItem) async {
        let category = RexCategory(rawType: item.type)
        guard category == .place || category == .event,
              item.external_source == "google_places",
              let placeId = item.external_id, !placeId.isEmpty
        else { return }

        if let fetchedAt = item.details_fetched_at,
           let date = ISO8601DateFormatter.rexDate(from: fetchedAt),
           date.timeIntervalSinceNow > -90 * 24 * 60 * 60 {
            return
        }

        guard let fetched = await RexSearch.placeDetails(placeId: placeId), !fetched.isEmpty else { return }
        placeDetails = fetched
        await RexAPI.shared.saveItemPlaceDetails(itemId: item.id, details: fetched)
    }

    /// Oct 3 — "please can we pull photos from Google?" Google's own photos of
    /// the place, swipeable. Friends' photos keep their own carousel further
    /// down: a picture someone you know took there is worth more than the
    /// listing's, so the two don't get mixed into one undifferentiated reel.
    @ViewBuilder
    private var googlePhotosSection: some View {
        let urls = effectivePlaceDetails?.photoURLs ?? []
        if urls.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(urls.dropFirst(), id: \.self) { urlString in
                            GoogleSafeAsyncImage(url: URL(string: urlString)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RexColor.muted
                            }
                            .frame(width: 150, height: 110)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                Text("Photos from Google")
                    .font(.system(size: 10))
                    .foregroundStyle(RexColor.placeholder)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, RexSpacing.sm)
        }
    }

    /// Opening times. Today's line is the one anybody actually wants, so it's
    /// the one on screen; the rest of the week is a tap away rather than seven
    /// lines of small print on every place page.
    @ViewBuilder
    private var openingHoursSection: some View {
        if let details = effectivePlaceDetails, !details.openingHours.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.snappy) { hoursExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock").font(.system(size: 12))
                        Text(details.todayHours ?? "Opening times")
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Image(systemName: hoursExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(RexColor.foreground.opacity(0.9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if hoursExpanded {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(details.openingHours, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                    .padding(.leading, 18)
                }
            }
        }
    }

    /// A place or an event leads with its photograph; everything else keeps
    /// the cover-beside-the-title layout that suits a portrait cover.
    private func usesHeroImage(category: RexCategory) -> Bool {
        category == .place || category == .event
    }

    private func categoryBadge(_ category: RexCategory) -> some View {
        HStack(spacing: 3) {
            Image(systemName: category.symbol).font(.system(size: 9))
            Text(category.label.uppercased()).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(RexColor.primary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RexColor.primary.opacity(0.12))
        .clipShape(Capsule())
    }

    /// The item's own picture if it has one, otherwise the best photo anybody
    /// has attached to a take on it — which is usually a better photograph of
    /// the place than the catalogue's, because a friend took it there.
    private var heroImageURL: URL? {
        if let urlString = item?.image_url, let url = URL(string: urlString) { return url }
        if let urlString = effectivePlaceDetails?.photoURLs.first, let url = URL(string: urlString) { return url }
        return communityPhotoURLs.first.flatMap(URL.init(string:))
    }

    @ViewBuilder
    private func heroImage(item: RexItem, category: RexCategory) -> some View {
        Group {
            if let url = heroImageURL {
                // GoogleSafeAsyncImage rather than AsyncImage: a Places photo
                // URL needs the bundle-id header, and without it loads as a
                // permanently blank box with no error.
                GoogleSafeAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RexColor.muted
                }
            } else {
                // No photograph anywhere: the drawn placeholder, sized down
                // and centred rather than stretched across the full width,
                // which is how the dino ends up looking like a mistake.
                Image(category.placeholderImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(28)
                    .frame(maxWidth: .infinity)
                    .background(RexColor.muted)
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// One line saying what the thing actually is — the sub-category and the
    /// town. Built from what's already stored rather than fetched: Google's
    /// own one-liner would read better ("smash burgers"), but it's a billed
    /// Place Details call per view, so that's a decision to take separately.
    private func placeSummary(item: RexItem, category: RexCategory) -> String? {
        // Google's own line first when we have it — "smash burgers" beats
        // "Restaurant · Streatham", which is what the fallback below builds.
        if let summary = effectivePlaceDetails?.summary?.trimmingCharacters(in: .whitespaces),
           !summary.isEmpty {
            if let locality = locality(from: item.address) {
                return "\(summary) \u{00B7} \(locality)"
            }
            return summary
        }
        var parts: [String] = []
        if let genre = item.genre?.trimmingCharacters(in: .whitespaces), !genre.isEmpty {
            parts.append(genre)
        }
        if let subtitle = item.subtitle?.trimmingCharacters(in: .whitespaces), !subtitle.isEmpty {
            parts.append(subtitle)
        }
        if let locality = locality(from: item.address) { parts.append(locality) }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// "180 Franciscan Rd, London SW17 8HG, UK" -> "London". Addresses here
    /// are Google-formatted, so the town is the second-to-last component
    /// before the country, with the postcode trimmed off.
    private func locality(from address: String?) -> String? {
        guard let address else { return nil }
        let parts = address.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let candidate = parts[parts.count - 2]
        // Drop a trailing postcode ("London SW17 8HG" -> "London").
        let words = candidate.components(separatedBy: " ")
        let town = words.prefix { word in
            !word.contains(where: \.isNumber)
        }
        let result = town.joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    /// Oct 3 — "a swipeable 'saved by' row of clickable profile pictures;
    /// how many people have Rex'd it". The faces were buried under the takes
    /// at the bottom of the page; who has been is the fastest answer to
    /// "should I go", so it moves up to sit under the title.
    /// Whoever Rex'd it first, then everyone since. `recs` comes back
    /// newest-first from fetchRecommendations(forItem:), and the person who
    /// found a place before anyone else is the one worth leading with.
    private var orderedRexers: [FeedRecommendation] {
        recs.reversed()
    }

    @ViewBuilder
    private var savedByRow: some View {
        if !recs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(recs.count == 1 ? "Rex\u{2019}d by" : "Rex\u{2019}d by \(recs.count) people")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(RexColor.mutedForeground)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.md) {
                        // Oct 3 — "the first person to Rex something should
                        // have a little number one next to it and on the left
                        // of the thumbnails of profile pictures so that there
                        // is an incentive to be the 1st to Rex something."
                        //
                        // `recs` arrives newest-first, so the first to Rex it
                        // is the last row; drawn first here, with the badge.
                        ForEach(orderedRexers) { rec in
                            let name = rec.profiles?.display_name ?? rec.profiles?.username ?? "Someone"
                            let isFirst = rec.id == recs.last?.id && recs.count > 1
                            NavigationLink(value: UserProfileRoute(userId: rec.user_id, name: name)) {
                                VStack(spacing: 4) {
                                    UserAvatarView(url: rec.profiles?.avatar_url, name: name, size: 44)
                                        .overlay(alignment: .topLeading) {
                                            if isFirst {
                                                Text("1")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(RexColor.primaryForeground)
                                                    .frame(width: 17, height: 17)
                                                    .background(RexColor.primary, in: Circle())
                                                    .overlay(Circle().stroke(RexColor.background, lineWidth: 1.5))
                                                    .offset(x: -3, y: -3)
                                            }
                                        }
                                    Text(name.components(separatedBy: " ").first ?? name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(RexColor.mutedForeground)
                                        .lineLimit(1)
                                }
                                .frame(width: 58)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.bottom, 2)
                }
            }
        }
    }

    /// #121 — every photo anyone's attached to a take on this item, pooled
    /// into one swipeable carousel. Most-recent-take-first, since `recs`
    /// already comes back ordered that way (fetchRecommendations(forItem:)).
    /// A single Rex's own photos already get this treatment on its card
    /// (RecommendationCardView's PhotoCarouselView) — this is the same
    /// component, just fed everyone's photos on this item at once rather
    /// than one person's.
    private var communityPhotoURLs: [String] {
        recs.flatMap { $0.photo_urls ?? ($0.photo_url.map { [$0] } ?? []) }
    }

    @ViewBuilder
    private var communityPhotosSection: some View {
        if !communityPhotoURLs.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                Text("Photos from friends")
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.horizontal, 16)
                PhotoCarouselView(urls: communityPhotoURLs, cornerRadius: RexRadius.card)
                    .padding(.horizontal, 16)
            }
            .padding(.top, RexSpacing.sm)
        }
    }

    // #126 — recipe_text saved correctly on post; this is the other half
    // of the fix, actually showing it. Reuses RecipeEditorView's own
    // Ingredients/Method splitter so a pasted or photo-auto-populated
    // recipe reads back the same shape it was reviewed in before posting.
    @ViewBuilder
    private func recipeSection(item: RexItem) -> some View {
        if let text = item.recipe_text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = RexRecipe.parse(text)
            VStack(alignment: .leading, spacing: 12) {
                if !parsed.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ingredients")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(RexColor.foreground)
                        ForEach(parsed.ingredients, id: \.self) { line in
                            Text("\u{2022} \(line)")
                                .font(.system(size: 13))
                                .foregroundStyle(RexColor.foreground)
                        }
                    }
                }
                if !parsed.method.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Method")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(RexColor.foreground)
                        ForEach(Array(parsed.method.enumerated()), id: \.offset) { index, line in
                            Text("\(index + 1). \(line)")
                                .font(.system(size: 13))
                                .foregroundStyle(RexColor.foreground)
                        }
                    }
                }
                // A recipe that didn't parse into recognizable sections —
                // pasted as one freeform block — still deserves to show up
                // rather than silently vanishing.
                if parsed.ingredients.isEmpty && parsed.method.isEmpty {
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(RexColor.foreground)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RexColor.card)
        }
    }

    private var yourTakeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(myRec != nil ? "Update your take" : "Your take")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(RexColor.foreground)
                Spacer()
                // "Still not able to update location within a card when
                // looking from a collection" — this screen only ever had
                // the inline rating/note above, never the full edit sheet
                // (title/address/subcategories/etc.) every other card
                // context (Feed, Profile, Trip, List) already opens via its
                // own "Edit" — a card reached through Collections lands
                // here with no way to get to it at all.
                if let myRec {
                    Button {
                        activeSheet = .edit(myRec)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil").font(.system(size: 11))
                            Text("Edit details").font(RexFont.text(12, weight: .semibold))
                        }
                        .foregroundStyle(RexColor.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Independent of the rating below — a want is its own row, not
            // a step toward posting one. Lets you flag/unflag "want to try"
            // right here instead of only ever being reachable from the
            // feed card's own bookmark icon.
            Button {
                Task { await toggleWant() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: wanted ? "bookmark.fill" : "bookmark")
                    Text(wanted ? "On your want-to-try list" : "Want to try")
                }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(wanted ? RexColor.primary : RexColor.mutedForeground)
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, 8)
                .background(wanted ? RexColor.badgeBackground : RexColor.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(RexColor.border, lineWidth: wanted ? 0 : 1))
            }
            .buttonStyle(.plain)
            .disabled(isTogglingWant)

            RexRatingPicker(value: $rating)

            TextField("What did you love about it?", text: $note, axis: .vertical)
                .lineLimit(3...5)
                .padding(12)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))

            Button(action: save) {
                if isSaving {
                    ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                } else {
                    Text(myRec != nil ? "Update" : "Post").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 46)
            .background(RexColor.primary)
            .foregroundStyle(RexColor.primaryForeground)
            .clipShape(Capsule())
            .disabled(isSaving)
        }
        .padding(16)
    }

    /// More by the same author, Goodreads-style — covers you can run your eye
    /// along rather than a list to read.
    ///
    /// The whole bibliography comes from OpenLibrary, so it includes books
    /// nobody here has touched; what makes it REX's rather than a catalogue is
    /// the count underneath. "2 Rex" means someone you know has read it and
    /// the cover is a door; no count means it's just a book that exists, and
    /// tapping offers to add it rather than opening a page that isn't there.
    @ViewBuilder
    private var moreByAuthorSection: some View {
        if RexCategory(rawType: item?.type) == .book, !moreByAuthor.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("More by \(primaryAuthor ?? "this author")")
                        .font(RexFont.display(18, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                    Spacer(minLength: RexSpacing.sm)
                    if let author = primaryAuthor {
                        NavigationLink(value: AuthorRoute(author: author)) {
                            Text("See all")
                                .font(RexFont.text(13, weight: .semibold))
                                .foregroundStyle(RexColor.primary)
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: RexSpacing.md) {
                        ForEach(moreByAuthor) { book in
                            authorBookTile(book)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, RexSpacing.lg)
        }
    }

    private func authorBookTile(_ book: RexSearchHit) -> some View {
        let existing = authorBookItems[book.title.lowercased()]
        let count = existing.flatMap { authorBookRexCounts[$0.id] } ?? 0

        return Group {
            if let existing {
                NavigationLink(value: existing.id) { authorBookCard(book, rexCount: count) }
                    .buttonStyle(.plain)
            } else {
                authorBookCard(book, rexCount: 0)
            }
        }
    }

    private func authorBookCard(_ book: RexSearchHit, rexCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(RexColor.muted)
                if let cover = book.imageURL, let url = URL(string: cover) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "book").foregroundStyle(RexColor.mutedForeground)
                    }
                } else {
                    Image(systemName: "book").foregroundStyle(RexColor.mutedForeground)
                }
            }
            .frame(width: 92, height: 138)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(book.title)
                .font(RexFont.text(12.5, weight: .medium))
                .foregroundStyle(RexColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if rexCount > 0 {
                HStack(spacing: 3) {
                    Image("RexDinoLogo")
                        .resizable().scaledToFit().frame(width: 12, height: 12)
                    Text("\(rexCount) Rex")
                        .font(RexFont.text(11, weight: .medium))
                        .foregroundStyle(RexColor.primary)
                }
            } else {
                Text("Not Rex'd yet")
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        }
        .frame(width: 92, alignment: .leading)
    }

    /// A book's subtitle is its author list as OpenLibrary returned it; the
    /// first name is the one worth building a shelf around.
    private var primaryAuthor: String? {
        guard let subtitle = item?.subtitle, !subtitle.isEmpty else { return nil }
        return subtitle
            .components(separatedBy: " \u{00B7} ").first?
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces)
    }

    private func loadMoreByAuthor() async {
        guard RexCategory(rawType: item?.type) == .book,
              let author = primaryAuthor, !author.isEmpty else { return }

        async let catalogueTask = RexSearch.byAuthor(author)
        async let mineTask = RexAPI.shared.fetchBooksByAuthor(author)
        let catalogue = (try? await catalogueTask) ?? []
        let mine = (try? await mineTask) ?? []

        // The book you are already looking at doesn't belong on its own shelf.
        let currentTitle = (item?.title ?? "").lowercased()
        moreByAuthor = catalogue.filter { $0.title.lowercased() != currentTitle }.prefix(12).map { $0 }

        authorBookItems = Dictionary(
            mine.map { ($0.title.lowercased(), $0) },
            uniquingKeysWith: { a, _ in a }
        )
        authorBookRexCounts = (try? await RexAPI.shared.fetchRexCounts(itemIds: mine.map(\.id))) ?? [:]
    }

    /// Public Google rating, deliberately after "What friends say" — friends
    /// lead, the crowd is secondary. Sept 29: the rating card is now a way
    /// through to the Google listing rather than a dead end, and everything
    /// that isn't a place gets the nearest equivalent.
    @ViewBuilder
    private var elsewhereSection: some View {
        let link = RexExternalLink.forItem(item)
        let rating = item?.google_rating ?? 0

        if rating > 0 || link != nil {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if rating > 0 {
                    Text("On Google")
                        .font(RexFont.text(13, weight: .semibold))
                        .foregroundStyle(RexColor.mutedForeground)
                }

                if let link {
                    RexOutboundLinkButton(url: link.url) {
                        elsewhereCard(rating: rating, link: link)
                    }
                } else {
                    elsewhereCard(rating: rating, link: nil)
                }
                articlesSection
            }
            .padding(.top, RexSpacing.lg)
        } else {
            articlesSection.padding(.top, RexSpacing.lg)
        }
    }

    /// Oct 3 — "can the same be done with other articles from popular news
    /// sources if they feature?" Sits directly under "On Google" and reads the
    /// same way: somewhere else this has been written about, and the way
    /// through to it.
    @ViewBuilder
    private var articlesSection: some View {
        if !articles.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                Text("Written about")
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.top, RexSpacing.sm)

                ForEach(articles) { article in
                    RexOutboundLinkButton(url: URL(string: article.url)!) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(article.publication.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(RexColor.primary)
                            Text(article.headline)
                                .font(RexFont.text(14, weight: .medium))
                                .foregroundStyle(RexColor.foreground)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            if let snippet = article.snippet, !snippet.isEmpty {
                                Text(snippet)
                                    .font(RexFont.text(12))
                                    .foregroundStyle(RexColor.mutedForeground)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(RexSpacing.md)
                        .rexCard()
                    }
                }
            }
        }
    }

    /// Only for places and events, and only once — a web search per item page
    /// view would be both slow and pointless, since the answer barely changes.
    private func loadArticles(_ item: RexItem) async {
        let category = RexCategory(rawType: item.type)
        guard category == .place || category == .event, articles.isEmpty else { return }
        articles = await RexSearch.articles(
            about: item.title,
            near: locality(from: item.address)
        )
    }

    /// One card whether or not there's a rating to put in it: a place with a
    /// Google score shows the score and the way through, a book shows only the
    /// way through, and both read as the same component.
    @ViewBuilder
    private func elsewhereCard(rating: Double, link: RexExternalLink.Destination?) -> some View {
        HStack(spacing: RexSpacing.sm) {
            if rating > 0 {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(RexColor.accent)
                Text(String(format: "%.1f", rating))
                    .font(RexFont.text(15, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                if let count = item?.google_rating_count, count > 0 {
                    Text("· \(count) reviews")
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            } else if let link {
                Image(systemName: link.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(RexColor.mutedForeground)
                Text(link.label)
                    .font(RexFont.text(15, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
            }

            Spacer(minLength: RexSpacing.sm)

            // Only where there's somewhere to go. A rating with no link keeps
            // the card but loses the affordance, rather than promising a tap
            // that does nothing.
            if link != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        }
        .padding(RexSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .rexCard()
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(RexColor.border)

            Text("What friends say")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(RexColor.foreground)
                .padding(.top, 6)

            if recs.isEmpty {
                Text("No takes yet.").font(.system(size: 14)).foregroundStyle(RexColor.mutedForeground)
            }

            ForEach(recs) { rec in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        // Whoever said it is as interesting as what they said.
                        NavigationLink(value: UserProfileRoute(
                            userId: rec.user_id,
                            name: rec.profiles?.display_name ?? rec.profiles?.username ?? "Someone"
                        )) {
                            HStack(spacing: 6) {
                                UserAvatarView(
                                    url: rec.profiles?.avatar_url,
                                    name: rec.profiles?.display_name ?? rec.profiles?.username ?? "?",
                                    size: 24
                                )

                                Text(rec.profiles?.display_name ?? rec.profiles?.username ?? "Someone")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(RexColor.foreground)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        RexRatingBadge(raw: rec.rating)
                    }
                    if let note = rec.note, !note.isEmpty {
                        Text("\u{201C}\(note)\u{201D}").font(.system(size: 13)).foregroundStyle(RexColor.foreground.opacity(0.9))
                    }

                    Rectangle().fill(RexColor.divider).frame(height: 1).padding(.vertical, 4)
                    LikesCommentsView(recommendationId: rec.id)
                }
                .padding(12)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(RexColor.border, lineWidth: 1))
            }
        }
        .padding(16)
    }

    /// What the thing actually is, before what your friends made of it:
    /// the ratings strip, then the synopsis. Only films, TV and books have
    /// one; everything else skips it entirely.
    @ViewBuilder
    private var detailsSection: some View {
        if isLoadingDetails, details == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Looking it up\u{2026}").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
            }
        } else if let details, !details.isEmpty {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                if !details.ratings.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: RexSpacing.sm) {
                            ForEach(details.ratings, id: \.source) { rating in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(rating.source.uppercased())
                                        .font(.system(size: 9, weight: .semibold))
                                        .tracking(0.4)
                                        .foregroundStyle(RexColor.mutedForeground)
                                    Text(rating.value)
                                        .font(RexFont.display(16, weight: .semibold))
                                        .foregroundStyle(RexColor.foreground)
                                    if let detail = rating.detail {
                                        Text(detail)
                                            .font(RexFont.text(10))
                                            .foregroundStyle(RexColor.mutedForeground)
                                    }
                                }
                                .padding(.horizontal, RexSpacing.md)
                                .padding(.vertical, RexSpacing.sm)
                                .background(RexColor.card)
                                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                        .stroke(RexColor.border, lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }

                if details.facts != nil || details.certificate != nil {
                    HStack(spacing: RexSpacing.sm) {
                        // Oct 4 — the certificate, where TMDB has it for the UK.
                        if let certificate = details.certificate {
                            Text(certificate)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(RexColor.mutedForeground)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(RexColor.mutedForeground.opacity(0.6), lineWidth: 1)
                                )
                        }
                        if let facts = details.facts {
                            Text(facts).font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                }

                // Oct 4 — "can we do the same thing we did for places with
                // films and TV? Ie cast and length." Same shape as the
                // place page's row of who Rex'd it, deliberately: a row of
                // faces is how you recognise a film, and the two pages
                // should feel like the same app.
                if !details.cast.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cast")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.3)
                            .foregroundStyle(RexColor.mutedForeground)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: RexSpacing.md) {
                                ForEach(details.cast) { member in
                                    VStack(spacing: 4) {
                                        AsyncImage(url: member.imageURL.flatMap(URL.init(string:))) { phase in
                                            if let image = phase.image {
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } else {
                                                RexColor.muted.overlay(
                                                    Image(systemName: "person.fill")
                                                        .font(.system(size: 16))
                                                        .foregroundStyle(RexColor.placeholder)
                                                )
                                            }
                                        }
                                        .frame(width: 54, height: 54)
                                        .clipShape(Circle())
                                        Text(member.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(RexColor.foreground)
                                            .lineLimit(1)
                                        if let role = member.role {
                                            Text(role)
                                                .font(.system(size: 10))
                                                .foregroundStyle(RexColor.mutedForeground)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(width: 68)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }
                    .padding(.top, RexSpacing.xs)
                }

                if let synopsis = details.synopsis {
                    Text(synopsis)
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.foreground.opacity(0.9))
                        .lineLimit(synopsisExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    if !synopsisExpanded, synopsis.count > 220 {
                        Button("Read more") { withAnimation(.snappy) { synopsisExpanded = true } }
                            .font(RexFont.text(12, weight: .semibold))
                            .foregroundStyle(RexColor.primary)
                    }
                    // Whose description this is, so the numbers above aren't
                    // mistaken for Rex's own.
                    Text("From \(details.ratings.first?.source ?? "the catalogue")")
                        .font(RexFont.text(10))
                        .foregroundStyle(RexColor.placeholder)
                }
            }
            .padding(.top, RexSpacing.xs)
        }
    }

    private func loadDetails(_ item: RexItem) async {
        let category = RexCategory(rawType: item.type)
        guard category == .movie || category == .tv || category == .book, details == nil else { return }
        isLoadingDetails = true
        let reference = await RexAPI.shared.fetchItemExternalRef(itemId: item.id)
        let fetched = await RexSearch.details(
            type: category, externalId: reference.id, externalSource: reference.source,
            title: item.title, subtitle: item.subtitle
        )
        details = fetched
        isLoadingDetails = false
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(.footnote).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.footnote.weight(.semibold)).foregroundStyle(RexColor.primary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

// The ten-crown picker moved to RexRatingScale.swift as RexRatingPicker,
// which is the five-tier scale (Do not Rex / Meh / Rex / Loved / Obsessed).

/// Sept 29 — "Google reviews — import or link through to the Google page.
/// For non-places, use the best thing e.g. Rotten Tomatoes for Films and TV,
/// Goodreads for books (if this is possible)".
///
/// Linking, not importing — and the "if this is possible" is the honest
/// part of the answer. Rotten Tomatoes licenses its scores through Fandango
/// and Goodreads closed its API in 2020, so neither score can legitimately be
/// read and shown as a number. What can be done is land someone on the right
/// page in one tap. Google is the exception: its rating is already stored on
/// the item, so that card shows a real figure and now has the link behind it.
enum RexExternalLink {
    struct Destination {
        let label: String
        let symbol: String
        let url: URL
    }

    static func forItem(_ item: RexItem?) -> Destination? {
        guard let item else { return nil }
        let query = [item.title, item.subtitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        switch RexCategory(rawValue: item.type) {
        case .place, .event:
            // A place found through Google keeps its place id, which opens the
            // real listing. Anything typed by hand falls back to a search for
            // the name and address — not guaranteed, but it lands right far
            // more often than it doesn't.
            if item.external_source == "google_places", let id = item.external_id, !id.isEmpty {
                return make("https://www.google.com/maps/search/?api=1&query=\(esc(item.title))&query_place_id=\(esc(id))",
                            "See on Google Maps", "mappin.and.ellipse")
            }
            let place = [item.title, item.address].compactMap { $0 }.joined(separator: " ")
            return make("https://www.google.com/maps/search/?api=1&query=\(esc(place))",
                        "See on Google Maps", "mappin.and.ellipse")

        case .movie, .tv:
            return make("https://www.rottentomatoes.com/search?search=\(esc(item.title))",
                        "See on Rotten Tomatoes", "film")

        case .book:
            return make("https://www.goodreads.com/search?q=\(esc(query))",
                        "See on Goodreads", "books.vertical")

        case .podcast:
            return make("https://podcasts.apple.com/search?term=\(esc(item.title))",
                        "See on Apple Podcasts", "mic")

        default:
            // Recipes, trips and the catch-all have no one obvious home to
            // send anyone to, so they get no link rather than a bad guess.
            return nil
        }
    }

    private static func make(_ string: String, _ label: String, _ symbol: String) -> Destination? {
        URL(string: string).map { Destination(label: label, symbol: symbol, url: $0) }
    }

    private static func esc(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }
}
