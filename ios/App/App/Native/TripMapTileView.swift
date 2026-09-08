import SwiftUI

/// A static map preview of a trip's stops, shown as a tile on the trip's own
/// card — same visual slot RecommendationCardView's photo carousel uses,
/// full card width. A live GMSMapView per card in a scrolling feed would be
/// needlessly heavy (many map instances rendering/animating at once); a
/// single static image, generated once and cached like any other AsyncImage,
/// gives the same "here's where this trip goes" glance without the cost.
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
    /// only to sequence the route line. Coordinates themselves still come
    /// from `stops` (fetchMapPlaces' self-heal geocode-repair), so an old
    /// stop with an address but no lat/lng yet still gets a shot at showing
    /// up here rather than silently breaking the route.
    @State private var orderedItemIds: [String] = []
    @State private var isLoading = true

    /// Google's Static Maps API auto-fits the viewport to every marker
    /// supplied, so no explicit center/zoom is needed — matches however
    /// tightly or loosely the stops are actually spread out. A path is only
    /// worth drawing for 2+ resolved stops — one point has nothing to
    /// connect, and the fit-to-markers behavior already handles a single
    /// stop fine on its own.
    private var staticMapURL: URL? {
        guard !stops.isEmpty else { return nil }
        let byItemId = Dictionary(uniqueKeysWithValues: stops.compactMap { place -> (String, MapPlace)? in
            guard place.lat != nil, place.lng != nil else { return nil }
            return (place.id, place)
        })
        // Capped — a static map URL has a real length ceiling, and a trip
        // with dozens of stops reads fine as "the busiest dozen or so".
        let ordered = orderedItemIds.compactMap { byItemId[$0] }.prefix(20)
        // A stop added a way that never populated trip_section/order (or one
        // this tile loaded before the trip-stops fetch resolved) still
        // deserves a marker — just not necessarily first in the route line.
        let unordered = stops.filter { place in
            place.lat != nil && place.lng != nil && !orderedItemIds.contains(place.id)
        }
        let sequence = Array(ordered) + unordered

        let scale = Int(UIScreen.main.scale)
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")!
        var queryItems = [
            URLQueryItem(name: "size", value: "640x320"),
            URLQueryItem(name: "scale", value: "\(min(scale, 2))"),
            URLQueryItem(name: "key", value: googleKey),
        ]
        for place in sequence {
            queryItems.append(URLQueryItem(name: "markers", value: "color:0x173626|\(place.lat!),\(place.lng!)"))
        }
        // Sept 8 — "remove the lines from the trip maps". The route line
        // drew stops in itinerary order, which implies a journey the trip
        // rarely describes: a week in Paris isn't a path between its
        // restaurants, and the line zig-zagged across the tile making the
        // markers harder to read rather than easier. Markers alone say the
        // true thing — here is where this trip happened.
        components.queryItems = queryItems
        return components.url
    }

    private var googleKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    }

    var body: some View {
        // Sept 7 — "the trip cards in the feed are still wider than other
        // cards". This used to be Group { image }.frame(height:) .frame(
        // maxWidth: .infinity).clipped(), which lets the image drive the
        // layout: a .fill image at a fixed height is intrinsically wider
        // than its box, .clipped() only stops it being *drawn* outside, and
        // the width it claimed had already widened the card. Sizing an
        // empty box first and hanging the image off it as an overlay means
        // the layout comes from the box, never the picture.
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let url = staticMapURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            placeholder
                        }
                    }
                } else if isLoading {
                    placeholder.overlay(ProgressView())
                } else {
                    placeholder
                }
            }
            .clipped()
            .task { await load() }
    }

    private var placeholder: some View {
        RexColor.muted.overlay(
            Image(systemName: "map")
                .font(.system(size: 22))
                .foregroundStyle(RexColor.mutedForeground)
        )
    }

    private func load() async {
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

    private var googleKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    }

    private var staticMapURL: URL? {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")!
        components.queryItems = [
            URLQueryItem(name: "size", value: "640x280"),
            URLQueryItem(name: "scale", value: "\(min(Int(UIScreen.main.scale), 2))"),
            URLQueryItem(name: "zoom", value: "14"),
            URLQueryItem(name: "center", value: "\(lat),\(lng)"),
            URLQueryItem(name: "markers", value: "color:0x173626|\(lat),\(lng)"),
            URLQueryItem(name: "key", value: googleKey),
        ]
        return components.url
    }

    var body: some View {
        // Same box-first layout as the trip tile above, for the same reason.
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                if let url = staticMapURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            RexColor.muted.overlay(
                                Image(systemName: "map")
                                    .font(.system(size: 20))
                                    .foregroundStyle(RexColor.mutedForeground)
                            )
                        }
                    }
                } else {
                    RexColor.muted
                }
            }
            .clipped()
    }
}
