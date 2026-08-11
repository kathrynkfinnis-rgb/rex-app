import SwiftUI

struct NotificationsRoute: Hashable {}
struct ProfileRoute: Hashable {}

struct FeedView: View {
    var onSignedOut: () -> Void
    /// Incremented by the tab bar when Feed is tapped while already active.
    var popToRootSignal: Int = 0

    @State private var path = NavigationPath()

    @State private var recommendations: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingAddRex = false
    @State private var filter: RexCategory?
    @State private var subFilter: String?
    @State private var query = ""

    /// Categories that actually appear in the feed, so we don't show filters
    /// that would return nothing.
    private var availableCategories: [RexCategory] {
        let present = Set(recommendations.compactMap { RexCategory(rawType: $0.items?.type) })
        return rexAllCategories.filter { present.contains($0) }
    }

    /// Subcategories (genres) within the selected category, mirroring the web.
    private var availableSubcategories: [String] {
        guard let filter else { return [] }
        var set = Set<String>()
        for rec in recommendations where RexCategory(rawType: rec.items?.type) == filter {
            for genre in splitGenres(rec.items?.genre) { set.insert(genre) }
        }
        return set.sorted()
    }

    private var visible: [FeedRecommendation] {
        recommendations.filter { rec in
            if let filter, RexCategory(rawType: rec.items?.type) != filter { return false }
            if let subFilter, !splitGenres(rec.items?.genre).contains(subFilter) { return false }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                let q = query.lowercased()
                let haystack = [
                    rec.items?.title, rec.items?.subtitle, rec.note,
                    rec.profiles?.username, rec.profiles?.display_name,
                ].compactMap { $0 }.joined(separator: " ").lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                RexColor.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: RexSpacing.betweenCards) {
                        header

                        if isLoading {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: RexRadius.card)
                                    .fill(RexColor.muted)
                                    .frame(height: 130)
                            }
                        } else if let errorMessage {
                            errorState(errorMessage)
                        } else if recommendations.isEmpty {
                            emptyState
                        } else if visible.isEmpty {
                            noMatchesState
                        } else {
                            ForEach(visible) { rec in
                                // Trips open their itinerary; everything else
                                // opens the item screen.
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
                    .padding(.horizontal, RexSpacing.page)
                    .padding(.bottom, RexSpacing.xxl)
                }
                .refreshable { await loadFeed() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { itemId in
                ItemDetailView(itemId: itemId)
            }
            .navigationDestination(for: TripRoute.self) { route in
                TripDetailView(route: route)
            }
            .navigationDestination(for: NotificationsRoute.self) { _ in
                NotificationsView()
            }
            .navigationDestination(for: ProfileRoute.self) { _ in
                ProfileView(onSignedOut: onSignedOut)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("REX")
                        .font(RexFont.display(20, weight: .semibold))
                        .foregroundStyle(RexColor.primary)
                        .tracking(1)
                        // Without this the toolbar squeezes it to "R…".
                        .fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: RexSpacing.lg) {
                        NavigationLink(value: NotificationsRoute()) {
                            Image(systemName: "bell")
                                .font(.system(size: 18))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                        // Profile avatar replaces the old "Sign out" button;
                        // logging out now lives at the bottom of Profile.
                        NavigationLink(value: ProfileRoute()) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                }
            }
        }
        .tint(RexColor.primary)
        .onChange(of: popToRootSignal) { _, _ in
            path = NavigationPath()
        }
        .task { await loadFeed() }
        .sheet(isPresented: $showingAddRex, onDismiss: { Task { await loadFeed() } }) {
            AddRexView(onDone: { showingAddRex = false })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RexSpacing.md) {
            // No "Your feed" heading — the feed is the home screen, so naming
            // it just eats vertical space above the content.
            searchField

            if !availableCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        filterChip(title: "All", isActive: filter == nil) {
                            filter = nil; subFilter = nil
                        }
                        ForEach(availableCategories, id: \.self) { category in
                            filterChip(title: category.label, isActive: filter == category) {
                                filter = (filter == category) ? nil : category
                                subFilter = nil
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            if !availableSubcategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        ForEach(availableSubcategories, id: \.self) { genre in
                            filterChip(title: genre, isActive: subFilter == genre, small: true) {
                                subFilter = (subFilter == genre) ? nil : genre
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(.top, RexSpacing.sm)
    }

    private var searchField: some View {
        HStack(spacing: RexSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(RexColor.placeholder)
            TextField("Search Rex, people, places…", text: $query)
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.foreground)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(RexColor.placeholder)
                }
            }
        }
        .padding(.horizontal, RexSpacing.lg)
        .frame(height: 46)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
    }

    private func filterChip(
        title: String,
        isActive: Bool,
        small: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(RexFont.text(small ? 12 : 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? RexColor.primaryForeground : RexColor.mutedForeground)
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, small ? 5 : 7)
                .background(isActive ? RexColor.primary : RexColor.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isActive ? RexColor.primary : RexColor.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func loadFeed() async {
        isLoading = recommendations.isEmpty
        errorMessage = nil
        do {
            recommendations = try await RexAPI.shared.fetchFeed()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private var emptyState: some View {
        VStack(spacing: RexSpacing.md) {
            Text("Your feed is empty")
                .font(RexFont.display(22, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Add friends or follow a creator — their picks will land here.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
        .padding(.top, RexSpacing.xxl)
    }

    private var noMatchesState: some View {
        VStack(spacing: RexSpacing.sm) {
            Text("Nothing matches")
                .font(RexFont.display(20, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Try a different filter or search.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(RexColor.destructive)
            Text(message)
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadFeed() } }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
        .padding(.top, RexSpacing.xxl)
    }
}

/// Genres are stored comma-separated on items, same as the web splitGenres().
func splitGenres(_ raw: String?) -> [String] {
    (raw ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}
