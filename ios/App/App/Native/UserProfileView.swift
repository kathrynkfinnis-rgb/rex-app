import SwiftUI

/// Route to someone else's profile. Carries the name so the screen has a
/// title before the fetch lands.
struct UserProfileRoute: Hashable {
    let userId: String
    let name: String
}

/// Someone else's profile: who they are, what they've Rex'd, filterable by
/// category — the read-only counterpart to ProfileView.
struct UserProfileView: View {
    let route: UserProfileRoute

    @State private var profile: RexProfileDetail?
    @State private var recommendations: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var filter: RexCategory?

    private var availableCategories: [RexCategory] {
        let present = Set(recommendations.compactMap { RexCategory(rawType: $0.items?.type) })
        return rexAllCategories.filter { present.contains($0) }
    }

    private var visible: [FeedRecommendation] {
        guard let filter else { return recommendations }
        return recommendations.filter { RexCategory(rawType: $0.items?.type) == filter }
    }

    private var averageRating: Double? {
        let rated = recommendations.filter { $0.rating > 0 }
        guard !rated.isEmpty else { return nil }
        return rated.reduce(0) { $0 + $1.rating } / Double(rated.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                header

                if !availableCategories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: RexSpacing.sm) {
                            chip("All", active: filter == nil) { filter = nil }
                            ForEach(availableCategories, id: \.self) { c in
                                chip(c.label, active: filter == c) {
                                    filter = (filter == c) ? nil : c
                                }
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: RexRadius.card)
                            .fill(RexColor.muted)
                            .frame(height: 120)
                    }
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if visible.isEmpty {
                    Text(recommendations.isEmpty ? "Nothing Rex'd yet." : "Nothing in this category.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, RexSpacing.xxl)
                } else {
                    LazyVStack(spacing: RexSpacing.betweenCards) {
                        ForEach(visible) { rec in
                            if RexCategory(rawType: rec.items?.type) == .trip {
                                NavigationLink(value: TripRoute(
                                    recommendationId: rec.id,
                                    title: rec.items?.title ?? "Trip",
                                )) {
                                    RecommendationCardView(rec: rec)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(value: rec.item_id) {
                                    RecommendationCardView(rec: rec)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.bottom, RexSpacing.xxxl)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(profile?.display_name ?? route.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: RexSpacing.lg) {
            UserAvatarView(
                url: profile?.avatar_url,
                name: profile?.display_name ?? route.name,
                size: 64
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.display_name ?? route.name)
                    .font(RexFont.display(22, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                if let username = profile?.username {
                    Text("@\(username)")
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                }
                HStack(spacing: RexSpacing.md) {
                    Text("\(recommendations.count) Rex")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                    if let averageRating {
                        HStack(spacing: 3) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(RexColor.primary)
                            Text("avg \(String(format: "%.1f", averageRating))")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                }
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(.top, RexSpacing.sm)
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RexFont.text(13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? RexColor.primaryForeground : RexColor.mutedForeground)
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, 7)
                .background(active ? RexColor.primary : RexColor.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? RexColor.primary : RexColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let profileTask = RexAPI.shared.fetchProfiles(ids: [route.userId])
            async let recsTask = RexAPI.shared.fetchRecommendations(forUser: route.userId)
            let (profiles, recs) = try await (profileTask, recsTask)
            profile = profiles.first
            recommendations = recs
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(RexFont.text(13)).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}
