import SwiftUI

/// Adds a place to one of your trips as a new stop — task #104's card
/// context menu action, places only. This doesn't touch the place's
/// existing Rex (yours or a friend's); it creates a brand-new stop
/// recommendation under your account pointing at the same item, exactly
/// the way TripStopsBuilderView creates one when you're composing a trip
/// from scratch. Unrated by default (0 — the same "unrated" sentinel
/// drafts use) since this is meant to be a quick one-tap action; you can
/// rate/note it properly later from the trip's own page.
struct AddToTripView: View {
    let itemId: String
    let itemTitle: String
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var trips: [FeedRecommendation] = []
    @State private var isLoading = true
    @State private var busyId: String?
    @State private var addedId: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    Text(itemTitle)
                        .font(RexFont.display(20, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(2)

                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: RexRadius.card)
                                .fill(RexColor.muted)
                                .frame(height: 60)
                        }
                    } else if trips.isEmpty {
                        Text("You haven't started a trip yet. Add one from the \u{201C}+\u{201D} button first, then come back here.")
                            .font(RexFont.text(14))
                            .foregroundStyle(RexColor.mutedForeground)
                    } else {
                        ForEach(trips) { trip in
                            Button {
                                Task { await add(to: trip) }
                            } label: {
                                HStack(spacing: RexSpacing.md) {
                                    Image(systemName: "bag")
                                        .font(.system(size: 16))
                                        .foregroundStyle(RexColor.primary)
                                        .frame(width: 40, height: 40)
                                        .background(RexColor.badgeBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))

                                    Text(trip.items?.title ?? "Trip")
                                        .font(RexFont.text(15, weight: .medium))
                                        .foregroundStyle(RexColor.foreground)

                                    Spacer()

                                    if busyId == trip.id {
                                        ProgressView().controlSize(.small)
                                    } else if addedId == trip.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(RexColor.primary)
                                    }
                                }
                                .padding(RexSpacing.md)
                                .rexCard()
                            }
                            .buttonStyle(.plain)
                            .disabled(busyId != nil || addedId != nil)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Add to trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { onDone(); dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        trips = (try? await RexAPI.shared.fetchMyTrips()) ?? []
        isLoading = false
    }

    private func add(to trip: FeedRecommendation) async {
        busyId = trip.id
        errorMessage = nil
        do {
            try await RexAPI.shared.createRecommendation(
                itemId: itemId, rating: 0, note: nil, tripId: trip.id
            )
            addedId = trip.id
            // A beat so "added" actually registers before the sheet closes,
            // rather than the checkmark flashing and vanishing instantly.
            try? await Task.sleep(for: .seconds(0.5))
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        busyId = nil
    }
}
