import SwiftUI
import GoogleMaps
import CoreLocation

/// Google Maps, so the native map matches the web app rather than showing
/// Apple's basemap. Wraps GMSMapView for SwiftUI.
/// #133 "view on map" — a request to jump to one specific pin, distinct from
/// the general `center` (which only ever fires once, on first load — see
/// Coordinator.didCenter). Carries a nonce so tapping "view on map" again on
/// the same place still re-centres, rather than a same-value SwiftUI update
/// being silently ignored.
struct MapFocusRequest: Equatable {
    let itemId: String
    let nonce: Int
}

struct GoogleMapView: UIViewRepresentable {
    let places: [MapPlace]
    /// Centre point and radius (metres) to show on first load.
    var center: CLLocationCoordinate2D?
    var radiusMeters: Double
    /// Jump straight to one place, overriding wherever the map currently sits.
    var focusRequest: MapFocusRequest?
    var onSelect: (MapPlace) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(
            latitude: center?.latitude ?? 51.5074,
            longitude: center?.longitude ?? -0.1278,
            zoom: zoomFor(radiusMeters: radiusMeters)
        )
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = true
        mapView.settings.compassButton = true
        mapView.padding = UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // Only rebuild markers when the set of places actually changes —
        // clearing on every SwiftUI update makes the map flicker.
        let ids = places.map(\.id).joined(separator: ",")
        if context.coordinator.renderedIds != ids {
            mapView.clear()
            context.coordinator.markersById.removeAll()
            for place in places {
                guard let lat = place.lat, let lng = place.lng else { continue }
                let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                marker.title = place.title
                marker.snippet = place.recommenderSummary
                marker.icon = GMSMarker.markerImage(with: markerColor(for: place))
                marker.userData = place.id
                marker.map = mapView
                context.coordinator.markersById[place.id] = place
            }
            context.coordinator.renderedIds = ids
        }

        if let center, !context.coordinator.didCenter {
            mapView.animate(to: GMSCameraPosition(
                target: center,
                zoom: zoomFor(radiusMeters: radiusMeters)
            ))
            context.coordinator.didCenter = true
        }

        if let focusRequest, focusRequest != context.coordinator.lastFocusRequest,
           let place = places.first(where: { $0.id == focusRequest.itemId }),
           let lat = place.lat, let lng = place.lng {
            // Tighter than the general area radius — this is "show me this
            // one place", not "show me the neighbourhood".
            mapView.animate(to: GMSCameraPosition(
                target: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                zoom: zoomFor(radiusMeters: 800)
            ))
            context.coordinator.lastFocusRequest = focusRequest
        }
    }

    /// Events get the gold accent; everything else forest green, matching the
    /// "colour sparingly" rule.
    private func markerColor(for place: MapPlace) -> UIColor {
        RexCategory(rawType: place.type) == .event
            ? UIColor(RexColor.gold)
            : UIColor(RexColor.primary)
    }

    /// Rough conversion from a radius in metres to a Google zoom level.
    private func zoomFor(radiusMeters: Double) -> Float {
        let equatorMeters = 40_075_016.686
        let screenPx = 640.0
        let zoom = log2(equatorMeters * screenPx / (256.0 * max(radiusMeters, 1) * 2))
        return Float(min(max(zoom, 2), 18))
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        let parent: GoogleMapView
        var markersById: [String: MapPlace] = [:]
        var renderedIds = ""
        var didCenter = false
        var lastFocusRequest: MapFocusRequest?

        init(_ parent: GoogleMapView) { self.parent = parent }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = marker.userData as? String, let place = markersById[id] {
                parent.onSelect(place)
            }
            return true
        }
    }
}
