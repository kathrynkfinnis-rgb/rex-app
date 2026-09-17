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
}
