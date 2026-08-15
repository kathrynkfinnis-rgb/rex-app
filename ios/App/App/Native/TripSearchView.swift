import SwiftUI

/// The Map page's "Trips" filter is fine with a handful of trips, but it's
/// just chip-scrolling through everyone's — it won't scale. This is a
/// dedicated search/browse screen: pick a trip here, and the Map focuses on
/// it exactly the way tapping its chip used to.
struct TripSearchView: View {
    /// Handed the picked trip's id and title — the map fetches that trip's
    /// own stops directly rather than hoping they're already loaded (see
    /// RexMapView.followTrip), so this only needs to report the choice, not
    /// hold any of the map's state itself.
    var onSelect: (_ id: String, _ title: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var trips: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var query = ""

    private var availableGenres: [String] {
        var set = Set<String>()
        for trip in trips { for genre in splitGenres(trip.items?.genre) { set.insert(genre) } }
        return set.sorted()
    }

    @State private var genreFilter: String?

    private var filtered: [FeedRecommendation] {
        trips.filter { trip in
            if let genreFilter, !splitGenres(trip.items?.genre).contains(genreFilter) { return false }
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return true }
            let haystack = [
                trip.items?.title, trip.items?.subtitle, trip.note,
                trip.profiles?.display_name, trip.profiles?.username,
            ].compactMap { $0 }.joined(separator: " ").lowercased()
            return haystack.contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    searchField

                    if !availableGenres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: RexSpacing.sm) {
                                ForEach(availableGenres, id: \.self) { genre in
                                    genreChip(genre)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else if filtered.isEmpty {
                        empty()
                    } else {
                        VStack(spacing: RexSpacing.sm) {
                            ForEach(filtered) { trip in
                                tripRow(trip)
                            }
                        }
                    }
                }
                .padding(.horizontal, RexSpacing.page)
                .padding(.vertical, RexSpacing.lg)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Find a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var searchField: some View {
        HStack(spacing: RexSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(RexColor.placeholder)
            TextField("Search trips…", text: $query)
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.foreground)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
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

    private func genreChip(_ genre: String) -> some View {
        let isActive = genreFilter == genre
        return Button {
            genreFilter = isActive ? nil : genre
        } label: {
            Text(genre)
                .font(RexFont.text(12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? RexColor.primaryForeground : RexColor.mutedForeground)
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, 5)
                .background(isActive ? RexColor.primary : RexColor.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isActive ? RexColor.primary : RexColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func tripRow(_ trip: FeedRecommendation) -> some View {
        Button {
            onSelect(trip.id, trip.items?.title ?? "Trip")
            dismiss()
        } label: {
            HStack(spacing: RexSpacing.md) {
                ZStack {
                    RexColor.muted
                    Image(systemName: "bag").font(.system(size: 18)).foregroundStyle(RexColor.mutedForeground)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.items?.title ?? "Trip")
                        .font(RexFont.text(15, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(1)
                    if let by = trip.profiles?.display_name ?? trip.profiles?.username {
                        Text("by \(by)")
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                }

                Spacer(minLength: RexSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RexColor.mutedForeground)
            }
            .padding(RexSpacing.cardPadding)
            .rexCard()
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            trips = try await RexAPI.shared.fetchTrips()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func empty() -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "bag").font(.system(size: 28)).foregroundStyle(RexColor.mutedForeground)
            Text(query.isEmpty && genreFilter == nil ? "No trips yet" : "No trips match")
                .font(RexFont.display(18, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, RexSpacing.xxl)
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
