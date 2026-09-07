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
    /// #150 — this sheet only ever listed trips you'd already started;
    /// there was no way to start one from here, so a place you wanted to
    /// build a new trip around meant leaving, going to "+", building the
    /// trip, then coming back to add this place a second time.
    @State private var showingNewTrip = false
    @State private var newTripTitle = ""
    @State private var isCreatingTrip = false

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

                    if showingNewTrip {
                        VStack(alignment: .leading, spacing: RexSpacing.sm) {
                            Text("New trip").font(RexFont.text(14, weight: .semibold))
                            TextField("e.g. Rye, Sussex", text: $newTripTitle)
                                .font(RexFont.text(15))
                                .padding(RexSpacing.md)
                                .background(RexColor.card)
                                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                        .stroke(RexColor.border, lineWidth: 1)
                                )
                            HStack {
                                Button("Cancel") {
                                    showingNewTrip = false
                                    newTripTitle = ""
                                }
                                .font(RexFont.text(13))
                                .foregroundStyle(RexColor.mutedForeground)
                                Spacer()
                                Button {
                                    Task { await createTripAndAdd() }
                                } label: {
                                    if isCreatingTrip {
                                        ProgressView().tint(RexColor.primaryForeground)
                                    } else {
                                        Text("Create & add")
                                    }
                                }
                                .buttonStyle(RexPrimaryButtonStyle())
                                .disabled(isCreatingTrip || newTripTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(RexSpacing.md)
                        .rexCard()
                    } else {
                        Button {
                            showingNewTrip = true
                        } label: {
                            Label("New trip", systemImage: "plus")
                                .font(RexFont.text(14, weight: .medium))
                        }
                        .buttonStyle(RexSecondaryButtonStyle())
                        .disabled(busyId != nil || addedId != nil)
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
            .rexDismissableKeyboard()
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
            try await RexAPI.shared.addPlaceToTrip(itemId: itemId, tripId: trip.id)
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

    /// #150 — same two-step shape AddRexView uses to post a trip (create
    /// the trip's own item+recommendation, then add stops under it), just
    /// starting from zero stops and adding exactly one: this place.
    private func createTripAndAdd() async {
        let trimmed = newTripTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isCreatingTrip = true
        errorMessage = nil
        do {
            let tripItemId = try await RexAPI.shared.createItem(type: RexCategory.trip.rawValue, title: trimmed, subtitle: nil, address: nil)
            let tripRecId = try await RexAPI.shared.createRecommendation(itemId: tripItemId, rating: 0, note: nil, returningId: true)
            try await RexAPI.shared.addPlaceToTrip(itemId: itemId, tripId: tripRecId)
            // A beat so success actually registers before the sheet closes,
            // same reasoning as add(to:) above.
            try? await Task.sleep(for: .seconds(0.5))
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreatingTrip = false
    }
}
