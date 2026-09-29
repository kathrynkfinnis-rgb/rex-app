import SwiftUI
import CoreLocation

/// A static map preview of a trip's stops, shown as a tile on the trip's own
/// card — same visual slot RecommendationCardView's photo carousel uses,
/// full card width. A live map per card in a scrolling feed would be
/// needlessly heavy (many map instances rendering/animating at once); a
/// single still image gives the same "here's where this trip goes" glance
/// without the cost.
///
/// Sept 29 — that still image used to come from Google's Static Maps API, one
/// billed request per card per scroll. It's now rendered on the device by
/// MKMapSnapshotter: free, unlimited, no key, and cached between scrolls. See
/// RexMapSnapshot.
struct TripMapTileView: View {
    let tripRecommendationId: String
    /// Context for the geocode self-heal — a stop imported before the
    /// importer geocoded anything has no address and no coordinates, and
    /// its bare title ("Le Comptoir") needs the trip's name to resolve to
    /// the right city. See repairPlaceCoordsIfNeeded's fallbackQuery.
    var tripName: String? = nil
    var height: CGFloat = 200

    @State private var stops: [MapPlace] = []
    /// #158 — itinerary order (fetchTripStops is already the source of
    /// truth for stop order everywhere else, e.g. TripDetailView), used
    /// only to sequence the stops. Coordinates themselves still come
    /// from `stops` (fetchMapPlaces' self-heal geocode-repair), so an old
    /// stop with an address but no lat/lng yet still gets a shot at showing
    /// up here rather than silently breaking the tile.
    @State private var orderedItemIds: [String] = []
    @State private var isLoading = true

    /// The viewport is fitted to whatever's here, so no explicit centre or
    /// zoom is needed — it matches however tightly or loosely the stops are
    /// actually spread out, the way the Static Maps version did.
    ///
    /// Sept 8 — "remove the lines from the trip maps". The route line drew
    /// stops in itinerary order, which implies a journey the trip rarely
    /// describes: a week in Paris isn't a path between its restaurants, and
    /// the line zig-zagged across the tile making the markers harder to read
    /// rather than easier. Markers alone say the true thing — here is where
    /// this trip happened. Order is still respected for *which* stops make
    /// the cut when a trip has more than the cap.
    private var coordinates: [CLLocationCoordinate2D] {
        let byItemId = Dictionary(uniqueKeysWithValues: stops.compactMap { place -> (String, MapPlace)? in
            guard place.lat != nil, place.lng != nil else { return nil }
            return (place.id, place)
        })
        // Capped — a trip with dozens of stops reads fine as "the busiest
        // dozen or so", and every extra pin is another one drawn by hand.
        let ordered = orderedItemIds.compactMap { byItemId[$0] }.prefix(20)
        // A stop added a way that never populated trip_section/order (or one
        // this tile loaded before the trip-stops fetch resolved) still
        // deserves a marker.
        let unordered = stops.filter { place in
            place.lat != nil && place.lng != nil && !orderedItemIds.contains(place.id)
        }
        return (Array(ordered) + unordered).compactMap { place in
            guard let lat = place.lat, let lng = place.lng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    var body: some View {
        // Sept 7 — "the trip cards in the feed are still wider than other
        // cards". The box-first layout that fixed it now lives in
        // RexMapSnapshotView, which every map tile shares.
        if !coordinates.isEmpty {
            RexMapSnapshotView(coordinates: coordinates, height: height)
                .task { await load() }
        } else {
            Color.clear
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .overlay {
                    if isLoading {
                        placeholder.overlay(ProgressView())
                    } else {
                        placeholder
                    }
                }
                .clipped()
                .task { await load() }
        }
    }

    private var placeholder: some View {
        RexColor.muted.overlay(
            Image(systemName: "map")
                .font(.system(size: 22))
                .foregroundStyle(RexColor.mutedForeground)
        )
    }

    private func load() async {
        guard stops.isEmpty else { return }
        async let placesTask = RexAPI.shared.fetchMapPlaces(forTrip: tripRecommendationId, tripName: tripName)
        async let orderTask = RexAPI.shared.fetchTripStops(tripRecommendationId: tripRecommendationId)
        stops = (try? await placesTask) ?? []
        orderedItemIds = ((try? await orderTask) ?? []).map { $0.item_id }
        isLoading = false
    }
}

/// Sept 5 — "a small map thumbnail on a place's card". A trip already gets
/// one built from its stops (above); this is the single-pin equivalent for
/// a place or event, shown in the same slot — which is otherwise empty when
/// the Rex has no photo of its own.
///
/// Deliberately only used when there's no photo: someone's own picture of
/// the place beats a map of it, and stacking both would make the card twice
/// as tall for no gain.
struct PlaceMapTileView: View {
    let lat: Double
    let lng: Double
    var height: CGFloat = 140

    var body: some View {
        RexMapSnapshotView(
            coordinates: [CLLocationCoordinate2D(latitude: lat, longitude: lng)],
            height: height
        )
    }
}
