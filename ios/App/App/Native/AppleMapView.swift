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
    /// Oct 14 — "these pins are not separating", "still have to zoom in way
    /// too much." Called instead of zooming when a cluster's members sit on
    /// top of each other, where zooming can never help.
    var onSelectMany: ([MapPlace]) -> Void = { _ in }
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
    /// Oct 4 — "on the map, if you're looking at a particular country, a
    /// bubble comes up with any trips inputted for that country." The view
    /// needs to know what is on screen to answer that, and nothing reported it
    /// before. Called as the camera settles rather than continuously — see the
    /// delegate, which fires on every frame of a pinch.
    var onRegionChange: ((MKCoordinateRegion) -> Void)? = nil
    /// Oct 5 — branches of a chain somebody rates that nobody has been to.
    /// Kept separate from `places` rather than folded in, because they are a
    /// different kind of claim and the moment they share a list something
    /// downstream will treat one as the other.
    var unvisitedBranches: [MapPlace] = []
    /// Bumped whenever the camera should frame every pin currently shown —
    /// following a trip, so all its stops are on screen at once rather than
    /// wherever the map happened to be sitting.
    var fitToPlacesNonce: Int = 0

    /// Oct 2 — "the new map seems to have deleted lots of stuff, missing many
    /// pins". Nothing was deleted: this was 2,200m, which is a couple of
    /// streets, so the map opened on a letterbox and every pin more than a
    /// few minutes' walk away was simply off-screen. Yikou Cafe, the reported
    /// example, sits 1.5km south of where the camera landed.
    ///
    /// The previous value framed twenty miles and was genuinely too far out.
    /// Seven kilometres is the honest middle: your own area, a borough's worth
    /// of pins in frame, and nothing hidden behind the edge of the screen.
    static let openingSpanMeters: CLLocationDistance = 7_000
    /// Below this span the pins are far enough apart to carry an icon; above
    /// it they would be a wall of overlapping glyphs, so colour alone does the
    /// work. "Colourful pins on a big view, icons when you zoom in." Set
    /// inside the opening span so one pinch in brings the icons up.
    static let glyphSpanMeters: CLLocationDistance = 5_000

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.register(
            RexPlaceAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: Coordinator.pinReuseId
        )
        // Oct 2 — "I still can't see Yikou (and lots of others) even when I'm
        // right on the place."
        //
        // The pin was never missing from the data: Yikou has two published
        // recommendations and the map had all 973 places in hand. MapKit was
        // declining to draw it. Unlike Google Maps, which drew every marker
        // it was given and let them overlap, MapKit declutters — where
        // annotations collide it picks one and silently drops the rest, which
        // on a city with a thousand pins means whole streets of them vanish.
        //
        // Clustering is the fix, and the better behaviour anyway: colliding
        // pins now become one bubble with a count, so nothing is ever hidden
        // — it's either a pin or a number you can tap into.
        mapView.register(
            RexClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )

        // Oct 1 — "when we click on the map make it more zoomed in to our
        // location". radiusMeters is how far out we FETCH (ten miles); it was
        // also being used to frame the map, so the first thing you saw was a
        // twenty-mile square with your street invisible in the middle.
        mapView.setRegion(
            MKCoordinateRegion(
                center: center ?? CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
                latitudinalMeters: Self.openingSpanMeters,
                longitudinalMeters: Self.openingSpanMeters
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
        let ids = places.map(\.id).joined(separator: ",") + "|"
            + unvisitedBranches.map(\.id).joined(separator: ",") + "|" + (highlightGenre ?? "")
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
                    tint: markerColor(for: place),
                    symbol: rexSubcategorySymbol(genre: place.genre, type: place.type)
                ))
                context.coordinator.markersById[place.id] = place
            }
            for branch in unvisitedBranches {
                guard let lat = branch.lat, let lng = branch.lng else { continue }
                annotations.append(RexPlaceAnnotation(
                    id: branch.id,
                    title: branch.title,
                    subtitle: "Nobody's been to this one",
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    tint: markerColor(for: branch),
                    symbol: rexSubcategorySymbol(genre: branch.genre, type: branch.type),
                    isUnvisitedBranch: true
                ))
                context.coordinator.markersById[branch.id] = branch
            }
            mapView.addAnnotations(annotations)
            context.coordinator.renderedIds = ids
        }

        if let center, !context.coordinator.didCenter {
            mapView.setRegion(
                MKCoordinateRegion(
                    center: center,
                    latitudinalMeters: Self.openingSpanMeters,
                    longitudinalMeters: Self.openingSpanMeters
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
        /// Whether the map is currently close enough in to draw icons.
        var showGlyphs = true

        static let ghostReuseId = "rex.ghost"
        private static var ghostCache: [UIColor: UIImage] = [:]

        /// A dashed ring in the chain's colour, on nothing. Small on purpose:
        /// it should read as a note on the map rather than compete with the
        /// pins for places somebody has actually been to.
        /// How much room a pin claims when MapKit works out what overlaps.
        /// Smaller means things separate at a lower zoom; too small and pins
        /// genuinely on top of each other stop merging and print over one
        /// another, which is the problem clustering exists to solve.
        ///
        /// The balloon's own width is about 40. 26 on 8 October, 18 now: what
        /// stopped it going further then was that the frame is also the tap
        /// target, and RexPlaceAnnotationView has since separated those, so a
        /// finger still gets its 44 whatever this says. Two pins now split
        /// roughly half a zoom step sooner than at 26, and about a step and a
        /// half sooner than an untouched balloon.
        static let pinCollisionSize: CGFloat = 18

        static func ghostImage(tint: UIColor) -> UIImage {
            if let cached = ghostCache[tint] { return cached }
            let size = CGSize(width: 18, height: 18)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2.5, dy: 2.5)
                let path = UIBezierPath(ovalIn: rect)
                UIColor.white.withAlphaComponent(0.85).setFill()
                path.fill()
                path.lineWidth = 2
                path.setLineDash([3, 2.5], count: 2, phase: 0)
                tint.setStroke()
                path.stroke()
                _ = context
            }
            ghostCache[tint] = image
            return image
        }

        init(_ parent: AppleMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let place = annotation as? RexPlaceAnnotation else { return nil }

            // Oct 5 — "a branch nobody's been to should read as 'here, but
            // nobody vouches for it' at a glance" — and the first attempt
            // didn't. It was the same teardrop marker in a paler colour, which
            // on a light basemap reads as a pin that hasn't finished loading
            // rather than a different kind of thing.
            //
            // A different shape says it instead: a small dashed ring, which
            // nothing else on the map uses. Shape carries at a glance in a way
            // tint never does, and it keeps working for anyone who can't
            // separate the two colours.
            if place.isUnvisitedBranch {
                let ring = mapView.dequeueReusableAnnotationView(
                    withIdentifier: Self.ghostReuseId
                ) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: Self.ghostReuseId)
                ring.annotation = annotation
                ring.image = Self.ghostImage(tint: place.tint)
                ring.canShowCallout = false
                // Always loses a collision with a real recommendation.
                ring.displayPriority = .defaultLow
                ring.collisionMode = .circle
                return ring
            }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.pinReuseId,
                for: annotation
            ) as? RexPlaceAnnotationView
            view?.markerTintColor = place.tint
            view?.glyphTintColor = .white
            view?.glyphText = nil
            view?.glyphImage = showGlyphs
                ? UIImage(systemName: place.symbol)
                : nil
            // Oct 8 — "can we change distances for expansion? You have to zoom
            // in too much to separate a 2."
            //
            // MapKit decides what collides, and so what clusters, from the
            // annotation view's own frame. A marker balloon is about 40pt
            // across, so two pins merge whenever they are within roughly that
            // on screen — which at street level is most of a block, and is why
            // Londis and Scotch Meats sat under one bubble while plainly being
            // two different shops.
            //
            // Shrinking the collision box separates them sooner. The balloon
            // still draws at its own size; only what MapKit measures for
            // collision changes, so the map looks the same and simply gives up
            // hiding things earlier. See pinCollisionSize for where it sits.
            view?.frame.size = CGSize(width: Self.pinCollisionSize, height: Self.pinCollisionSize)
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
            // Everything clusters together: a café hidden behind a pub helps
            // nobody, and one bubble saying "7" is honest about what's there.
            view?.clusteringIdentifier = "rex"
            view?.displayPriority = .required
            view?.collisionMode = .circle
            return view
        }

        /// Below this, two pins are the same pin for any practical purpose.
        /// MapKit's maximum useful zoom shows roughly 50 metres across a
        /// phone, so anything inside 25 would still be touching at the bottom
        /// of the zoom and the bubble would never open.
        static let inseparableMetres: CLLocationDistance = 25

        /// How far apart the furthest two members of a cluster are.
        private func spread(of members: [MKAnnotation]) -> CLLocationDistance {
            guard let first = members.first else { return 0 }
            var worst: CLLocationDistance = 0
            let origin = CLLocation(latitude: first.coordinate.latitude, longitude: first.coordinate.longitude)
            for member in members.dropFirst() {
                let point = CLLocation(latitude: member.coordinate.latitude, longitude: member.coordinate.longitude)
                worst = max(worst, origin.distance(from: point))
            }
            return worst
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Tapping a cluster zooms into it rather than picking one of its
            // pins arbitrarily — the whole point is that nothing is hidden.
            if let cluster = view.annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)

                // Oct 14 — "these pins are not separating. Still have to zoom
                // in way too much."
                //
                // Two different places at the same address — a restaurant and
                // the bar upstairs, or the same venue entered twice — are at
                // the same point on a map, and no zoom level separates points
                // that are the same point. Every previous attempt at this
                // tuned the collision distance, which is the wrong dial: at
                // nought metres apart they collide at any setting.
                //
                // So a cluster that cannot come apart stops pretending it can.
                // Zooming into a zero-width rect takes the map to its limit and
                // leaves the bubble exactly where it was, which is what she has
                // been doing over and over. This opens the list instead.
                let members = cluster.memberAnnotations.compactMap { member -> MapPlace? in
                    (member as? RexPlaceAnnotation).flatMap { markersById[$0.id] }
                }
                if spread(of: cluster.memberAnnotations) < Self.inseparableMetres, members.count > 1 {
                    parent.onSelectMany(members)
                    return
                }

                // Oct 16 — "if you press a number of compressed pins on the
                // map, the map zooms out but in fact you want it to zoom in."
                //
                // The union of a tight cluster is a rect a few tens of metres
                // across, and setVisibleMapRect was being handed that along
                // with 440 points of vertical padding. Fitting a tiny rect
                // inside a viewport shrunk by that much makes MapKit solve for
                // a *wider* region than the one you were already looking at —
                // so tapping a knot of pins pulled the camera back, which is
                // the opposite of what the tap means.
                //
                // Work in regions rather than rects so the span is something we
                // can reason about, floor it so a near-degenerate cluster still
                // gets a sensible frame, and never return a span wider than the
                // current one: a tap on a cluster means "closer", always.
                var rect = MKMapRect.null
                for member in cluster.memberAnnotations {
                    let point = MKMapPoint(member.coordinate)
                    rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                }

                var target = MKCoordinateRegion(rect)
                // Roughly 150m across at the tightest, so the pins separate
                // without the map slamming into its maximum zoom.
                let minimumSpan = 0.0015
                target.span.latitudeDelta = max(target.span.latitudeDelta * 2.2, minimumSpan)
                target.span.longitudeDelta = max(target.span.longitudeDelta * 2.2, minimumSpan)

                let current = mapView.region.span
                if target.span.latitudeDelta >= current.latitudeDelta {
                    // Whatever the arithmetic says, going out is wrong here.
                    target.span.latitudeDelta = current.latitudeDelta / 2
                    target.span.longitudeDelta = current.longitudeDelta / 2
                }

                mapView.setRegion(mapView.regionThatFits(target), animated: true)
                return
            }
            guard let annotation = view.annotation as? RexPlaceAnnotation,
                  let place = markersById[annotation.id] else { return }
            // Deselect so tapping the same pin twice works — MapKit otherwise
            // treats the second tap as a no-op on an already-selected pin.
            mapView.deselectAnnotation(view.annotation, animated: false)
            parent.onSelect(place)
        }

        /// Flip the glyphs on or off as the map is zoomed, and only redraw
        /// when the answer actually changes — this fires continuously while
        /// someone pinches.
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            reportRegion(mapView)
            let span = mapView.region.span.latitudeDelta * 111_000
            let shouldShow = span <= AppleMapView.glyphSpanMeters
            guard shouldShow != showGlyphs else { return }
            showGlyphs = shouldShow
            for annotation in mapView.annotations {
                guard let place = annotation as? RexPlaceAnnotation,
                      let view = mapView.view(for: annotation) as? MKMarkerAnnotationView
                else { continue }
                view.glyphImage = shouldShow ? UIImage(systemName: place.symbol) : nil
            }
        }

        /// Coalesced: this delegate method fires continuously while someone
        /// pans or pinches, and recomputing which trips are on screen at sixty
        /// hertz would be absurd for something that only changes when the
        /// camera stops.
        private var regionWork: DispatchWorkItem?

        private func reportRegion(_ mapView: MKMapView) {
            guard let report = parent.onRegionChange else { return }
            regionWork?.cancel()
            let region = mapView.region
            let work = DispatchWorkItem { report(region) }
            regionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
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
    /// Oct 1 — shown only when the map is zoomed in far enough to read it;
    /// see Coordinator.showGlyphs.
    let symbol: String
    /// Oct 5 — another branch of a chain your friends rate, which nobody has
    /// actually been to. Drawn hollow, because it is information rather than
    /// a recommendation and the map should never blur the two.
    let isUnvisitedBranch: Bool

    init(
        id: String, title: String?, subtitle: String?,
        coordinate: CLLocationCoordinate2D, tint: UIColor, symbol: String,
        isUnvisitedBranch: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.tint = tint
        self.symbol = symbol
        self.isUnvisitedBranch = isUnvisitedBranch
    }
}

/// A place pin whose collision box is small but whose tap target is not.
///
/// Oct 12 — "you don't have to zoom in so far to split out the grouped pins."
/// MapKit measures collision from the view's frame, and UIKit measures taps
/// from the same frame, so every step that separates pins sooner also makes
/// them harder to hit. Below about 30pt that stops being a fair trade: a pin
/// you can see and can't reliably tap is worse than one that clustered.
///
/// Overriding `point(inside:)` breaks the two apart. MapKit keeps measuring
/// the small frame; a finger still gets 44pt, which is Apple's own minimum and
/// roughly what the balloon looks like anyway.
final class RexPlaceAnnotationView: MKMarkerAnnotationView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let target: CGFloat = 44
        return bounds.insetBy(
            dx: (bounds.width - target) / 2,
            dy: (bounds.height - target) / 2
        ).contains(point)
    }
}

/// What a group of colliding pins looks like: REX green, the count, and the
/// same shape language as a single pin so the map reads as one system.
///
/// Oct 2 — introduced because MapKit hides annotations that collide, which is
/// how pins "disappeared" from a map that had them all loaded. A cluster is
/// the honest alternative to hiding: tap it and it opens out.
final class RexClusterAnnotationView: MKAnnotationView {
    /// How much room the bubble claims when MapKit works out what overlaps.
    /// Kept just above the pins' own box so a cluster never outlives the pins
    /// inside it.
    static let collisionSize: CGFloat = 19
    /// What the bubble actually looks like. Deliberately bigger than the
    /// collision box — see `bubble`.
    private static let artworkSize: CGFloat = 36

    /// Oct 12 — "we would still like to change the map so you don't have to
    /// zoom in so far to split out the grouped pins."
    ///
    /// On 8 October I set this view's frame to 28 in `init` and said the
    /// cluster now matched the pins. It did not. Assigning `image` on an
    /// MKAnnotationView resets `bounds` to the image's size, and the image is
    /// assigned in `prepareForDisplay`, which runs after `init` — so every
    /// bubble went back to colliding at 36 while the pins collided at 26. The
    /// fix I described was overwritten by the next line of my own code, which
    /// is why a "2" still held together after its two pins had separated.
    ///
    /// The artwork therefore lives in a subview instead of in `image`. The
    /// view's own bounds stay at the collision size and nothing resets them;
    /// the bubble draws at full size outside those bounds, because annotation
    /// views do not clip. Collision and appearance are now two separate
    /// numbers, which is what they always needed to be.
    private let bubble = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        displayPriority = .required
        collisionMode = .circle
        frame = CGRect(x: 0, y: 0, width: Self.collisionSize, height: Self.collisionSize)
        centerOffset = CGPoint(x: 0, y: -Self.collisionSize / 2)
        bubble.frame = CGRect(x: 0, y: 0, width: Self.artworkSize, height: Self.artworkSize)
        bubble.center = CGPoint(x: Self.collisionSize / 2, y: Self.collisionSize / 2)
        bubble.autoresizingMask = [
            .flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin,
        ]
        addSubview(bubble)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The collision box is far smaller than a finger. Hit-testing normally
    /// stops at `bounds`, so shrinking it to separate pins sooner would also
    /// shrink the target you have to hit — the bubble would look tappable and
    /// mostly not be. This restores a full-sized target over the artwork.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let target = max(Self.artworkSize, 44)
        return bounds.insetBy(
            dx: (bounds.width - target) / 2,
            dy: (bounds.height - target) / 2
        ).contains(point)
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let count = cluster.memberAnnotations.count

        bubble.image = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36)).image { _ in
            UIColor(RexColor.primary).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 36, height: 36)).fill()
            UIColor.white.setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 34, height: 34))
            ring.lineWidth = 2
            ring.stroke()

            let text = count > 99 ? "99+" : "\(count)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: count > 99 ? 12 : 14, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (36 - size.width) / 2, y: (36 - size.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
