import SwiftUI

/// Own profile: header + all-time stats + own Rex, filterable by category.
/// Folds in the backlog request for profile-page filtering (task #20), built as a single
/// scrollable row of chips rather than a dropdown — same pattern requested for the feed's
/// filters (task #17), so this establishes the look we'll reuse there later.
struct ProfileView: View {
    /// Optional so the tab-bar Profile can own sign-out while other entry
    /// points (e.g. the feed toolbar) just view the profile.
    var onSignedOut: (() -> Void)? = nil

    @State private var profile: RexProfileDetail?
    @State private var recommendations: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedFilter: RexCategory?
    @State private var editing: FeedRecommendation?
    @State private var selecting = false
    @State private var selectedIds: Set<String> = []
    @State private var confirmBulkDelete = false
    @State private var isDeleting = false
    @State private var editingProfile = false

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
                    if let onSignedOut {
                        logOutButton(onSignedOut)
                    }
                }
            }
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle(profile?.display_name ?? profile?.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !recommendations.isEmpty {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        selectedIds.removeAll()
                    }
                    .font(RexFont.text(14, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && !selectedIds.isEmpty {
                Button {
                    confirmBulkDelete = true
                } label: {
                    if isDeleting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Delete \(selectedIds.count) Rex")
                    }
                }
                .font(RexFont.text(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RexColor.destructive)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.button, style: .continuous))
                .padding(.horizontal, RexSpacing.page)
                .padding(.bottom, RexSpacing.sm)
                .disabled(isDeleting)
            }
        }
        .alert("Delete \(selectedIds.count) Rex?", isPresented: $confirmBulkDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await bulkDelete() } }
        } message: {
            Text("This can't be undone.")
        }
        .task { await load() }
        .sheet(isPresented: $editingProfile) {
            EditProfileView(profile: profile, onSaved: { Task { await load() } })
        }
        .sheet(item: $editing) { rec in
            EditRexView(
                rec: rec,
                onSaved: { Task { await load() } },
                onDeleted: { Task { await load() } }
            )
        }
    }

    private func bulkDelete() async {
        isDeleting = true
        // Sequential rather than parallel — a handful of deletes, and this
        // keeps the error case simple if one fails partway.
        for id in selectedIds {
            try? await RexAPI.shared.deleteRecommendation(id: id)
        }
        selectedIds.removeAll()
        selecting = false
        isDeleting = false
        await load()
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
            UserAvatarView(
                url: profile?.avatar_url,
                name: profile?.display_name ?? profile?.username ?? "?",
                size: 64
            )

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
            Button {
                editingProfile = true
            } label: {
                Text("Edit")
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.primary)
                    .padding(.horizontal, RexSpacing.md)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(RexColor.primary, lineWidth: 1))
            }
            .buttonStyle(.plain)
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
            VStack(spacing: RexSpacing.betweenCards) {
                ForEach(filteredRecommendations) { rec in
                    Group {
                        if selecting {
                            Button {
                                if selectedIds.contains(rec.id) { selectedIds.remove(rec.id) }
                                else { selectedIds.insert(rec.id) }
                            } label: {
                                RecommendationCardView(rec: rec)
                                    .overlay(alignment: .topLeading) {
                                        Image(systemName: selectedIds.contains(rec.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 22))
                                            .foregroundStyle(selectedIds.contains(rec.id) ? RexColor.primary : RexColor.border)
                                            .background(Circle().fill(RexColor.card).padding(2))
                                            .padding(10)
                                    }
                                    .opacity(selectedIds.contains(rec.id) ? 1 : 0.75)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: rec.item_id) {
                                RecommendationCardView(rec: rec)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // These are all your own Rex, so every one is editable.
                    .contextMenu {
                        Button {
                            editing = rec
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            editing = rec
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(RexColor.mutedForeground)
                                .padding(7)
                                .background(RexColor.card)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(RexColor.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
        }
    }

    /// Log out lives at the bottom of Profile rather than eating space in the
    /// feed's top bar.
    private func logOutButton(_ signOut: @escaping () -> Void) -> some View {
        Button {
            RexAPI.shared.signOut()
            signOut()
        } label: {
            Text("Log out")
        }
        .buttonStyle(RexSecondaryButtonStyle())
        .padding(.horizontal, RexSpacing.page)
        .padding(.top, RexSpacing.sm)
        .padding(.bottom, RexSpacing.xxl)
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
