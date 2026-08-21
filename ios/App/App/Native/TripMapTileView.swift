import SwiftUI

/// A static map preview of a trip's stops, shown as a tile on the trip's own
/// card — same visual slot RecommendationCardView's photo carousel uses,
/// full card width. A live GMSMapView per card in a scrolling feed would be
/// needlessly heavy (many map instances rendering/animating at once); a
/// single static image, generated once and cached like any other AsyncImage,
/// gives the same "here's where this trip goes" glance without the cost.
struct TripMapTileView: View {
    let tripRecommendationId: String
    var height: CGFloat = 200

    @State private var stops: [MapPlace] = []
    @State private var isLoading = true

    /// Google's Static Maps API auto-fits the viewport to every marker
    /// supplied, so no explicit center/zoom is needed — matches however
    /// tightly or loosely the stops are actually spread out.
    private var staticMapURL: URL? {
        guard !stops.isEmpty else { return nil }
        let scale = Int(UIScreen.main.scale)
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")!
        var queryItems = [
            URLQueryItem(name: "size", value: "640x320"),
            URLQueryItem(name: "scale", value: "\(min(scale, 2))"),
            URLQueryItem(name: "key", value: googleKey),
        ]
        // Capped — a static map URL has a real length ceiling, and a trip
        // with dozens of stops reads fine as "the busiest dozen or so".
        for stop in stops.prefix(20) {
            guard let lat = stop.lat, let lng = stop.lng else { continue }
            queryItems.append(URLQueryItem(name: "markers", value: "color:0x173626|\(lat),\(lng)"))
        }
        components.queryItems = queryItems
        return components.url
    }

    private var googleKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    }

    var body: some View {
        Group {
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
        .frame(height: height)
        .frame(maxWidth: .infinity)
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
        stops = (try? await RexAPI.shared.fetchMapPlaces(forTrip: tripRecommendationId)) ?? []
        isLoading = false
    }
}
