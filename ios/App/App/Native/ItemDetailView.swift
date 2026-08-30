import SwiftUI

struct ItemDetailView: View {
    let itemId: String

    @State private var item: RexItem?
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
    @State private var addingToCollection: FeedRecommendation?
    /// "View on map function via a button" — the feed/profile cards
    /// already had one (#133), the full item page never did.
    @Environment(\.viewOnMap) private var viewOnMap
    @State private var editingRec: FeedRecommendation?

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
                    communityPhotosSection
                    recipeSection(item: item)
                    yourTakeSection
                    friendsSection
                    googleSection
                }
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(item?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // A drag can drop the keyboard too, so the comment field and its Post
        // button aren't only reachable via the keyboard's own Done button.
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $addingToCollection) { rec in
            AddToCollectionView(rec: rec, onDone: {})
        }
        .sheet(item: $editingRec) { rec in
            EditRexView(
                rec: rec,
                onSaved: { Task { await load() } },
                onDeleted: { Task { await load() } }
            )
        }
        .task { await load() }
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
            recs = fetchedRecs
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
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let urlString = item.image_url, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                RexColor.muted
                            }
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
                    HStack(spacing: 3) {
                        Image(systemName: category.symbol).font(.system(size: 9))
                        Text(category.label.uppercased()).font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(RexColor.primary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RexColor.primary.opacity(0.12))
                    .clipShape(Capsule())

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

            HStack(spacing: RexSpacing.md) {
                if !recs.isEmpty {
                    HStack(spacing: 6) {
                        if recs.count == 1 {
                            RexRatingBadge(raw: recs[0].rating)
                        } else {
                            RexRatingAverageBadge(ratings: recs.map { $0.rating })
                        }
                        Text("· \(recs.count) Rex\(recs.count == 1 ? "" : "es")")
                            .font(.system(size: 13)).foregroundStyle(RexColor.mutedForeground)
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

                if let collectionTargetRec {
                    Button {
                        addingToCollection = collectionTargetRec
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
                PhotoCarouselView(urls: communityPhotoURLs, height: 280, cornerRadius: RexRadius.card)
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
                        editingRec = myRec
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

    /// Public Google rating, deliberately after "What friends say" — friends
    /// lead, the crowd is secondary.
    @ViewBuilder
    private var googleSection: some View {
        if let rating = item?.google_rating, rating > 0 {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                Text("On Google")
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
                HStack(spacing: RexSpacing.sm) {
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
                }
                .padding(RexSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rexCard()
            }
            .padding(.top, RexSpacing.lg)
        }
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
