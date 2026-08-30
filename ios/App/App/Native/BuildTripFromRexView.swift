import SwiftUI

/// #183 — "pool all your Rex into a trip": rather than rebuilding an
/// itinerary from scratch (TripStopsBuilderView's normal flow, which
/// always creates fresh items), this picks from places/events you've
/// *already* Rex'd standalone and folds the ones you tick into a new
/// trip as its stops — same row each already lived in, just re-pointed
/// at the new trip via RexAPI.assignRecommendationToTrip rather than
/// duplicated.
///
/// Itinerary order is deliberately just "the order you originally added
/// them" (fetchStandalonePlaceRex's own created_at.asc, unchanged by
/// selection) — no proximity/day grouping. Simplest version that's
/// still useful; a fancier ordering pass is a natural follow-up if this
/// one earns its keep.
struct BuildTripFromRexView: View {
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [FeedRecommendation] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var title = ""
    @State private var isCreating = false
    @State private var progress: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                VStack(alignment: .leading, spacing: RexSpacing.sm) {
                    Text("Trip name").font(RexFont.text(14, weight: .semibold))
                    TextField("e.g. Cornwall, July", text: $title)
                        .font(RexFont.text(15))
                        .padding(RexSpacing.md)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                }
                .padding(.horizontal, RexSpacing.page)
                .padding(.top, RexSpacing.md)

                Text("Pick the places to fold in — they'll keep their rating, note and photos, they'll just live under this trip from now on instead of standalone.")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.horizontal, RexSpacing.page)

                ScrollView {
                    VStack(spacing: RexSpacing.sm) {
                        if isLoading {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: RexRadius.card)
                                    .fill(RexColor.muted)
                                    .frame(height: 60)
                            }
                        } else if candidates.isEmpty {
                            Text("No standalone places or events to pool yet — Rex a few first, then come back here.")
                                .font(RexFont.text(14))
                                .foregroundStyle(RexColor.mutedForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.top, RexSpacing.xxl)
                        } else {
                            ForEach(candidates) { rec in
                                candidateRow(rec)
                            }
                        }
                    }
                    .padding(.horizontal, RexSpacing.page)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                        .padding(.horizontal, RexSpacing.page)
                }

                Button {
                    Task { await createTrip() }
                } label: {
                    if isCreating {
                        VStack(spacing: 4) {
                            ProgressView().tint(RexColor.primaryForeground)
                            if let progress {
                                Text(progress).font(RexFont.text(11)).foregroundStyle(RexColor.primaryForeground)
                            }
                        }
                    } else {
                        Text(selected.isEmpty ? "Create trip" : "Create trip with \(selected.count) \(selected.count == 1 ? "stop" : "stops")")
                    }
                }
                .buttonStyle(RexPrimaryButtonStyle())
                .disabled(isCreating || selected.isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, RexSpacing.page)
                .padding(.bottom, RexSpacing.xl)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Build a trip from your Rex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .task { await load() }
    }

    private func candidateRow(_ rec: FeedRecommendation) -> some View {
        let isSelected = selected.contains(rec.id)
        return Button {
            if isSelected { selected.remove(rec.id) } else { selected.insert(rec.id) }
        } label: {
            HStack(spacing: RexSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? RexColor.primary : RexColor.mutedForeground)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.items?.title ?? "Untitled")
                        .font(RexFont.text(15, weight: .medium))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(1)
                    if let subtitle = rec.items?.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if rec.rating > 0 {
                    Text(RexRatingTier.tier(forRaw: rec.rating).emoji)
                        .font(.system(size: 16))
                }
            }
            .padding(RexSpacing.md)
            .rexCard()
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
    }

    private func load() async {
        isLoading = true
        candidates = (try? await RexAPI.shared.fetchStandalonePlaceRex()) ?? []
        isLoading = false
    }

    private func createTrip() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, !selected.isEmpty else { return }
        isCreating = true
        errorMessage = nil
        do {
            let tripItemId = try await RexAPI.shared.createItem(type: RexCategory.trip.rawValue, title: trimmedTitle, subtitle: nil, address: nil)
            let tripRecId = try await RexAPI.shared.createRecommendation(itemId: tripItemId, rating: 0, note: nil, returningId: true)
            // Order matches candidates' own created_at.asc — "just the
            // order added" is the whole itinerary-ordering story here, so
            // this loop doesn't need to reorder anything itself.
            let toAssign = candidates.filter { selected.contains($0.id) }
            for (index, rec) in toAssign.enumerated() {
                progress = toAssign.count > 1 ? "Adding stop \(index + 1) of \(toAssign.count)…" : "Adding stop…"
                try await RexAPI.shared.assignRecommendationToTrip(recommendationId: rec.id, tripId: tripRecId)
            }
            progress = nil
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}
