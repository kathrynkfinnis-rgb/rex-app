import Foundation

enum RexAPIError: LocalizedError {
    case invalidResponse
    case server(String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Something went wrong talking to Rex."
        case .server(let message): return message
        case .notSignedIn: return "Please sign in again."
        }
    }
}

/// Minimal hand-rolled Supabase REST client (PostgREST + GoTrue over HTTPS).
/// Same project/keys the web app uses (see .env: VITE_SUPABASE_URL / VITE_SUPABASE_PUBLISHABLE_KEY).
/// NOTE: stores the session in UserDefaults for this prototype pass — move to Keychain before
/// this ships beyond simulator testing. Refresh-token rotation IS implemented (see validToken()),
/// which is what actually fixes "constantly logged out" — access tokens expire in ~1hr and were
/// never being refreshed before.
final class RexAPI {
    static let shared = RexAPI()

    private let baseURL = URL(string: "https://uhpzkbkwxcgqfxmlyktj.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHprYmt3eGNncWZ4bWx5a3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Mzk2NDMsImV4cCI6MjEwMTQxNTY0M30.IvQ8byDwHErLhuJI1Pg3bRcb4AKK4sb9Bm6cr_6sHbI"

    private init() {}

    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "rex.accessToken") }
        set { UserDefaults.standard.set(newValue, forKey: "rex.accessToken") }
    }

    private var refreshTokenValue: String? {
        get { UserDefaults.standard.string(forKey: "rex.refreshToken") }
        set { UserDefaults.standard.set(newValue, forKey: "rex.refreshToken") }
    }

    var isSignedIn: Bool { accessToken != nil }

    /// Decodes the "sub" claim out of the stored JWT — avoids an extra round trip to /auth/v1/user.
    var currentUserId: String? {
        guard let token = accessToken else { return nil }
        return decodeJWTClaims(token)?["sub"] as? String
    }

    private func decodeJWTClaims(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// True if the stored access token is expired or expiring within the next 60s.
    private var accessTokenNeedsRefresh: Bool {
        guard let token = accessToken, let claims = decodeJWTClaims(token), let exp = claims["exp"] as? Double else {
            return true
        }
        return Date(timeIntervalSince1970: exp) < Date().addingTimeInterval(60)
    }

    /// Returns a valid (non-expired) access token, transparently refreshing it first if needed.
    /// This is what actually fixes the "logged out after an hour" bug — every authenticated call
    /// routes through here instead of reading the possibly-stale token directly.
    private func validToken() async throws -> String {
        guard let token = accessToken else { throw RexAPIError.notSignedIn }
        if !accessTokenNeedsRefresh { return token }

        guard let refreshToken = refreshTokenValue else {
            signOut()
            throw RexAPIError.notSignedIn
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("/auth/v1/token"))
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        request.url = components.url
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            // Refresh token itself is dead — only real fix is signing in again.
            signOut()
            throw RexAPIError.notSignedIn
        }
        struct TokenResponse: Codable { let access_token: String; let refresh_token: String }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = decoded.access_token
        refreshTokenValue = decoded.refresh_token
        return decoded.access_token
    }

    func signIn(email: String, password: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/auth/v1/token"))
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        request.url = components.url
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RexAPIError.invalidResponse }
        if http.statusCode >= 400 {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (body?["error_description"] as? String) ?? (body?["msg"] as? String) ?? "Couldn't sign in — check your email and password."
            throw RexAPIError.server(message)
        }
        struct TokenResponse: Codable { let access_token: String; let refresh_token: String }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = decoded.access_token
        refreshTokenValue = decoded.refresh_token
    }

    func signOut() {
        accessToken = nil
        refreshTokenValue = nil
    }

    func fetchFeed() async throws -> [FeedRecommendation] {
        let token = try await validToken()

        let select = "id,rating,note,created_at,photo_url,photo_urls,tags,user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)," +
            "creators(slug,name,color,emoji)"

        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "50"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RexAPIError.invalidResponse }
        if http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't load your feed (\(http.statusCode)). \(body)")
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
    }

    func fetchItem(id: String) async throws -> RexItem {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,type,title,subtitle,image_url,genre,address"),
            URLQueryItem(name: "id", value: "eq.\(id)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load this item.")
        }
        return try JSONDecoder().decode(RexItem.self, from: data)
    }

    /// Stops on a trip. A stop is a recommendation whose `trip_id` points at the
    /// trip's *recommendation* id (not its item id), mirroring the web trip page.
    /// Ordered oldest-first so the itinerary reads in the order it was built.
    func fetchTripStops(tripRecommendationId: String) async throws -> [FeedRecommendation] {
        let token = try await validToken()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags,user_id,item_id,trip_id,trip_section," +
            "items!inner(id,type,title,subtitle,image_url,genre)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "trip_id", value: "eq.\(tripRecommendationId)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't load this trip. \(body)")
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
    }

    func fetchRecommendations(forItem itemId: String) async throws -> [FeedRecommendation] {
        let token = try await validToken()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags,user_id,item_id," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "item_id", value: "eq.\(itemId)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load takes for this item.")
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
    }

    func upsertRecommendation(itemId: String, rating: Double, note: String?) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/recommendations"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        var body: [String: Any] = ["user_id": userId, "item_id": itemId, "rating": rating]
        body["note"] = note?.isEmpty == false ? note : NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var urlComponents = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,item_id")]
        request.url = urlComponents.url

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't save your take. \(body)")
        }
    }

    /// Creates a new item (manual entry — no external search match) and returns its id.
    func createItem(type: String, title: String, subtitle: String?, address: String?) async throws -> String {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/items"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        var body: [String: Any] = ["type": type, "title": title]
        body["subtitle"] = subtitle?.isEmpty == false ? subtitle : NSNull()
        body["address"] = address?.isEmpty == false ? address : NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't create this item. \(body)")
        }
        struct CreatedItem: Codable { let id: String }
        let created = try JSONDecoder().decode([CreatedItem].self, from: data)
        guard let itemId = created.first?.id else { throw RexAPIError.server("Item wasn't created.") }
        return itemId
    }

    /// Creates a brand-new recommendation (used right after createItem — no existing row to merge with).
    func createRecommendation(itemId: String, rating: Double, note: String?) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/recommendations"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["user_id": userId, "item_id": itemId, "rating": rating]
        body["note"] = note?.isEmpty == false ? note : NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't post your Rex. \(body)")
        }
    }

    /// Marks an item as "want to try/watch/visit" instead of rating it — inserts into `wants`.
    func createWant(itemId: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/wants"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let body: [String: Any] = ["user_id": userId, "item_id": itemId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var urlComponents = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,item_id")]
        request.url = urlComponents.url

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't save. \(body)")
        }
    }

    func fetchMyProfile() async throws -> RexProfileDetail {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,username,display_name,avatar_url"),
            URLQueryItem(name: "id", value: "eq.\(userId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load your profile.")
        }
        return try JSONDecoder().decode(RexProfileDetail.self, from: data)
    }

    func fetchRecommendations(forUser userId: String) async throws -> [FeedRecommendation] {
        let token = try await validToken()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags,user_id,item_id," +
            "items!inner(id,type,title,subtitle,image_url,genre)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)," +
            "creators(slug,name,color,emoji)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load this profile's Rex.")
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
    }

    // MARK: - Friends
    // friendships.requester_id/addressee_id reference auth.users(id) directly, not profiles,
    // so (same as the web app) there's no PostgREST embed available — fetch friendships and
    // profiles separately and merge client-side.

    func fetchFriendships() async throws -> [Friendship] {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/friendships"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "select", value: "id,requester_id,addressee_id,status")]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load friends.")
        }
        return try JSONDecoder().decode([Friendship].self, from: data)
    }

    func fetchProfiles(ids: [String]) async throws -> [RexProfileDetail] {
        guard !ids.isEmpty else { return [] }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,username,display_name,avatar_url"),
            URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load profiles.")
        }
        return try JSONDecoder().decode([RexProfileDetail].self, from: data)
    }

    func searchProfilesByUsername(_ query: String) async throws -> [RexProfileDetail] {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,username,display_name,avatar_url"),
            URLQueryItem(name: "or", value: "(username.ilike.*\(query)*,display_name.ilike.*\(query)*)"),
            URLQueryItem(name: "limit", value: "15"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Search failed.")
        }
        return try JSONDecoder().decode([RexProfileDetail].self, from: data)
    }

    func sendFriendRequest(addresseeId: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/friendships"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["requester_id": userId, "addressee_id": addresseeId, "status": "pending"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't send request. \(body)")
        }
    }

    func respondToFriendRequest(id: String, accept: Bool) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/friendships"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = accept ? "PATCH" : "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if accept {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["status": "accepted"])
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't update request. \(body)")
        }
    }

    // MARK: - Notifications

    func fetchNotifications() async throws -> [RexNotification] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/notifications"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,actor_id,type,entity_type,entity_id,data,read_at,created_at,actor:profiles!notifications_actor_id_fkey(username,display_name,avatar_url)"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "100"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load notifications.")
        }
        return try JSONDecoder().decode([RexNotification].self, from: data)
    }

    func markNotificationsRead(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/notifications"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let iso = ISO8601DateFormatter().string(from: Date())
        request.httpBody = try JSONSerialization.data(withJSONObject: ["read_at": iso])

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Wants (Collections)

    func fetchWants() async throws -> [WantRow] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,created_at,item_id,items(id,type,title,subtitle,image_url,genre,address)"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load your want-to list.")
        }
        return try JSONDecoder().decode([WantRow].self, from: data)
    }

    func deleteWant(id: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't remove. \(body)")
        }
    }

    // MARK: - Map

    /// One row per place/event that has at least one live Rex (matches the web app's
    /// `!inner` join — items whose only recommendation got deleted never linger as pins).
    func fetchMapPlaces() async throws -> [MapPlace] {
        let token = try await validToken()
        let select = "id,title,subtitle,type,genre,address,lat,lng,image_url," +
            "recommendations!inner(id,rating,user_id,profiles(username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "type", value: "in.(place,event)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load the map.")
        }
        let places = try JSONDecoder().decode([MapPlace].self, from: data)
        // lat/lng are nullable in the schema even though we need them to place a pin.
        return places.filter { $0.lat != nil && $0.lng != nil }
    }
}
