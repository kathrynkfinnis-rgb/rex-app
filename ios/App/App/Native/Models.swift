import Foundation

struct RexItem: Codable {
    let id: String
    let type: String
    let title: String
    let subtitle: String?
    let image_url: String?
    let genre: String?
    let address: String?

    init(id: String, type: String, title: String, subtitle: String?, image_url: String?, genre: String?, address: String? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.image_url = image_url
        self.genre = genre
        self.address = address
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

struct WantRow: Codable, Identifiable {
    let id: String
    let created_at: String
    let item_id: String
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
    let actor: RexProfile?

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

    /// Item id to deep-link to, if this notification points at a (non-trip) recommendation.
    var linkedItemId: String? {
        guard entity_type == "recommendation", let id = entity_id else { return nil }
        guard data?["category"]?.stringValue != "trip" else { return nil }
        return id
    }
    var linksToFriends: Bool {
        entity_type == "friendship" || type == "friend_request" || type == "friend_accepted"
    }
}

struct MapRecStub: Codable {
    let id: String
    let rating: Double
    let user_id: String
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

    var averageRating: Double {
        guard !recommendations.isEmpty else { return 0 }
        return recommendations.reduce(0) { $0 + $1.rating } / Double(recommendations.count)
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
