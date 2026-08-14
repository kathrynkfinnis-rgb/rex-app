import SwiftUI
import CoreLocation

/// Places and events on a Google map, matching the web app's basemap.
/// Opens centred on the user with a 10-mile radius; falls back to fitting the
/// pins when location isn't available.
struct RexMapView: View {
    @State private var places: [MapPlace] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedPlace: MapPlace?
    @State private var userCoordinate: CLLocationCoordinate2D?
    @State private var areaName: String?
    @State private var filter: RexCategory?
    /// Recommendation id of the trip we're following, if any.
    @State private var tripFilter: String?
    @State private var tripTitles: [String: String] = [:]
    @State private var openTrip: TripRoute?

    private static let milesToMeters = 1609.34
    private var radiusMeters: Double { 10 * Self.milesToMeters }

    private var visiblePlaces: [MapPlace] {
        var out = places
        // Following a trip shows only its stops, the way the web map does.
        if let tripFilter { out = out.filter { $0.tripIds.contains(tripFilter) } }
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
            } else {
                GoogleMapView(
                    places: visiblePlaces,
                    center: center,
                    radiusMeters: radiusMeters,
                    onSelect: { selectedPlace = $0 }
                )
                .ignoresSafeArea(edges: .bottom)
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
        .sheet(item: $selectedPlace) { place in
            placeSheet(place)
                // Compact by default; drag up when a place is on several trips.
                .presentationDetents([.height(260), .height(440)])
        }
        .navigationDestination(item: $openTrip) { TripDetailView(route: $0) }
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
            }

            if let tripFilter, let title = tripTitles[tripFilter] {
                HStack(spacing: RexSpacing.sm) {
                    Image(systemName: "suitcase.fill").font(.system(size: 11))
                    Text("Following \(title)")
                        .font(RexFont.text(13, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Button("Show all") { self.tripFilter = nil }
                        .font(RexFont.text(12, weight: .semibold))
                }
                .foregroundStyle(RexColor.primary)
                .padding(.horizontal, RexSpacing.sm + 2)
                .padding(.vertical, 7)
                .background(RexColor.badgeBackground)
                .clipShape(Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    chip("All", active: filter == nil) { filter = nil }
                    chip("Places", active: filter == .place) { filter = filter == .place ? nil : .place }
                    chip("Events", active: filter == .event) { filter = filter == .event ? nil : .event }
                }
            }
        }
        .padding(.horizontal, RexSpacing.lg)
        .padding(.vertical, RexSpacing.md)
        .background(
            RexColor.card.opacity(0.96)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(RexColor.border).frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
        )
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
        isLoading = true
        errorMessage = nil
        do {
            places = try await RexAPI.shared.fetchMapPlaces()
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
                                    tripFilter = trip.id
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
