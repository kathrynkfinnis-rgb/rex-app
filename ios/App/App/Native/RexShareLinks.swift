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
    /// 'to see more, join Rex' with a short link", and "every time anything
    /// gets shared on WhatsApp, it should have the link."
    ///
    /// Every share goes through here now, so one place decides what a shared
    /// Rex looks like in a chat thread rather than three that had drifted
    /// apart — one had a link and a message, one a link and no invitation, and
    /// a collection had neither.
    ///
    /// The invitation sits on its own line after the link. WhatsApp previews
    /// the first URL it finds, so the link leading is what produces the card;
    /// the invitation points at the same site rather than introducing a second
    /// URL that would make the preview ambiguous. Someone without the app
    /// lands on a public page that offers the App Store from there.
    static let joinLine = "To see more, join REX \u{2014} \(site)"

    /// The whole message: what it is, then the link, then the invitation.
    static func message(_ lead: String, url: URL?) -> String {
        [lead, url?.absoluteString, joinLine]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }
}
