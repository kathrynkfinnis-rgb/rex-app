import CoreLocation
import Foundation
import MapKit

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
    /// Apple throttles these and starts returning errors rather than
    /// queueing, so repeats are answered from here. Towns do not move, and
    /// the same few get typed over and over.
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
    /// MKLocalSearch rather than CLGeocoder, which Apple deprecated in the
    /// 26 releases in favour of MapKit. Its replacement, MKGeocodingRequest,
    /// is iOS 26 only and this app supports 18, so the search API — which has
    /// been there since iOS 6.1 and is not deprecated — is what works on
    /// every phone Rex runs on. It wants no authorisation either: the query
    /// is answered by Apple's servers, not by the device's whereabouts.
    ///
    /// `boundingRegion` rather than the first result's own coordinate. For a
    /// town the region Apple draws round the query is the better centre; the
    /// first match can be a single shop that happens to carry the name.
    ///
    /// nil is a perfectly good answer and the caller treats it as "no hint":
    /// the search still runs, biased to Europe as before. A town we cannot
    /// place should never be the difference between results and an error.
    static func coordinate(for text: String) async -> (lat: Double, lng: Double)? {
        // Folded the same way both sides of the comparison in `answers`, so
        // "Köln" and "Koln" are the same question and the same cache entry.
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard key.count >= 2 else { return nil }
        if let hit = cache[key] { return (hit.latitude, hit.longitude) }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        guard let response = try? await MKLocalSearch(request: request).start(),
              let match = response.mapItems.first,
              answers(key, match)
        else { return nil }

        let centre = response.boundingRegion.center
        guard CLLocationCoordinate2DIsValid(centre) else { return nil }
        cache[key] = centre
        return (centre.latitude, centre.longitude)
    }

    /// Whether a result is actually about what was asked for.
    ///
    /// Emptiness is not the test. Asked for "notarealplacexyzq",
    /// MKLocalSearch answers with Nora Gardens, London rather than nothing —
    /// so without this a typo would pin every search to wherever Apple
    /// guessed, and the cache above would hold it there. (Some nonsense does
    /// error instead: "qqqqzzzz" returns MKErrorDomain 4. Neither behaviour
    /// can be relied on, which is why the check is on the result.)
    ///
    /// Two ways to pass, and both are needed:
    ///
    /// * **The result echoes the query.** London → London. Prefixes count in
    ///   both directions, because "Lond" has to resolve while somebody is
    ///   still typing, and "Hackney, London" comes back named just "Hackney".
    /// * **The result names itself a settlement** — its own name equals its
    ///   locality or administrative area. This is what catches the endonyms,
    ///   which Apple returns localised and which the echo test therefore
    ///   rejects: Köln → Cologne, München → Munich, Firenze → Florence,
    ///   Lisboa → Lisbon. All four fail the first test and pass this one.
    ///
    /// Nora Gardens fails both — a street carries London as its locality, not
    /// as its name. What does slip through is a real business whose name
    /// matches: "asdfghjkl" finds one in Kisvárda, Hungary. That is a place
    /// that exists and biasing to it is not wrong, only surprising, and the
    /// box is on screen showing what was typed.
    ///
    /// `placemark` is deprecated in the 26 releases, but its replacement
    /// (`addressRepresentations`) is 26-only and this app supports iOS 18.
    private static func answers(_ key: String, _ match: MKMapItem) -> Bool {
        func fold(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        let name = match.name.map(fold)
        let locality = match.placemark.locality.map(fold)
        let admin = match.placemark.administrativeArea.map(fold)

        let echoes = [name, locality, admin].compactMap { $0 }
            .contains { $0.hasPrefix(key) || key.hasPrefix($0) }
        let isSettlement = name != nil && (name == locality || name == admin)
        return echoes || isSettlement
    }
}
