import SwiftUI

/// AsyncImage, except it also handles Google Places photo URLs.
///
/// The Places key is iOS-bundle-restricted, which Google enforces by
/// requiring an `X-Ios-Bundle-Identifier` header on the photo request —
/// AsyncImage's own URLSession request never sends custom headers, so a
/// Places photo silently never loads through it (no error, just a blank
/// placeholder forever). RexAPI.repairPlacePhotoIfNeeded already works
/// around this for *saved* items by re-hosting the photo once, but a search
/// picker shows results before anything's saved, so there's no item row to
/// repair yet — this is that same fix, done live for display instead of
/// once for storage.
struct GoogleSafeAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var didFail = false

    private var isGooglePlacesURL: Bool {
        url?.absoluteString.contains("places.googleapis.com") ?? false
    }

    var body: some View {
        Group {
            if let loadedImage {
                content(Image(uiImage: loadedImage))
            } else if isGooglePlacesURL {
                placeholder()
                    .task(id: url) { await loadGoogle() }
            } else {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        content(image)
                    } else {
                        placeholder()
                    }
                }
            }
        }
    }

    private func loadGoogle() async {
        guard let url, !didFail else { return }
        var request = URLRequest(url: url)
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let image = UIImage(data: data)
        else {
            didFail = true
            return
        }
        loadedImage = image
    }
}
