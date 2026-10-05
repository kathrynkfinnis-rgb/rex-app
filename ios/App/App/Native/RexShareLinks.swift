import Foundation

/// Sept 17 — where a shared Rex actually points.
///
/// Every share link the app has ever produced pointed at the old Lovable
/// preview host, which now returns 404 — so every Rex anyone has shared with
/// a friend is a dead link. They point at find-rex.com now, which serves the
/// same pages from the same database, and which we control.
///
/// Trips get their own path: /t/<id> renders the whole itinerary in order,
/// while /r/<id> would show only the trip's own card.
enum RexShareLink {
    static let site = "https://find-rex.com"

    static func url(recommendationId: String, type: String?) -> URL? {
        let path = RexCategory(rawType: type) == .trip ? "t" : "r"
        return URL(string: "\(site)/\(path)/\(recommendationId)")
    }

    /// Oct 5 — a collection's own public page. Only resolves for one the owner
    /// has set to "Anyone on REX"; the RPC behind it refuses anything else, so
    /// a link to a private collection 404s rather than confirming it exists.
    static func collectionURL(listId: String) -> URL? {
        URL(string: "\(site)/c/\(listId)")
    }

    /// Oct 5 — "when you share something on WhatsApp it should always have a
    /// 'to see more, join Rex' with a short link."
    ///
    /// The message is words only. ShareLink appends the URL itself, so a
    /// message that also contains it produces the link twice — and the first
    /// attempt here put the site in the invitation as well, which made three
    /// links for one share. Everything a reader needs is the one link
    /// ShareLink adds: it opens a public page that offers the App Store from
    /// there, so the invitation doesn't need an address of its own.
    static let joinLine = "To see more, join REX."

    /// What it is, then the invitation. No URLs: see above.
    static func message(_ lead: String, url: URL? = nil) -> String {
        _ = url
        return "\(lead)\n\n\(joinLine)"
    }
}
