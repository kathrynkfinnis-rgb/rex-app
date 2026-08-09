import SwiftUI

private struct NotificationsRoute: Hashable {}

struct FeedView: View {
    var onSignedOut: () -> Void

    @State private var recommendations: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingAddRex = false

    var body: some View {
        NavigationStack {
            ZStack {
                RexColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        if isLoading {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(RexColor.muted)
                                    .frame(height: 120)
                            }
                        } else if let errorMessage {
                            errorState(errorMessage)
                        } else if recommendations.isEmpty {
                            emptyState
                        } else {
                            ForEach(recommendations) { rec in
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
                    .padding(12)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAddRex = true
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 22))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        NavigationLink(value: NotificationsRoute()) {
                            Image(systemName: "bell").font(.system(size: 19))
                        }
                        Button("Sign out") {
                            RexAPI.shared.signOut()
                            onSignedOut()
                        }
                        .font(.footnote)
                        .foregroundStyle(RexColor.mutedForeground)
                    }
                }
            }
        }
        .tint(RexColor.primary)
        .task { await loadFeed() }
        .sheet(isPresented: $showingAddRex, onDismiss: { Task { await loadFeed() } }) {
            AddRexView(onDone: { showingAddRex = false })
        }
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
        VStack(spacing: 12) {
            Text("REX").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(RexColor.primary)
            Text("Your feed is empty").font(.title3).fontWeight(.semibold)
            Text("Add friends or follow a creator — their picks will land here. Tap Friends below to add people.")
                .font(.subheadline)
                .foregroundStyle(RexColor.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(.footnote).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await loadFeed() } }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(RexColor.primary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}
