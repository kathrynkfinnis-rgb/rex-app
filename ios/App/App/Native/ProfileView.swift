import SwiftUI

/// Own profile: header + all-time stats + own Rex, filterable by category.
/// Folds in the backlog request for profile-page filtering (task #20), built as a single
/// scrollable row of chips rather than a dropdown — same pattern requested for the feed's
/// filters (task #17), so this establishes the look we'll reuse there later.
struct ProfileView: View {
    @State private var profile: RexProfileDetail?
    @State private var recommendations: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedFilter: RexCategory?

    private var availableCategories: [RexCategory] {
        let present = Set(recommendations.compactMap { RexCategory(rawValue: $0.items?.type ?? "") })
        return [.place, .trip, .book, .movie, .tv, .podcast, .recipe, .event, .other].filter { present.contains($0) }
    }

    private var filteredRecommendations: [FeedRecommendation] {
        guard let selectedFilter else { return recommendations }
        return recommendations.filter { $0.items?.type == selectedFilter.rawValue }
    }

    private var averageRating: Double? {
        guard !recommendations.isEmpty else { return nil }
        return recommendations.reduce(0) { $0 + $1.rating } / Double(recommendations.count)
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(.top, 80)
            } else if let errorMessage {
                errorState(errorMessage)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if !availableCategories.isEmpty {
                        filterRow
                    }
                    recList
                }
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(profile?.display_name ?? profile?.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let profileTask = RexAPI.shared.fetchMyProfile()
            let fetchedProfile = try await profileTask
            profile = fetchedProfile
            recommendations = try await RexAPI.shared.fetchRecommendations(forUser: fetchedProfile.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(RexColor.primary)
                Text(String((profile?.display_name ?? profile?.username ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(RexColor.primaryForeground)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.display_name ?? profile?.username ?? "")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(RexColor.foreground)
                if let username = profile?.username {
                    Text("@\(username)").font(.system(size: 13)).foregroundStyle(RexColor.mutedForeground)
                }
                HStack(spacing: 10) {
                    Text("\(recommendations.count) Rex").font(.system(size: 12)).foregroundStyle(RexColor.mutedForeground)
                    if let averageRating {
                        HStack(spacing: 2) {
                            Image(systemName: "crown.fill").font(.system(size: 10)).foregroundStyle(RexColor.primary)
                            Text("avg \(String(format: "%.1f", averageRating))").font(.system(size: 12)).foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                }
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(16)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", isSelected: selectedFilter == nil) { selectedFilter = nil }
                ForEach(availableCategories, id: \.self) { cat in
                    filterChip(cat.label, isSelected: selectedFilter == cat) { selectedFilter = cat }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(isSelected ? RexColor.primary : RexColor.card)
                .foregroundStyle(isSelected ? RexColor.primaryForeground : RexColor.foreground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(RexColor.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var recList: some View {
        if filteredRecommendations.isEmpty {
            Text("Nothing posted yet.")
                .font(.system(size: 14))
                .foregroundStyle(RexColor.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            VStack(spacing: 10) {
                ForEach(filteredRecommendations) { rec in
                    NavigationLink(value: rec.item_id) {
                        RecommendationCardView(rec: rec)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
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
