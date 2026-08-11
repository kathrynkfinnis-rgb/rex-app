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

    private var myRec: FeedRecommendation? {
        recs.first { $0.user_id == RexAPI.shared.currentUserId }
    }

    private var averageRating: Double {
        guard !recs.isEmpty else { return 0 }
        return recs.reduce(0) { $0 + $1.rating } / Double(recs.count)
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
                    yourTakeSection
                    friendsSection
                    googleSection
                }
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(item?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let itemTask = RexAPI.shared.fetchItem(id: itemId)
            async let recsTask = RexAPI.shared.fetchRecommendations(forItem: itemId)
            let (fetchedItem, fetchedRecs) = try await (itemTask, recsTask)
            item = fetchedItem
            recs = fetchedRecs
            if let mine = fetchedRecs.first(where: { $0.user_id == RexAPI.shared.currentUserId }) {
                rating = mine.rating
                note = mine.note ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
                        RexColor.muted.overlay(Image(systemName: category.symbol).foregroundStyle(RexColor.mutedForeground))
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

            if !recs.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill").foregroundStyle(RexColor.primary)
                    Text(String(format: "%.1f", averageRating)).font(.system(size: 15, weight: .semibold))
                    Text("/10").foregroundStyle(RexColor.mutedForeground).font(.system(size: 13))
                    Text("· \(recs.count) Rex\(recs.count == 1 ? "" : "es")")
                        .font(.system(size: 13)).foregroundStyle(RexColor.mutedForeground)
                }
            }
        }
        .padding(16)
    }

    private var yourTakeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(myRec != nil ? "Update your take" : "Your take")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(RexColor.foreground)

            CrownRatingInput(value: $rating)

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
                        Spacer()
                        HStack(spacing: 2) {
                            Image(systemName: "crown.fill").font(.system(size: 11)).foregroundStyle(RexColor.primary)
                            Text(String(format: rec.rating.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", rec.rating))
                                .fontWeight(.semibold)
                            Text("/10").foregroundStyle(RexColor.mutedForeground)
                        }
                        .font(.system(size: 13))
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

struct CrownRatingInput: View {
    @Binding var value: Double
    /// Allow 0 ("not rated") by tapping the crown that's already selected.
    var clearable: Bool = false

    var body: some View {
        HStack(spacing: RexSpacing.xs) {
            ForEach(1...10, id: \.self) { i in
                Image(systemName: Double(i) <= value ? "crown.fill" : "crown")
                    .font(.system(size: 18))
                    .foregroundStyle(Double(i) <= value ? RexColor.primary : RexColor.border)
                    .onTapGesture {
                        value = (clearable && value == Double(i)) ? 0 : Double(i)
                    }
            }
            if clearable && value == 0 {
                Text("Not rated")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.leading, RexSpacing.xs)
            }
        }
    }
}
