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
    /// Sept 10 — "when you click on the map in a trip card in the feed, it
    /// should take you to a filtered view of the map with just the pins for
    /// that trip on it, zoomed to show all of them". Set instead of an item
    /// to follow a whole trip.
    var tripId: String? = nil
    var tripTitle: String? = nil
}

struct GoogleMapView: UIViewRepresentable {
    let places: [MapPlace]
    /// Centre point and radius (metres) to show on first load.
    var center: CLLocationCoordinate2D?
    var radiusMeters: Double
    /// Jump straight to one place, overriding wherever the map currently sits.
    var focusRequest: MapFocusRequest?
    var onSelect: (MapPlace) -> Void
    /// #167 — "add a Rex by finding a place on the map first". A tap alone
    /// is already claimed (panning/pin selection); long-press is the same
    /// gesture Apple/Google Maps themselves use for "drop a pin here".
    var onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil
    /// Bumped whenever the camera should frame every pin currently shown —
    /// following a trip, so all its stops are on screen at once rather than
    /// wherever the map happened to be sitting.
    var fitToPlacesNonce: Int = 0

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

        // Only once the pins are there to frame — a nonce that arrives
        // before its places would otherwise be spent on an empty map.
        if fitToPlacesNonce != context.coordinator.lastFitNonce {
            let coords = places.compactMap { p -> CLLocationCoordinate2D? in
                guard let lat = p.lat, let lng = p.lng else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
            if coords.count == 1 {
                // Fitting one point zooms to street level; a single stop
                // reads better with some neighbourhood around it.
                mapView.animate(to: GMSCameraPosition(target: coords[0], zoom: zoomFor(radiusMeters: 1500)))
                context.coordinator.lastFitNonce = fitToPlacesNonce
            } else if coords.count > 1 {
                var bounds = GMSCoordinateBounds()
                for coord in coords { bounds = bounds.includingCoordinate(coord) }
                // Generous at the top: the map's header (area name, the
                // "Following" bar and two rows of filter chips) floats over
                // the top ~230pt, and a pin framed under it is as good as
                // missing. Bottom clears the tab bar and the + button.
                mapView.animate(with: GMSCameraUpdate.fit(bounds, with: UIEdgeInsets(top: 250, left: 50, bottom: 130, right: 50)))
                context.coordinator.lastFitNonce = fitToPlacesNonce
            }
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
    /// Sept 5 — was forest green for everything bar events, which on a map
    /// of mostly places distinguished almost nothing. Now keyed to the
    /// place's own sub-category, so dinner, drinks and somewhere to stay
    /// read apart at a glance. See rexSubcategoryColor.
    private func markerColor(for place: MapPlace) -> UIColor {
        UIColor(rexSubcategoryColor(genre: place.genre, type: place.type))
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
        var lastFitNonce = 0

        init(_ parent: GoogleMapView) { self.parent = parent }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = marker.userData as? String, let place = markersById[id] {
                parent.onSelect(place)
            }
            return true
        }

        func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            parent.onLongPress?(coordinate)
        }
    }
}
