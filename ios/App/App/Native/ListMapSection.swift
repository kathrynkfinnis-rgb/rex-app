import SwiftUI
import CoreLocation

/// Oct 14 — "for a list of places, can we have a map view?"
///
/// The third segment of a list's own toggle, rather than a trip to the Map
/// tab: a list of twelve London date-night places is a thing you read as a
/// shape — these three are all in Peckham, that one is miles away — and
/// leaving the page to see it loses the list.
///
/// A live map rather than a snapshot, because the question people have once
/// they can see the shape is "what's that one?", and that needs a tap. Trips
/// use a still image on their *card*, in a scrolling feed, where a dozen live
/// maps at once would be the wrong trade; this is one map on one page.
struct ListMapSection: View {
    let listRecommendationId: String
    var listName: String?
    var height: CGFloat = 420

    @State private var places: [MapPlace] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selected: MapPlace?
    /// Bumped once the places land, to frame all of them at once.
    @State private var fitNonce = 0

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            ZStack(alignment: .bottom) {
                if isLoading {
                    RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                        .fill(RexColor.muted)
                        .frame(height: height)
                        .overlay(ProgressView())
                } else if places.isEmpty {
                    RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                        .fill(RexColor.muted)
                        .frame(height: height)
                        .overlay(
                            Text(errorMessage ?? "None of these have a location on them yet.")
                                .font(RexFont.text(14))
                                .foregroundStyle(RexColor.mutedForeground)
                                .multilineTextAlignment(.center)
                                .padding(RexSpacing.xl)
                        )
                } else {
                    AppleMapView(
                        places: places,
                        center: nil,
                        radiusMeters: 3000,
                        focusRequest: nil,
                        onSelect: { selected = $0 },
                        // Several of a list's places at one address — a food
                        // market, a hotel with three restaurants in it — can't
                        // be separated by zooming, so the first is picked and
                        // named rather than nothing happening.
                        onSelectMany: { selected = $0.first },
                        fitToPlacesNonce: fitNonce
                    )
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                            .stroke(RexColor.border, lineWidth: 1)
                    )

                    if let selected {
                        callout(selected)
                            .padding(RexSpacing.sm)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.snappy, value: selected?.id)

            if !places.isEmpty {
                Text(places.count == 1 ? "1 of these has a location" : "\(places.count) of these have locations")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        }
        .task { await load() }
    }

    /// What you tapped, and the way through to it. A card rather than a sheet:
    /// the point of the map is the shape of the list, and a sheet covers it.
    private func callout(_ place: MapPlace) -> some View {
        NavigationLink(value: place.id) {
            HStack(spacing: RexSpacing.md) {
                Group {
                    if let urlString = place.image_url, let url = URL(string: urlString) {
                        GoogleSafeAsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { RexColor.muted }
                    } else {
                        ZStack {
                            RexColor.badgeBackground
                            Image(systemName: "mappin")
                                .font(.system(size: 14))
                                .foregroundStyle(RexColor.primary)
                        }
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.title)
                        .font(RexFont.text(15, weight: .bold))
                        .foregroundStyle(RexColor.foreground)
                        .lineLimit(1)
                    if let detail = [place.genre, place.address].compactMap({ $0 })
                        .first(where: { !$0.isEmpty }) {
                        Text(detail)
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RexColor.border)
            }
            .padding(RexSpacing.sm)
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            places = try await RexAPI.shared.fetchMapPlaces(
                forList: listRecommendationId, listName: listName
            )
            fitNonce += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
