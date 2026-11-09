import CoreLocation
import Foundation

/// Nov 9 — "the play should be the dominant title, not the theatre", and the
/// search behind it: typing "eurotrash" into an event offered 1 Eurotrash
/// street, Prahran VIC 3181, Australia.
///
/// The place search was never unbiased — with nothing better to go on it
/// rings a rectangle round the UK, Ireland, Scandinavia and mainland Europe
/// (see RexSearch.places). But locationBias is soft: it ranks matches inside
/// the box higher rather than excluding what is outside it, so when no
/// European place answers to the name, a street in Victoria wins by default.
/// A continent is simply too large a hint to settle anything.
///
/// So the form asks. A town typed into the search becomes a 60km box, which
/// is the same `near` a trip already passes from its own stops.
///
/// Asking beats reading the device's location, and not only on privacy.
/// Rex is for things you will do somewhere else — the Tokyo restaurant added
/// from a sofa in London is the case the whole app is built around, and the
/// device's answer there is worse than the Europe fallback. It also means no
/// authorisation: forward-geocoding a string someone typed needs none, unlike
/// reading where they actually are.
enum RexNearby {
    /// Apple rate-limits geocoding at around a request a second and starts
    /// returning errors rather than queueing, so repeats are answered from
    /// here. Towns do not move, and the same few get typed over and over.
    private static var cache: [String: CLLocationCoordinate2D] = [:]
    private static let lastUsedKey = "rex.search.near"

    /// The town the box starts with, so the common case needs no typing.
    /// Whatever was used last, which after the first search is almost always
    /// still right.
    static var remembered: String {
        get { UserDefaults.standard.string(forKey: lastUsedKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: lastUsedKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: lastUsedKey)
            }
        }
    }

    /// A typed place name as coordinates, or nil.
    ///
    /// nil is a perfectly good answer and the caller treats it as "no hint":
    /// the search still runs, biased to Europe as before. A town we cannot
    /// place should never be the difference between results and an error.
    static func coordinate(for text: String) async -> (lat: Double, lng: Double)? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key.count >= 2 else { return nil }
        if let hit = cache[key] { return (hit.latitude, hit.longitude) }

        guard let placemark = try? await CLGeocoder().geocodeAddressString(text).first,
              let location = placemark.location
        else { return nil }

        cache[key] = location.coordinate
        return (location.coordinate.latitude, location.coordinate.longitude)
    }
}
