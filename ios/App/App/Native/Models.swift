import Foundation

struct RexItem: Codable {
    let id: String
    let type: String
    let title: String
    let subtitle: String?
    let image_url: String?
    let genre: String?
    let address: String?
    let google_rating: Double?
    let google_rating_count: Int?

    init(id: String, type: String, title: String, subtitle: String?, image_url: String?, genre: String?, address: String? = nil, google_rating: Double? = nil, google_rating_count: Int? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.image_url = image_url
        self.genre = genre
        self.address = address
        self.google_rating = google_rating
        self.google_rating_count = google_rating_count
    }
}

struct RexProfile: Codable {
    let username: String
    let display_name: String?
    let avatar_url: String?
}

struct RexProfileDetail: Codable, Identifiable {
    let id: String
    let username: String
    let display_name: String?
    let avatar_url: String?
}

/// A friends-of-friends candidate from suggested_friends_for_me, ranked by
/// how many mutual friends you share.
struct SuggestedFriend: Codable, Identifiable {
    let id: String
    let username: String
    let display_name: String?
    let avatar_url: String?
    let mutual_count: Int
}

struct WantRow: Codable, Identifiable {
    let id: String
    let created_at: String
    let item_id: String
    /// Which collection this want sits in, if any — see RexAPI.setWantList.
    var list_id: String?
    let items: RexItem?
}

struct Friendship: Codable, Identifiable {
    let id: String
    let requester_id: String
    let addressee_id: String
    let status: String
}

/// Minimal permissive JSON value for the notifications.data JSONB column (shape varies by type).
enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

struct RexNotification: Codable, Identifiable {
    let id: String
    let actor_id: String?
    let type: String
    let entity_type: String?
    let entity_id: String?
    let data: [String: JSONValue]?
    let read_at: String?
    let created_at: String
    /// Filled in after fetch — there's no FK to embed it via the query.
    var actor: RexProfile?

    var copy: String {
        let who = actor?.display_name ?? actor?.username ?? "Someone"
        let preview = data?["preview"]?.stringValue ?? ""
        let title = data?["title"]?.stringValue ?? ""
        switch type {
        case "rec_like": return "\(who) liked your Rex"
        case "rec_saved": return "\(who) added your Rex to their collection"
        case "rec_comment": return "\(who) commented: \"\(preview)\""
        case "friend_request": return "\(who) sent you a friend request"
        case "friend_accepted": return "\(who) accepted your friend request"
        case "blast_new": return "\(who) put out a blast: \"\(title)\""
        case "blast_comment":
            return data?["has_suggestion"]?.boolValue == true
                ? "\(who) suggested something on your blast \"\(title)\""
                : "\(who) replied to your blast: \"\(preview)\""
        case "mention": return "\(who) tagged you: \"\(preview)\""
        case "friend_new_rec": return "\(who) Rexed \(title.isEmpty ? "something new" : title)"
        default: return "New activity"
        }
    }

    /// Recommendation id this notification points at, for non-trip "recommendation"
    /// entity_type notifications (likes, comments, saves, mentions, a friend's new
    /// Rex). This is the *recommendation* id, not the item id — every trigger that
    /// writes entity_type='recommendation' sets entity_id to recommendations.id
    /// (see the notify_rec_like/rec_comment/rec_saved/mention/friend_new_rec
    /// triggers), so passing it straight to ItemDetailView(itemId:) as this used
    /// to do just 404'd. NotificationsView resolves it to the actual item id via
    /// a batched lookup instead, since entity_id is polymorphic and can't be
    /// embedded in the notifications query itself.
    var linkedRecommendationId: String? {
        guard entity_type == "recommendation", let id = entity_id else { return nil }
        guard data?["category"]?.stringValue != "trip" else { return nil }
        return id
    }

    /// Trips are addressed by their recommendation id, so they open the
    /// itinerary rather than a generic item screen.
    var isTrip: Bool {
        entity_type == "recommendation" && data?["category"]?.stringValue == "trip"
    }

    var linkedTitle: String? { data?["title"]?.stringValue }
    var linksToFriends: Bool {
        entity_type == "friendship" || type == "friend_request" || type == "friend_accepted"
    }
}

struct MapRecStub: Codable {
    let id: String
    let rating: Double
    let user_id: String
    /// The trip this stop belongs to, if any — points at the trip's own
    /// recommendation id, not an item id.
    let trip_id: String?
    let profiles: RexProfile?
}

/// One pin per place — matches the decided map behavior (consolidated, not per-person).
/// `recommendations` is only ever non-empty (PostgREST's `!inner` join guarantees that),
/// so a place whose only Rex got deleted never lingers as an orphan pin.
struct MapPlace: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let type: String
    let genre: String?
    let address: String?
    let lat: Double?
    let lng: Double?
    let image_url: String?
    let recommendations: [MapRecStub]

    /// Trips this place is a stop on.
    var tripIds: [String] {
        Array(Set(recommendations.compactMap { $0.trip_id }))
    }

    /// "Ava" if one recommender, "Rex'd by several friends" if more than one.
    var recommenderSummary: String {
        let names = recommendations.compactMap { $0.profiles?.display_name ?? $0.profiles?.username }
        if names.count == 1 { return names[0] }
        if names.isEmpty { return "A friend" }
        return "Rex'd by several friends"
    }
}

struct RexCreator: Codable {
    let slug: String
    let name: String
    let color: String
    let emoji: String?
}

struct FeedRecommendation: Codable, Identifiable {
    let id: String
    let rating: Double
    let note: String?
    let created_at: String
    let photo_url: String?
    let photo_urls: [String]?
    let tags: [String]?
    let user_id: String
    let item_id: String
    let items: RexItem?
    let profiles: RexProfile?
    let creators: RexCreator?
    /// Optional heading a trip stop sits under (e.g. "Brunch"). Only present on
    /// trip-stop queries, hence optional everywhere else.
    let trip_section: String?
    /// Posted without a name on it. Optional so the app keeps working against a
    /// database where the migration hasn't been run.
    let is_anonymous: Bool?
    /// Optional heading a list item sits under — list_id/list_section mirror
    /// trip_id/trip_section exactly, just for the "List" category.
    let list_section: String?
    /// Whether a list item shows on the main feed on its own, independent of
    /// the list itself showing there. Optional/defaulted true client-side so
    /// this keeps working against a database where the migration hasn't run
    /// yet, and for every query that doesn't select it at all.
    let show_in_feed: Bool?

    /// A want rather than a Rex — someone saying they'd like to try this. The
    /// feed carries both, and an unrated row is what marks the difference.
    var isWant: Bool { id.hasPrefix("want-") }

    /// A blast — someone asking for recommendations rather than giving one.
    var isBlast: Bool { id.hasPrefix("blast-") }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var createdDate: Date? {
        FeedRecommendation.isoFormatter.date(from: created_at)
            ?? ISO8601DateFormatter().date(from: created_at)
    }
}

/// One of the user's own curated lists (hitlist_lists) — e.g. "Baby Recs".
struct RexList: Codable, Identifiable {
    let id: String
    let name: String
    let emoji: String?
    let item_type: String?
    let visibility: String?
    let created_at: String?
    /// Owner — used to credit followed and shared collections.
    let user_id: String?
}

/// A recommendation the user saved from someone else's post.
struct SavedPost: Codable, Identifiable {
    let id: String
    let created_at: String?
    let list_id: String?
    let recommendation_id: String
    let recommendations: FeedRecommendation?
}

struct RexComment: Codable, Identifiable {
    let id: String
    let body: String
    let created_at: String
    let user_id: String
    let profiles: RexProfile?
}

/// A weekly leaderboard entry from the top_rexxers_weekly RPC.
struct TopRexxer: Codable, Identifiable {
    let user_id: String
    let username: String
    let display_name: String?
    let avatar_url: String?
    let rex_count: Int

    var id: String { user_id }
}

/// Explore tab. Most-Rex'd items this week, from trending_items_weekly.
struct TrendingItem: Codable, Identifiable {
    let item_id: String
    let title: String
    let subtitle: String?
    let image_url: String?
    let type: String
    let rex_count: Int

    var id: String { item_id }
}

/// Explore tab. A shelf curated by the named REX team members — either
/// their own pick or something credited elsewhere via source_label.
struct EditorialCollection: Codable, Identifiable {
    let id: String
    let title: String
    let source_label: String
    let category: String?
    let editorial_collection_items: [EditorialCollectionItem]?

    var items: [EditorialCollectionItem] { editorial_collection_items ?? [] }
}

struct EditorialCollectionItem: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let image_url: String?
    let item_id: String?
    let link_url: String?
}

// MARK: - Import (#109 "Lists" category, #15/#38 native trip import)

/// One recommendation as the extraction edge function returned it, before
/// it's ever touched the database. Mirrors the web importer's ExtractedRec
/// (src/lib/import.functions.ts) and the edge function's EXTRACTION_TOOL
/// schema exactly — same shape either client asked for it.
struct ExtractedRec: Codable {
    let title: String
    let creator: String?
    let note: String?
    let rating: Double?
    let type: String?
    let section: String?
    let url: String?
}

/// A row in import_staging — an extracted recommendation waiting to be
/// reviewed and turned into a real item + recommendation. Field names match
/// the table columns directly since this is decoded straight from PostgREST.
struct ImportStagingRow: Codable, Identifiable, Hashable {
    let id: String
    let source: String
    let raw_title: String
    let raw_creator: String?
    let raw_note: String?
    let raw_rating: Double?
    let suggested_type: String?
    let raw_section: String?
    let raw_url: String?
    let resolved_item_id: String?
    let resolved_external_id: String?
    let resolved_external_source: String?
    let resolved_image_url: String?
    let resolved_subtitle: String?
    let resolved_genre: String?
    let status: String
}
