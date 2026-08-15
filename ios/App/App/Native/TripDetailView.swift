import SwiftUI

/// Route marker so a trip card can navigate to the itinerary rather than the
/// generic item screen. Trips are addressed by their *recommendation* id,
/// because that's what a stop's trip_id points at.
struct TripRoute: Hashable, Identifiable {
    let recommendationId: String
    let title: String

    var id: String { recommendationId }
}

/// The itinerary for a trip: every stop, grouped under its optional heading,
/// in the order it was added. Mirrors the web trip page.
struct TripDetailView: View {
    let route: TripRoute

    @State private var stops: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isDraft = false
    @State private var isPublishing = false
    @State private var publishError: String?

    /// Stops grouped by heading, preserving the order both groups and stops
    /// first appear in — same rule as the web's groupStops().
    private var groups: [(heading: String, stops: [FeedRecommendation])] {
        var result: [(heading: String, stops: [FeedRecommendation])] = []
        for stop in stops {
            let heading = (stop.trip_section ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let idx = result.firstIndex(where: { $0.heading.caseInsensitiveCompare(heading) == .orderedSame }) {
                result[idx].stops.append(stop)
            } else {
                result.append((heading: heading, stops: [stop]))
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16).fill(RexColor.muted).frame(height: 90)
                    }
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if stops.isEmpty {
                    Text("No stops on this trip yet.")
                        .font(.footnote)
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 8) {
                            if !group.heading.isEmpty {
                                Text(group.heading)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundStyle(RexColor.foreground)
                                    .padding(.top, 4)
                            }
                            ForEach(group.stops) { stop in
                                NavigationLink(value: stop.item_id) {
                                    RecommendationCardView(rec: stop)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "bag").font(.system(size: 10))
                Text("TRIP").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(RexColor.primary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RexColor.primary.opacity(0.1))
            .clipShape(Capsule())

            Text(route.title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(RexColor.foreground)

            if !isLoading {
                Text("\(stops.count) \(stops.count == 1 ? "stop" : "stops")")
                    .font(.footnote)
                    .foregroundStyle(RexColor.mutedForeground)
            }

            if isDraft {
                draftBanner
            }
        }
    }

    /// Only ever shown to the trip's own author — RLS hides a draft from
    /// anyone else before this view could even load it.
    private var draftBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.system(size: 12))
                Text("Draft — only you can see this")
                    .font(RexFont.text(13, weight: .medium))
                Spacer()
            }
            .foregroundStyle(RexColor.mutedForeground)

            Button {
                Task { await publish() }
            } label: {
                if isPublishing {
                    ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                } else {
                    Text("Publish trip").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44)
            .background(RexColor.primary)
            .foregroundStyle(RexColor.primaryForeground)
            .clipShape(Capsule())
            .disabled(isPublishing || stops.isEmpty)

            if stops.isEmpty {
                Text("Add at least one stop before publishing.")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            if let publishError {
                Text(publishError)
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.destructive)
            }
        }
        .padding(12)
        .background(RexColor.badgeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func publish() async {
        isPublishing = true
        publishError = nil
        do {
            try await RexAPI.shared.publishTrip(tripRecommendationId: route.recommendationId)
            isDraft = false
        } catch {
            publishError = error.localizedDescription
        }
        isPublishing = false
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let stopsTask = RexAPI.shared.fetchTripStops(tripRecommendationId: route.recommendationId)
            async let draftTask = RexAPI.shared.isDraft(recommendationId: route.recommendationId)
            stops = try await stopsTask
            // Best-effort: not knowing whether it's a draft shouldn't block
            // seeing the itinerary itself.
            isDraft = (try? await draftTask) ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(.footnote).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.footnote.weight(.semibold)).foregroundStyle(RexColor.primary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
