import SwiftUI
import CoreLocation

/// Places and events on a Google map, matching the web app's basemap.
/// Opens centred on the user with a 10-mile radius; falls back to fitting the
/// pins when location isn't available.
struct RexMapView: View {
    /// Bumped by MainTabView every time this tab becomes active — TabView
    /// keeps tabs alive rather than recreating them, so without this a
    /// deleted item's pin would sit on the map until the app relaunched.
    var refreshSignal: Int = 0
    /// #133 "view on map" — set by MainTabView when a card's map icon is
    /// tapped elsewhere in the app. Carries its own nonce so tapping the
    /// same card's icon twice in a row still re-centres.
    var focusRequest: MapFocusRequest? = nil

    @State private var places: [MapPlace] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedPlace: MapPlace?
    @State private var userCoordinate: CLLocationCoordinate2D?
    @State private var areaName: String?
    @State private var filter: RexCategory?
    /// Recommendation id of the trip we're following, if any.
    @State private var tripFilter: String?
    /// Set alongside tripFilter whenever we follow a trip, so the "Following
    /// X" banner doesn't depend on tripTitles having that trip in it (see
    /// focusedTripPlaces below for why that's no longer a safe assumption).
    @State private var followingTripTitle: String?
    @State private var tripTitles: [String: String] = [:]
    /// A followed trip's own stops, fetched directly rather than filtered
    /// out of `places` — that array is only the most-recently-added 200
    /// places overall, which was fine when the only way to follow a trip was
    /// tapping a chip built from that same sample. TripSearchView lets you
    /// pick any trip, so a followed trip needs a guaranteed-complete fetch.
    @State private var focusedTripPlaces: [MapPlace]?
    @State private var openTrip: TripRoute?
    @State private var showingTripSearch = false
    /// #106 — a list alongside the map, for when scanning names beats
    /// panning pins around, plus a sort the map itself has no use for.
    @State private var showingList = false
    @State private var sortMode: MapSortMode = .recent
    /// topBar floats over the map (by design — the map should still be
    /// visible/pannable underneath it), but the list needs to know its
    /// actual height to avoid starting underneath it. Measured rather than
    /// guessed since the bar's height changes (trip banner, sort row).
    @State private var topBarHeight: CGFloat = 160
    /// #167 — "add a Rex by finding a place on the map first": long-press
    /// drops a pin, reverse-geocodes it (same CLGeocoder already used for
    /// areaName below) into a real address, then opens Add a Rex prefilled.
    @State private var isResolvingLongPress = false
    @State private var pendingPlaceHit: RexSearchHit?
    @State private var longPressError: String?

    enum MapSortMode: String, CaseIterable {
        case recent = "Most recent"
        case mostRexd = "Most Rex'd"
    }

    /// fetchMapPlaces already orders by the item's created_at descending, so
    /// "most recent" is just the array's existing order — no extra fetch or
    /// model field needed. "Most Rex'd" sorts by how many recommendations
    /// are embedded per place, which is already fetched too.
    private var sortedVisiblePlaces: [MapPlace] {
        switch sortMode {
        case .recent: return visiblePlaces
        case .mostRexd: return visiblePlaces.sorted { $0.recommendations.count > $1.recommendations.count }
        }
    }

    private static let milesToMeters = 1609.34
    private var radiusMeters: Double { 10 * Self.milesToMeters }

    private var visiblePlaces: [MapPlace] {
        // Following a trip shows only its stops, the way the web map does —
        // from their own dedicated fetch, not filtered out of the general
        // sample (see focusedTripPlaces).
        var out = tripFilter != nil ? (focusedTripPlaces ?? []) : places
        if let filter { out = out.filter { RexCategory(rawType: $0.type) == filter } }
        return out
    }

    /// Centre on the user if we have them, otherwise the middle of the pins.
    private var center: CLLocationCoordinate2D? {
        if let userCoordinate { return userCoordinate }
        let coords = visiblePlaces.compactMap { p -> CLLocationCoordinate2D? in
            guard let lat = p.lat, let lng = p.lng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.latitude), lngs = coords.map(\.longitude)
        return CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            RexColor.background.ignoresSafeArea()

            if isLoading {
                ProgressView()
            } else if let errorMessage {
                errorState(errorMessage)
            } else if showingList {
                placesList
            } else {
                GoogleMapView(
                    places: visiblePlaces,
                    center: center,
                    radiusMeters: radiusMeters,
                    focusRequest: focusRequest,
                    onSelect: { selectedPlace = $0 },
                    onLongPress: { coordinate in Task { await resolveLongPress(coordinate) } }
                )
                .ignoresSafeArea(edges: .bottom)
            }

            if isResolvingLongPress {
                VStack(spacing: RexSpacing.sm) {
                    ProgressView().tint(.white)
                    Text("Finding this place…")
                        .font(RexFont.text(13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(RexSpacing.lg)
                .background(Color.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            }

            topBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            async let placesTask: () = load()
            async let locationTask: () = resolveLocation()
            _ = await (placesTask, locationTask)
        }
        .onChange(of: refreshSignal) { _, _ in
            // Not isLoading = true here — that would blank the map behind
            // the spinner every time you just glance at the tab. Places
            // swap in once the fresh fetch lands; nothing visible changes
            // if nothing actually changed server-side.
            Task { await load() }
        }
        // .task(id:) rather than .onChange — this needs to fire for
        // whatever focusRequest MainTabView already set *before* this view
        // first appeared (tapping a card's map icon switches tabs and sets
        // the request in the same action), not only for later changes.
        .task(id: focusRequest) { await focusOn(focusRequest) }
        .sheet(item: $selectedPlace) { place in
            placeSheet(place)
                // Compact by default; drag up when a place is on several trips.
                .presentationDetents([.height(260), .height(440)])
        }
        .navigationDestination(item: $openTrip) { TripDetailView(route: $0) }
        .sheet(isPresented: $showingTripSearch) {
            TripSearchView(onSelect: { id, title in followTrip(id: id, title: title) })
        }
        .sheet(item: $pendingPlaceHit) { hit in
            AddRexView(onDone: { pendingPlaceHit = nil; Task { await load() } }, initialPlaceHit: hit)
        }
        .alert("Couldn't find that place", isPresented: Binding(
            get: { longPressError != nil },
            set: { if !$0 { longPressError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(longPressError ?? "")
        }
    }

    /// Follows a trip on the map, fetching its stops directly rather than
    /// hoping they're already in `places` (see focusedTripPlaces).
    private func followTrip(id: String, title: String) {
        tripFilter = id
        followingTripTitle = title
        focusedTripPlaces = nil
        Task {
            focusedTripPlaces = (try? await RexAPI.shared.fetchMapPlaces(forTrip: id)) ?? []
        }
    }

    private func unfollowTrip() {
        tripFilter = nil
        followingTripTitle = nil
        focusedTripPlaces = nil
    }

    /// #133 "view on map" — jumps straight to one place regardless of
    /// whatever filter or followed trip the map was already showing, and
    /// pops its info sheet the same as tapping the pin directly would.
    private func focusOn(_ request: MapFocusRequest?) async {
        guard let request else { return }
        guard let place = try? await RexAPI.shared.fetchMapPlace(itemId: request.itemId) else { return }
        // A category filter or a followed trip could hide the very place
        // being jumped to — clear both so it's guaranteed visible.
        filter = nil
        if tripFilter != nil { unfollowTrip() }
        if let idx = places.firstIndex(where: { $0.id == place.id }) {
            places[idx] = place
        } else {
            places.append(place)
        }
        selectedPlace = place
    }

    /// Location indicator + category filters, floating over the map.
    private var topBar: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            HStack(spacing: RexSpacing.sm) {
                Image(systemName: "location.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(RexColor.primary)
                Text(areaName ?? "Places near you")
                    .font(RexFont.display(18, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Spacer()
                Text("\(visiblePlaces.count)")
                    .font(RexFont.text(12, weight: .semibold))
                    .foregroundStyle(RexColor.badgeForeground)
                    .padding(.horizontal, RexSpacing.sm)
                    .padding(.vertical, 3)
                    .background(RexColor.badgeBackground)
                    .clipShape(Capsule())

                Button {
                    withAnimation(.snappy) { showingList.toggle() }
                } label: {
                    Image(systemName: showingList ? "map" : "list.bullet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RexColor.primary)
                        .frame(width: 30, height: 30)
                        .background(RexColor.badgeBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingList ? "Show map" : "Show list")
            }

            if tripFilter != nil, let title = followingTripTitle {
                HStack(spacing: RexSpacing.sm) {
                    Image(systemName: "suitcase.fill").font(.system(size: 11))
                    Text("Following \(title)")
                        .font(RexFont.text(13, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Button("Show all") { unfollowTrip() }
                        .font(RexFont.text(12, weight: .semibold))
                }
                .foregroundStyle(RexColor.primary)
                .padding(.horizontal, RexSpacing.sm + 2)
                .padding(.vertical, 7)
                .background(RexColor.badgeBackground)
                .clipShape(Capsule())
            } else {
                // The trip chip row on the map itself doesn't scale once
                // there are many trips — this is the dedicated search/browse
                // screen instead.
                Button {
                    showingTripSearch = true
                } label: {
                    HStack(spacing: RexSpacing.sm) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11))
                        Text("Looking for a trip?")
                            .font(RexFont.text(13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(RexColor.mutedForeground)
                    .padding(.horizontal, RexSpacing.sm + 2)
                    .padding(.vertical, 7)
                    .background(RexColor.card)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(RexColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    chip("All", active: filter == nil) { filter = nil }
                    chip("Places", active: filter == .place) { filter = filter == .place ? nil : .place }
                    chip("Events", active: filter == .event) { filter = filter == .event ? nil : .event }
                }
            }

            if showingList {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RexSpacing.sm) {
                        ForEach(MapSortMode.allCases, id: \.self) { mode in
                            chip(mode.rawValue, active: sortMode == mode) { sortMode = mode }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, RexSpacing.lg)
        .padding(.vertical, RexSpacing.md)
        .background(
            GeometryReader { proxy in
                RexColor.card.opacity(0.96)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(RexColor.border).frame(height: 1)
                    }
                    .ignoresSafeArea(edges: .top)
                    .onAppear { topBarHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in topBarHeight = h }
            }
        )
    }

    private var placesList: some View {
        ScrollView {
            VStack(spacing: RexSpacing.md) {
                if sortedVisiblePlaces.isEmpty {
                    Text("Nothing here yet")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                        .padding(.top, RexSpacing.xxl)
                } else {
                    ForEach(sortedVisiblePlaces) { place in
                        Button { selectedPlace = place } label: {
                            listRow(place)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.top, topBarHeight + RexSpacing.md)
            .padding(.bottom, RexSpacing.xxxl)
        }
    }

    private func listRow(_ place: MapPlace) -> some View {
        HStack(spacing: RexSpacing.md) {
            Group {
                if let urlString = place.image_url, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            RexColor.muted
                        }
                    }
                } else {
                    RexColor.muted.overlay(
                        Image(systemName: RexCategory(rawType: place.type).symbol)
                            .foregroundStyle(RexColor.mutedForeground)
                    )
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(place.title)
                    .font(RexFont.text(15, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if place.recommendations.count == 1 {
                        RexRatingBadge(raw: place.recommendations[0].rating, compact: true)
                    } else {
                        RexRatingAverageBadge(ratings: place.recommendations.map { $0.rating })
                    }
                    Text("\u{00B7} \(place.recommenderSummary)")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: RexSpacing.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RexColor.mutedForeground)
        }
        .padding(RexSpacing.cardPadding)
        .rexCard()
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(RexFont.text(13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? RexColor.primaryForeground : RexColor.mutedForeground)
                .padding(.horizontal, RexSpacing.md)
                .padding(.vertical, 6)
                .background(active ? RexColor.primary : RexColor.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? RexColor.primary : RexColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        // Only the very first load shows the spinner-instead-of-map state —
        // a tab-return refresh (see refreshSignal) should swap places in
        // quietly, not blank the map you're already looking at.
        isLoading = places.isEmpty
        errorMessage = nil
        do {
            let recPlaces = try await RexAPI.shared.fetchMapPlaces()
            // #153 — wants live in a separate table with no recommendations
            // row at all, so they need their own fetch; merged here rather
            // than fought into fetchMapPlaces' own query (same reasoning as
            // fetchFeed's wants/blasts merge). Best-effort: a failure here
            // shouldn't blank the map that already loaded fine.
            let wantPlaces = (try? await RexAPI.shared.fetchMapWants()) ?? []
            var merged: [String: MapPlace] = [:]
            for place in recPlaces { merged[place.id] = place }
            for want in wantPlaces {
                if let existing = merged[want.id] {
                    // Already a real pin (someone's rated it) — fold the
                    // want in as another "recommendation" on it instead of a
                    // second pin, so the count/summary reflects both.
                    merged[want.id] = MapPlace(
                        id: existing.id, title: existing.title, subtitle: existing.subtitle, type: existing.type,
                        genre: existing.genre, address: existing.address, lat: existing.lat, lng: existing.lng,
                        image_url: existing.image_url, recommendations: existing.recommendations + want.recommendations
                    )
                } else {
                    merged[want.id] = want
                }
            }
            places = Array(merged.values)
            let tripIds = Array(Set(places.flatMap { $0.tripIds }))
            tripTitles = (try? await RexAPI.shared.fetchTripTitles(recommendationIds: tripIds)) ?? [:]
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Gets a location fix (races an 8s timeout so the map never hangs) and
    /// reverse-geocodes it into a place name for the header.
    private func resolveLocation() async {
        let manager = CLLocationManager()
        manager.requestWhenInUseAuthorization()

        let location: CLLocation? = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let loc = update.location { return loc }
                        if update.authorizationDenied || update.authorizationRestricted { return nil }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard let location else { return }
        userCoordinate = location.coordinate
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            areaName = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        }
    }

    /// #167 — reverse-geocodes a long-pressed point into a real address,
    /// then hands it to Add a Rex as a RexSearchHit, the same shape a
    /// picked Google Places result takes (see AddRexView's custom init).
    /// externalSource is its own tag rather than "google_places" — this is
    /// a CLGeocoder reverse-geocode, not an actual Google Place match, and
    /// createItem's (external_source, external_id) dedup lookup shouldn't
    /// conflate the two.
    private func resolveLongPress(_ coordinate: CLLocationCoordinate2D) async {
        isResolvingLongPress = true
        longPressError = nil
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        isResolvingLongPress = false
        guard let placemark else {
            longPressError = "Couldn't identify a place at that spot — try a different point, or add it manually instead."
            return
        }
        let name = placemark.name ?? placemark.thoroughfare ?? "Dropped pin"
        let address = [placemark.name, placemark.thoroughfare, placemark.locality, placemark.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { acc, part in if acc.last != part { acc.append(part) } }
            .joined(separator: ", ")
        pendingPlaceHit = RexSearchHit(
            externalId: "\(coordinate.latitude),\(coordinate.longitude)",
            externalSource: "map_long_press",
            title: name,
            subtitle: nil,
            imageURL: nil,
            genre: nil,
            address: address.isEmpty ? name : address,
            lat: coordinate.latitude,
            lng: coordinate.longitude,
            googleRating: nil,
            googleRatingCount: nil,
            productURL: nil
        )
    }

    @ViewBuilder
    private func placeSheet(_ place: MapPlace) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: RexSpacing.md) {
                HStack(spacing: 4) {
                    Image(systemName: RexCategory(rawType: place.type).symbol).font(.system(size: 9))
                    Text(RexCategory(rawType: place.type).label.uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                }
                .foregroundStyle(RexColor.badgeForeground)
                .padding(.horizontal, RexSpacing.sm).padding(.vertical, 3)
                .background(RexColor.badgeBackground)
                .clipShape(Capsule())

                Text(place.title)
                    .font(RexFont.display(22, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)

                if let address = place.address, !address.isEmpty {
                    Text(address)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.mutedForeground)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if place.recommendations.count == 1 {
                        RexRatingBadge(raw: place.recommendations[0].rating)
                    } else {
                        RexRatingAverageBadge(ratings: place.recommendations.map { $0.rating })
                    }
                    Text("· \(place.recommenderSummary)")
                        .font(RexFont.text(13)).foregroundStyle(RexColor.mutedForeground)
                }

                // A stop usually belongs to a trip — let people jump to the
                // whole itinerary, or follow it on the map.
                let trips = place.tripIds.compactMap { id in
                    tripTitles[id].map { (id: id, title: $0) }
                }
                if !trips.isEmpty {
                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Part of")
                            .font(RexFont.text(12, weight: .semibold))
                            .foregroundStyle(RexColor.mutedForeground)
                        ForEach(trips, id: \.id) { trip in
                            HStack(spacing: RexSpacing.sm) {
                                Button {
                                    selectedPlace = nil
                                    openTrip = TripRoute(recommendationId: trip.id, title: trip.title)
                                } label: {
                                    HStack(spacing: RexSpacing.sm) {
                                        Image(systemName: "suitcase")
                                            .font(.system(size: 13))
                                        Text(trip.title)
                                            .font(RexFont.text(14, weight: .medium))
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundStyle(RexColor.foreground)
                                    .padding(RexSpacing.md)
                                    .contentShape(Rectangle())
                                    .rexCard()
                                }
                                .buttonStyle(.plain)

                                Button {
                                    followTrip(id: trip.id, title: trip.title)
                                    selectedPlace = nil
                                } label: {
                                    Text("Map it")
                                        .font(RexFont.text(12, weight: .semibold))
                                        .foregroundStyle(RexColor.primary)
                                        .padding(.horizontal, RexSpacing.sm + 2)
                                        .padding(.vertical, 8)
                                        .overlay(Capsule().stroke(RexColor.primary.opacity(0.4), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, RexSpacing.sm)
                }

                NavigationLink(value: place.id) {
                    Text("View details")
                }
                .buttonStyle(RexPrimaryButtonStyle())

                Spacer()
            }
            .padding(RexSpacing.page)
            .background(RexColor.background.ignoresSafeArea())
            .navigationDestination(for: String.self) { ItemDetailView(itemId: $0) }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: RexSpacing.sm) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(RexFont.text(13)).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
        }
        .padding(RexSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

extension MapPlace: Equatable {
    static func == (lhs: MapPlace, rhs: MapPlace) -> Bool { lhs.id == rhs.id }
}
