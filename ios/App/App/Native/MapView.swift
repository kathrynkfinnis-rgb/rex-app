import SwiftUI
import MapKit
import CoreLocation

/// v1 scope: pins for places/events with coordinates, colored by category (decided:
/// category not person), one consolidated pin per place (guaranteed by the `!inner` join —
/// see fetchMapPlaces). Tapping a pin shows a summary sheet with the decided wording:
/// the single recommender's name, or "Rex'd by several friends" if more than one.
/// Skips: European-bias search tuning, Google star import, world-view/deleted-pin bugs
/// (those are web-app-specific per task #22) — this is the native map from scratch.
struct RexMapView: View {
    @State private var places: [MapPlace] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedPlace: MapPlace?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var didCenterOnUser = false

    var body: some View {
        ZStack {
            if isLoading {
                RexColor.background.ignoresSafeArea()
                ProgressView()
            } else if let errorMessage {
                RexColor.background.ignoresSafeArea()
                errorState(errorMessage)
            } else {
                Map(position: $cameraPosition, selection: .constant(nil)) {
                    ForEach(places) { place in
                        if let lat = place.lat, let lng = place.lng {
                            Annotation(place.title, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                                pin(for: place)
                                    .onTapGesture { selectedPlace = place }
                            }
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Map")
        .task {
            async let placesTask: () = load()
            async let locationTask: () = centerOnUserLocation()
            _ = await (placesTask, locationTask)
        }
        .sheet(item: $selectedPlace) { place in
            placeSummarySheet(place)
                .presentationDetents([.height(220)])
        }
    }

    private func pin(for place: MapPlace) -> some View {
        let category = RexCategory(rawType: place.type)
        return ZStack {
            Circle()
                .fill(category == .event ? RexColor.accent : RexColor.primary)
                .frame(width: 30, height: 30)
            Image(systemName: category.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            places = try await RexAPI.shared.fetchMapPlaces()
            // Only use "fit all pins" as a fallback — a successful user-location fix (below,
            // running concurrently) takes priority per the 10-mile-radius-from-me request.
            if !didCenterOnUser { fitCamera(to: places) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Centers on the user's current location with a ~10 mile radius. Falls back to
    /// "fit all pins" (set in load(), above) if permission is denied or location can't
    /// be resolved within a few seconds — never blocks the map from showing.
    private func centerOnUserLocation() async {
        let manager = CLLocationManager()
        manager.requestWhenInUseAuthorization()

        guard let location = await withTaskGroup(of: CLLocation?.self, returning: CLLocation?.self, body: { group in
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
        }) else { return }

        let milesToMeters = 1609.34
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 10 * milesToMeters * 2,
            longitudinalMeters: 10 * milesToMeters * 2
        )
        didCenterOnUser = true
        cameraPosition = .region(region)
    }

    private func fitCamera(to places: [MapPlace]) {
        let coords = places.compactMap { place -> CLLocationCoordinate2D? in
            guard let lat = place.lat, let lng = place.lng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        guard !coords.isEmpty else { return }
        if coords.count == 1 {
            cameraPosition = .region(MKCoordinateRegion(center: coords[0], latitudinalMeters: 4000, longitudinalMeters: 4000))
            return
        }
        let lats = coords.map { $0.latitude }
        let lngs = coords.map { $0.longitude }
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.05),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.4, 0.05)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    @ViewBuilder
    private func placeSummarySheet(_ place: MapPlace) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 3) {
                    Image(systemName: RexCategory(rawType: place.type).symbol).font(.system(size: 9))
                    Text(RexCategory(rawType: place.type).label.uppercased()).font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(RexColor.primary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RexColor.primary.opacity(0.1))
                .clipShape(Capsule())

                Text(place.title).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(RexColor.foreground)
                if let address = place.address, !address.isEmpty {
                    Text(address).font(.system(size: 13)).foregroundStyle(RexColor.mutedForeground)
                }

                HStack(spacing: 6) {
                    Image(systemName: "crown.fill").font(.system(size: 12)).foregroundStyle(RexColor.primary)
                    Text(String(format: "%.1f", place.averageRating)).font(.system(size: 14, weight: .semibold))
                    Text("/10").font(.system(size: 12)).foregroundStyle(RexColor.mutedForeground)
                    Text("· \(place.recommenderSummary)").font(.system(size: 13)).foregroundStyle(RexColor.mutedForeground)
                }
                .padding(.top, 2)

                NavigationLink(value: place.id) {
                    Text("View details").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .frame(height: 44)
                .background(RexColor.primary)
                .foregroundStyle(RexColor.primaryForeground)
                .clipShape(Capsule())
                .padding(.top, 4)

                Spacer()
            }
            .padding(20)
            .background(RexColor.background.ignoresSafeArea())
            .navigationDestination(for: String.self) { itemId in
                ItemDetailView(itemId: itemId)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(RexColor.destructive)
            Text(message).font(.footnote).foregroundStyle(RexColor.mutedForeground).multilineTextAlignment(.center)
            Button("Retry") { Task { await load() } }.font(.footnote.weight(.semibold)).foregroundStyle(RexColor.primary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

extension MapPlace: Equatable {
    static func == (lhs: MapPlace, rhs: MapPlace) -> Bool { lhs.id == rhs.id }
}
