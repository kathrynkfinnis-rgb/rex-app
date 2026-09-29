import SwiftUI
import MapKit
import CoreLocation

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

/// Sept 29 — the maps cost review. This was GMSMapView (see the deleted
/// GoogleMapView), which bills as a Dynamic Map load every time the tab opens.
/// MapKit costs nothing and, for a map of pins you tap, is the same product.
///
/// Google keeps the one job it's genuinely better at — searching for places —
/// so the pins themselves still come from Google's data. Only the basemap
/// under them changed.
struct AppleMapView: UIViewRepresentable {
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
    /// Phoebe, 16 Sept: "I have filtered by restaurant, but still other types
    /// of pins are coming up". They were all restaurants — but a place tagged
    /// "Bar, Restaurant" is drawn in its FIRST sub-category's colour, and
    /// the chips double as the colour key, so a filtered map looked unfiltered.
    /// While a filter is on, every pin is drawn in that filter's colour: they
    /// all match it, and the colour then says why the pin is there.
    var highlightGenre: String? = nil
    /// Bumped whenever the camera should frame every pin currently shown —
    /// following a trip, so all its stops are on screen at once rather than
    /// wherever the map happened to be sitting.
    var fitToPlacesNonce: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Coordinator.pinReuseId
        )

        mapView.setRegion(
            MKCoordinateRegion(
                center: center ?? CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
                latitudinalMeters: radiusMeters * 2,
                longitudinalMeters: radiusMeters * 2
            ),
            animated: false
        )

        // MKMapView has no built-in "my location" button the way GMSMapView
        // does, so it gets Apple's own tracking control, placed clear of the
        // floating header above it.
        let tracking = MKUserTrackingButton(mapView: mapView)
        tracking.translatesAutoresizingMaskIntoConstraints = false
        tracking.backgroundColor = UIColor(RexColor.card)
        tracking.layer.cornerRadius = 8
        tracking.layer.borderWidth = 1
        tracking.layer.borderColor = UIColor(RexColor.border).cgColor
        tracking.clipsToBounds = true
        mapView.addSubview(tracking)
        NSLayoutConstraint.activate([
            tracking.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -12),
            tracking.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 244),
            tracking.widthAnchor.constraint(equalToConstant: 40),
            tracking.heightAnchor.constraint(equalToConstant: 40),
        ])
        // The compass would otherwise sit under the floating header too.
        mapView.layoutMargins = UIEdgeInsets(top: 244, left: 0, bottom: 0, right: 0)

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.45
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Only rebuild annotations when the set of places actually changes —
        // clearing on every SwiftUI update makes the map flicker.
        let ids = places.map(\.id).joined(separator: ",") + "|" + (highlightGenre ?? "")
        if context.coordinator.renderedIds != ids {
            mapView.removeAnnotations(mapView.annotations.filter { $0 is RexPlaceAnnotation })
            context.coordinator.markersById.removeAll()
            var annotations: [RexPlaceAnnotation] = []
            for place in places {
                guard let lat = place.lat, let lng = place.lng else { continue }
                annotations.append(RexPlaceAnnotation(
                    id: place.id,
                    title: place.title,
                    subtitle: place.recommenderSummary,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    tint: markerColor(for: place)
                ))
                context.coordinator.markersById[place.id] = place
            }
            mapView.addAnnotations(annotations)
            context.coordinator.renderedIds = ids
        }

        if let center, !context.coordinator.didCenter {
            mapView.setRegion(
                MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: radiusMeters * 2,
                    longitudinalMeters: radiusMeters * 2
                ),
                animated: true
            )
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
                mapView.setRegion(
                    MKCoordinateRegion(center: coords[0], latitudinalMeters: 3_000, longitudinalMeters: 3_000),
                    animated: true
                )
                context.coordinator.lastFitNonce = fitToPlacesNonce
            } else if coords.count > 1 {
                var rect = MKMapRect.null
                for coord in coords {
                    let point = MKMapPoint(coord)
                    rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                }
                // Generous at the top: the map's header (area name, the
                // "Following" bar and two rows of filter chips) floats over
                // the top ~230pt, and a pin framed under it is as good as
                // missing. Bottom clears the tab bar and the + button.
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 250, left: 50, bottom: 130, right: 50),
                    animated: true
                )
                context.coordinator.lastFitNonce = fitToPlacesNonce
            }
        }

        if let focusRequest, focusRequest != context.coordinator.lastFocusRequest,
           let place = places.first(where: { $0.id == focusRequest.itemId }),
           let lat = place.lat, let lng = place.lng {
            // Tighter than the general area radius — this is "show me this
            // one place", not "show me the neighbourhood".
            mapView.setRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    latitudinalMeters: 1_600,
                    longitudinalMeters: 1_600
                ),
                animated: true
            )
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
        if let highlightGenre {
            return UIColor(rexSubcategoryColor(
                genre: highlightGenre == "Event" ? nil : highlightGenre,
                type: highlightGenre == "Event" ? "event" : "place"
            ))
        }
        return UIColor(rexSubcategoryColor(genre: place.genre, type: place.type))
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let pinReuseId = "rex.place"

        var parent: AppleMapView
        var markersById: [String: MapPlace] = [:]
        var renderedIds = ""
        var didCenter = false
        var lastFocusRequest: MapFocusRequest?
        var lastFitNonce = 0

        init(_ parent: AppleMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let place = annotation as? RexPlaceAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.pinReuseId,
                for: annotation
            ) as? MKMarkerAnnotationView
            view?.markerTintColor = place.tint
            view?.glyphImage = nil
            view?.glyphText = nil
            // The callout is REX's own sheet, not MapKit's bubble — selecting
            // is what opens it, so the built-in callout would be a second,
            // worse version of the same thing.
            view?.canShowCallout = false
            // MapKit prints the title under the marker by default, which
            // Google didn't. On a city with thirty pins in it that's thirty
            // overlapping labels — and tapping already opens a sheet with the
            // name at the top. The title stays set for VoiceOver.
            view?.titleVisibility = .hidden
            view?.subtitleVisibility = .hidden
            view?.displayPriority = .required
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? RexPlaceAnnotation,
                  let place = markersById[annotation.id] else { return }
            // Deselect so tapping the same pin twice works — MapKit otherwise
            // treats the second tap as a no-op on an already-selected pin.
            mapView.deselectAnnotation(view.annotation, animated: false)
            parent.onSelect(place)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            parent.onLongPress?(mapView.convert(point, toCoordinateFrom: mapView))
        }
    }
}

/// One pin. Carries the item id so a tap can find its way back to the
/// MapPlace it came from, and its own colour so the sub-category key works.
final class RexPlaceAnnotation: NSObject, MKAnnotation {
    let id: String
    let title: String?
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
    let tint: UIColor

    init(id: String, title: String?, subtitle: String?, coordinate: CLLocationCoordinate2D, tint: UIColor) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.tint = tint
    }
}
