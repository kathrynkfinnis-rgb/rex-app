import SwiftUI
import MapKit

/// Sept 29 — the maps cost review.
///
/// Every place and trip card in the feed drew its tile from Google's Static
/// Maps API: one billed request per card, per scroll, at $2 per thousand with
/// 10,000 free a month. It was the highest-volume Google SKU REX had by a wide
/// margin — the first one that would run out, at roughly fifty active users —
/// and the least necessary, because a small locator tile with one pin on it is
/// a job Apple does on the device for nothing.
///
/// MKMapSnapshotter renders the same picture locally. No network call, no key,
/// no quota, no per-tile charge, and it keeps working if the Google key is ever
/// wrong. Google stays where it earns its money: place search, where its data
/// is genuinely better and there's no real alternative.
///
/// Two things this has to get right that a URL got for free — caching, so
/// scrolling back doesn't re-render, and a concurrency limit, because
/// MKMapSnapshotter is real work and a LazyVStack will happily ask for twenty
/// at once.
enum RexMapSnapshot {

    // MARK: - Cache

    /// Keyed on what the picture actually depends on. Coordinates are rounded
    /// to about a metre, which is far finer than a tile can show and stops
    /// floating-point noise from missing the cache.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Roughly 60 tiles at typical feed sizes. Bigger than any one scroll,
        // small enough that iOS is never tempted to kill us over it.
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private static func key(_ coordinates: [CLLocationCoordinate2D], _ size: CGSize) -> NSString {
        let points = coordinates
            .map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }
            .joined(separator: ";")
        return "\(points)|\(Int(size.width))x\(Int(size.height))" as NSString
    }

    // MARK: - Throttle

    /// MKMapSnapshotter will accept every request you hand it and then thrash.
    /// Three at a time keeps a fast scroll responsive without leaving tiles
    /// blank for long.
    private actor Gate {
        private var running = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            if running < 3 {
                running += 1
                return
            }
            await withCheckedContinuation { waiting.append($0) }
        }

        func leave() {
            if let next = waiting.first {
                waiting.removeFirst()
                next.resume()
            } else {
                running -= 1
            }
        }
    }

    private static let gate = Gate()

    // MARK: - Rendering

    /// One pin, framed with some neighbourhood around it — the place tile.
    static func image(at coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        // ~1.6km top to bottom. Matches what the Google tile showed at its
        // fixed zoom 14, so the cards don't visibly change proportion.
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1_600,
            longitudinalMeters: 1_600
        )
        return await render(region: region, pins: [coordinate], size: size)
    }

    /// Every stop framed at once — the trip tile. Google's Static Maps fitted
    /// the viewport to the markers automatically; here that sum is ours.
    static func image(fitting coordinates: [CLLocationCoordinate2D], size: CGSize) async -> UIImage? {
        guard let region = region(fitting: coordinates) else { return nil }
        return await render(region: region, pins: coordinates, size: size)
    }

    /// The bounding box of every stop, with room around the edges so no pin
    /// sits half off the tile, and a floor so a trip whose stops are all on one
    /// street doesn't zoom to the pavement.
    private static func region(fitting coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        if coordinates.count == 1 {
            return MKCoordinateRegion(
                center: first,
                latitudinalMeters: 1_600,
                longitudinalMeters: 1_600
            )
        }

        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLng = min(minLng, coordinate.longitude)
            maxLng = max(maxLng, coordinate.longitude)
        }

        let centre = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        // 40% of headroom: a pin is drawn above its coordinate, so a stop at
        // the very top of the box would otherwise lose its head.
        let latitudeDelta = max((maxLat - minLat) * 1.4, 0.012)
        let longitudeDelta = max((maxLng - minLng) * 1.4, 0.012)
        return MKCoordinateRegion(
            center: centre,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private static func render(
        region: MKCoordinateRegion,
        pins: [CLLocationCoordinate2D],
        size: CGSize
    ) async -> UIImage? {
        guard size.width > 1, size.height > 1 else { return nil }

        let cacheKey = key(pins, size)
        if let cached = cache.object(forKey: cacheKey) { return cached }

        // MapKit sizes its labels for a map you can read at arm's length, not
        // for a 96pt strip on a card — at tile size a city name like "Lisbon"
        // came out big enough to swamp the picture, which Google's tiles never
        // did. Rendering the basemap at twice the size and drawing it down
        // halves the labels relative to the tile while keeping the same
        // framing. Pins are drawn afterwards at their proper size.
        let labelScale: CGFloat = 2

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: size.width * labelScale, height: size.height * labelScale)
        options.mapType = .standard
        options.showsBuildings = true
        options.pointOfInterestFilter = .includingAll
        // RexColor is a fixed light palette and the app pins itself to light
        // mode (see AppDelegate) — the tile has to match the card it sits on,
        // not the phone's setting.
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        await gate.enter()
        defer { Task { await gate.leave() } }

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }

        let image = draw(pins: pins, on: snapshot, size: size, scale: labelScale)
        cache.setObject(image, forKey: cacheKey, cost: Int(size.width * size.height * 4))
        return image
    }

    /// Snapshots come back without annotations — MapKit hands you the basemap
    /// and a coordinate-to-point function, and the markers are yours to draw.
    private static func draw(
        pins: [CLLocationCoordinate2D],
        on snapshot: MKMapSnapshotter.Snapshot,
        size: CGSize,
        scale: CGFloat
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Drawn into the smaller canvas, which is what shrinks the labels.
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))

            let cg = context.cgContext
            let fill = UIColor(RexColor.primary)

            for pin in pins {
                // snapshot.point is in the oversized canvas's coordinates.
                let raw = snapshot.point(for: pin)
                let point = CGPoint(x: raw.x / scale, y: raw.y / scale)
                // Off the edge of the tile entirely — skip rather than draw a
                // half-pin clinging to the border.
                guard point.x > -20, point.y > -20,
                      point.x < size.width + 20, point.y < size.height + 20 else { continue }
                drawPin(at: point, in: cg, color: fill)
            }
        }
    }

    /// The same teardrop Google drew, so the cards look like they always did:
    /// a filled circle with a white ring, tapering to a point at the
    /// coordinate itself.
    private static func drawPin(at point: CGPoint, in context: CGContext, color: UIColor) {
        let radius: CGFloat = 7
        let height: CGFloat = 22
        let centre = CGPoint(x: point.x, y: point.y - height + radius)

        // UIKit angles run clockwise on screen from the positive x axis
        // (because y points down), so the left shoulder is 135° and the right
        // is 45°, and sweeping *clockwise* from 135° carries the arc up over
        // the top of the head rather than down through the tail.
        let path = UIBezierPath()
        path.addArc(
            withCenter: centre,
            radius: radius,
            startAngle: .pi * 0.75,
            endAngle: .pi * 0.25,
            clockwise: true
        )
        path.addLine(to: point)
        path.close()

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 2.5,
                          color: UIColor.black.withAlphaComponent(0.35).cgColor)
        color.setFill()
        path.fill()
        context.restoreGState()

        UIColor.white.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        // A small light centre, so a cluster of pins still reads as several
        // rather than one green blob.
        UIColor.white.withAlphaComponent(0.9).setFill()
        UIBezierPath(arcCenter: centre, radius: 2.4, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
    }
}

/// The SwiftUI wrapper both map tiles draw through. Sizes itself from the
/// layout, then renders at exactly that size — no guessing, and no stretched
/// picture on an iPad or a rotated phone.
struct RexMapSnapshotView: View {
    /// Every pin to show. One for a place, all its stops for a trip.
    let coordinates: [CLLocationCoordinate2D]
    var height: CGFloat

    @State private var image: UIImage?
    @State private var renderedFor: String?

    var body: some View {
        // Same box-first layout the Google version used, for the same reason:
        // let the box decide the width, and hang the picture off it, so a
        // .fill image can never widen the card.
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            placeholder
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .task(id: signature(for: geometry.size)) {
                        await render(size: geometry.size)
                    }
                }
            }
            .clipped()
    }

    private var placeholder: some View {
        RexColor.muted.overlay(
            Image(systemName: "map")
                .font(.system(size: 20))
                .foregroundStyle(RexColor.mutedForeground)
        )
    }

    /// Re-render only when the pins or the box actually change — not on every
    /// SwiftUI pass.
    private func signature(for size: CGSize) -> String {
        let points = coordinates
            .map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) }
            .joined(separator: ";")
        return "\(points)|\(Int(size.width))x\(Int(size.height))"
    }

    private func render(size: CGSize) async {
        guard !coordinates.isEmpty, size.width > 1, size.height > 1 else { return }
        let rendered = coordinates.count == 1
            ? await RexMapSnapshot.image(at: coordinates[0], size: size)
            : await RexMapSnapshot.image(fitting: coordinates, size: size)
        guard !Task.isCancelled else { return }
        image = rendered
    }
}
