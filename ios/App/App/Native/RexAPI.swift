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

    /// Whether the `is_anonymous` migration has been run.
    ///
    /// Asking PostgREST for a column that doesn't exist makes it reject the
    /// whole query, so selecting this blind would take the entire feed down
    /// until the SQL is run — which is exactly what the Google rating columns
    /// did. Probe once, then remember.
    private var anonymousColumn: Bool?

    private func anonymousField() async -> String {
        if let anonymousColumn { return anonymousColumn ? ",is_anonymous" : "" }
        guard let token = try? await validToken() else { return "" }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "is_anonymous"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let ok = (try? await URLSession.shared.data(for: request))
            .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
            .map { $0 < 400 } ?? false
        anonymousColumn = ok
        return ok ? ",is_anonymous" : ""
    }

    func signUp(email: String, password: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/auth/v1/signup"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RexAPIError.invalidResponse }
        if http.statusCode >= 400 {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (body?["error_description"] as? String) ?? (body?["msg"] as? String)
                ?? "Couldn't create your account."
            throw RexAPIError.server(message)
        }
        // With email confirmation on, signup returns a user but no session —
        // the caller shows "check your inbox" rather than barging into the feed.
        struct SignUpResponse: Codable { let access_token: String?; let refresh_token: String? }
        let decoded = try JSONDecoder().decode(SignUpResponse.self, from: data)
        accessToken = decoded.access_token
        refreshTokenValue = decoded.refresh_token
    }

    /// Whether signup produced a usable session, or the account still needs
    /// confirming by email.
    var hasSession: Bool { accessToken != nil }

    /// Sign in with the identity token Apple handed us. Supabase verifies it
    /// against the bundle ID listed in its Apple provider settings, so this
    /// needs no client secret.
    func signInWithApple(idToken: String, nonce: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("/auth/v1/token"))
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        request.url = components.url
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": "apple", "id_token": idToken, "nonce": nonce,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RexAPIError.invalidResponse }
        if http.statusCode >= 400 {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (body?["error_description"] as? String) ?? (body?["msg"] as? String)
                ?? "Couldn't sign in with Apple."
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

        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
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
        // The Google rating columns only exist once that migration has been run.
        // Ask for them, but fall back to the base columns rather than failing the
        // whole page — an item detail that can't open is far worse than a missing
        // star rating. Drop the fallback once the migration is everywhere.
        let base = "id,type,title,subtitle,image_url,genre,address"
        if let item = try? await fetchItem(id: id, select: base + ",google_rating,google_rating_count") {
            return item
        }
        return try await fetchItem(id: id, select: base)
    }

    private func fetchItem(id: String, select: String) async throws -> RexItem {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
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
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,trip_id,trip_section," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
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
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id," +
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
    /// `hit` carries the external catalogue metadata (cover art, coordinates,
    /// genre, source id) when the user picked a search suggestion, so items
    /// created natively look the same as ones created on the web.
    func createItem(
        type: String,
        title: String,
        subtitle: String?,
        address: String?,
        hit: RexSearchHit? = nil,
        genre: String? = nil,
        linkURL: String? = nil,
        externalId: String? = nil,
        externalSource: String? = nil,
        imageURL: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        recipeText: String? = nil
    ) async throws -> String {
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
        if let hit {
            body["external_id"] = hit.externalId
            body["external_source"] = hit.externalSource
            body["image_url"] = hit.imageURL ?? NSNull()
            body["genre"] = hit.genre ?? NSNull()
            body["lat"] = hit.lat ?? NSNull()
            body["lng"] = hit.lng ?? NSNull()
        }
        // An explicit subcategory choice wins over whatever the catalogue guessed.
        if let genre, !genre.isEmpty { body["genre"] = genre }
        if let linkURL, !linkURL.isEmpty { body["link_url"] = linkURL }
        if let externalId { body["external_id"] = externalId }
        if let externalSource { body["external_source"] = externalSource }
        if let imageURL { body["image_url"] = imageURL }
        if let lat { body["lat"] = lat }
        if let lng { body["lng"] = lng }
        // Google's public rating, kept separate from friends' ratings.
        if let r = hit?.googleRating { body["google_rating"] = r }
        if let c = hit?.googleRatingCount { body["google_rating_count"] = c }
        if let recipeText, !recipeText.isEmpty { body["recipe_text"] = recipeText }
        // Google's photo URLs only serve an image to a request carrying our
        // bundle id, which AsyncImage doesn't send — so they render blank. They
        // also embed the API key in a URL we'd be storing. Fetch the image once
        // here and keep our own copy instead.
        if let raw = body["image_url"] as? String, raw.contains("places.googleapis.com") {
            body["image_url"] = (await copyGooglePhoto(raw)) ?? NSNull()
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var (data, response) = try await URLSession.shared.data(for: request)
        // Same story as fetchItem: if the Google rating columns aren't there yet,
        // save the item without them rather than losing the whole Rex.
        if let http = response as? HTTPURLResponse, http.statusCode >= 400,
           body["google_rating"] != nil || body["google_rating_count"] != nil {
            body["google_rating"] = nil
            body["google_rating_count"] = nil
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            (data, response) = try await URLSession.shared.data(for: request)
        }
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
    @discardableResult
    func createRecommendation(
        itemId: String,
        rating: Double,
        note: String?,
        photoURLs: [String] = [],
        tags: [String] = [],
        tripId: String? = nil,
        tripSection: String? = nil,
        anonymous: Bool = false,
        returningId: Bool = false
    ) async throws -> String {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/recommendations"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["user_id": userId, "item_id": itemId, "rating": rating]
        body["note"] = note?.isEmpty == false ? note : NSNull()
        body["photo_url"] = photoURLs.first ?? NSNull()
        body["photo_urls"] = photoURLs
        body["tags"] = tags
        if let tripId { body["trip_id"] = tripId }
        if let tripSection, !tripSection.isEmpty { body["trip_section"] = tripSection }
        if anonymous { body["is_anonymous"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        if returningId {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't post your Rex. \(body)")
        }
        guard returningId else { return "" }
        struct Created: Codable { let id: String }
        let rows = try JSONDecoder().decode([Created].self, from: data)
        guard let id = rows.first?.id else { throw RexAPIError.invalidResponse }
        return id
    }

    /// Marks an item as "want to try/watch/visit" instead of rating it — inserts into `wants`.
    func createWant(itemId: String, note: String? = nil) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/wants"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        var body: [String: Any] = ["user_id": userId, "item_id": itemId]
        // Only sent when there's something to say, so the column being absent
        // can't break saving.
        if let note, !note.isEmpty { body["note"] = note }
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
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
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
        // There's no FK from notifications.actor_id to profiles, so the
        // embedded join PostgREST would need doesn't exist — fetch the actors
        // separately and stitch them on. (The web app does the same.)
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/notifications"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,actor_id,type,entity_type,entity_id,data,read_at,created_at"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "100"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't load notifications. \(body)")
        }
        var notifications = try JSONDecoder().decode([RexNotification].self, from: data)

        let actorIds = Array(Set(notifications.compactMap { $0.actor_id }))
        if !actorIds.isEmpty {
            let profiles = (try? await fetchProfiles(ids: actorIds)) ?? []
            let byId = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            notifications = notifications.map { n in
                guard let aid = n.actor_id, let p = byId[aid] else { return n }
                var copy = n
                copy.actor = RexProfile(
                    username: p.username,
                    display_name: p.display_name,
                    avatar_url: p.avatar_url
                )
                return copy
            }
        }
        return notifications
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

    // MARK: - Profile

    /// Uploads an avatar to the `avatars` bucket (own folder, matching the RLS
    /// policy) and returns a long-lived signed URL.
    func uploadAvatar(data imageData: Data) async throws -> String {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let path = "\(userId)/\(UUID().uuidString).jpg"

        var upload = URLRequest(url: baseURL.appendingPathComponent("/storage/v1/object/avatars/\(path)"))
        upload.httpMethod = "POST"
        upload.setValue(anonKey, forHTTPHeaderField: "apikey")
        upload.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        upload.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        upload.httpBody = imageData

        let (upData, upResponse) = try await URLSession.shared.data(for: upload)
        guard let upHttp = upResponse as? HTTPURLResponse, upHttp.statusCode < 400 else {
            let body = String(data: upData, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't upload that photo. \(body)")
        }

        var sign = URLRequest(url: baseURL.appendingPathComponent("/storage/v1/object/sign/avatars/\(path)"))
        sign.httpMethod = "POST"
        sign.setValue(anonKey, forHTTPHeaderField: "apikey")
        sign.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        sign.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sign.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": 157_680_000])

        let (signData, signResponse) = try await URLSession.shared.data(for: sign)
        guard let signHttp = signResponse as? HTTPURLResponse, signHttp.statusCode < 400,
              let json = try JSONSerialization.jsonObject(with: signData) as? [String: Any],
              let signed = json["signedURL"] as? String ?? json["signedUrl"] as? String
        else { throw RexAPIError.server("Couldn't sign that photo URL.") }
        return baseURL.absoluteString + "/storage/v1" + signed
    }

    func updateProfile(displayName: String?, avatarURL: String?) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let displayName { body["display_name"] = displayName.isEmpty ? NSNull() : displayName }
        if let avatarURL { body["avatar_url"] = avatarURL }
        guard !body.isEmpty else { return }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't save your profile. \(body)")
        }
    }

    // MARK: - Photos

    /// Uploads image data to the rec-photos bucket and returns a long-lived
    /// signed URL. Files go under the user's own folder, which is what the
    /// storage RLS policy checks.
    /// Downloads a Google Places photo using the headers its key restriction
    /// requires, and re-hosts it in our own storage. Returns nil rather than
    /// failing the save — a place without a picture still beats no place.
    private func copyGooglePhoto(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        if let bundleId = Bundle.main.bundleIdentifier {
            request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              !data.isEmpty
        else { return nil }
        return try? await uploadPhoto(data: data)
    }

    func uploadPhoto(data imageData: Data, fileExtension: String = "jpg") async throws -> String {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let path = "\(userId)/\(UUID().uuidString).\(fileExtension)"

        var upload = URLRequest(url: baseURL.appendingPathComponent("/storage/v1/object/rec-photos/\(path)"))
        upload.httpMethod = "POST"
        upload.setValue(anonKey, forHTTPHeaderField: "apikey")
        upload.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        upload.setValue(fileExtension == "png" ? "image/png" : "image/jpeg", forHTTPHeaderField: "Content-Type")
        upload.httpBody = imageData

        let (upData, upResponse) = try await URLSession.shared.data(for: upload)
        guard let upHttp = upResponse as? HTTPURLResponse, upHttp.statusCode < 400 else {
            let body = String(data: upData, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't upload that photo. \(body)")
        }

        // 5 years, matching the web uploader.
        var sign = URLRequest(url: baseURL.appendingPathComponent("/storage/v1/object/sign/rec-photos/\(path)"))
        sign.httpMethod = "POST"
        sign.setValue(anonKey, forHTTPHeaderField: "apikey")
        sign.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        sign.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sign.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": 157_680_000])

        let (signData, signResponse) = try await URLSession.shared.data(for: sign)
        guard let signHttp = signResponse as? HTTPURLResponse, signHttp.statusCode < 400,
              let json = try JSONSerialization.jsonObject(with: signData) as? [String: Any],
              let signed = json["signedURL"] as? String ?? json["signedUrl"] as? String
        else {
            throw RexAPIError.server("Couldn't sign that photo URL.")
        }
        return baseURL.absoluteString + "/storage/v1" + signed
    }

    // MARK: - Editing

    func updateRecommendation(
        id: String,
        rating: Double,
        note: String?,
        photoURLs: [String],
        tags: [String]
    ) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["rating": rating, "tags": tags, "photo_urls": photoURLs]
        body["note"] = note?.isEmpty == false ? note : NSNull()
        body["photo_url"] = photoURLs.first ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't save your changes. \(body)")
        }
    }

    func deleteRecommendation(id: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't delete that Rex. \(body)")
        }
    }

    // MARK: - Saves & wants (card actions)

    func isSaved(recommendationId: String) async throws -> Bool {
        let token = try await validToken()
        guard let userId = currentUserId else { return false }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "recommendation_id", value: "eq.\(recommendationId)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return false }
        struct Row: Codable { let id: String }
        return !((try? JSONDecoder().decode([Row].self, from: data)) ?? []).isEmpty
    }

    func setSaved(recommendationId: String, saved: Bool) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        if saved {
            var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"))
            request.httpMethod = "POST"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "user_id": userId, "recommendation_id": recommendationId,
            ])
            _ = try await URLSession.shared.data(for: request)
        } else {
            var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "recommendation_id", value: "eq.\(recommendationId)"),
            ]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "DELETE"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try await URLSession.shared.data(for: request)
        }
    }

    func removeWant(itemId: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "item_id", value: "eq.\(itemId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    func isWanted(itemId: String) async throws -> Bool {
        let token = try await validToken()
        guard let userId = currentUserId else { return false }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "item_id", value: "eq.\(itemId)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return false }
        struct Row: Codable { let id: String }
        return !((try? JSONDecoder().decode([Row].self, from: data)) ?? []).isEmpty
    }

    /// Weekly leaderboard, via the same RPC the web uses.
    func fetchTopRexxers(limit: Int = 5) async throws -> [TopRexxer] {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/rpc/top_rexxers_weekly"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["_limit": limit])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't load the leaderboard. \(body)")
        }
        return try JSONDecoder().decode([TopRexxer].self, from: data)
    }

    // MARK: - Likes & comments

    /// Like counts plus whether the current user has liked each one, for a page
    /// of recommendations. Fetched in one round trip rather than per card.
    func fetchLikeState(recommendationIds: [String]) async throws -> [String: (count: Int, likedByMe: Bool)] {
        guard !recommendationIds.isEmpty else { return [:] }
        let token = try await validToken()
        let list = recommendationIds.joined(separator: ",")
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendation_likes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "recommendation_id,user_id"),
            URLQueryItem(name: "recommendation_id", value: "in.(\(list))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [:] }

        struct LikeRow: Codable { let recommendation_id: String; let user_id: String }
        let rows = try JSONDecoder().decode([LikeRow].self, from: data)
        let me = currentUserId
        var result: [String: (count: Int, likedByMe: Bool)] = [:]
        for row in rows {
            var entry = result[row.recommendation_id] ?? (0, false)
            entry.count += 1
            if row.user_id == me { entry.likedByMe = true }
            result[row.recommendation_id] = entry
        }
        return result
    }

    func setLike(recommendationId: String, liked: Bool) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }

        if liked {
            var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/recommendation_likes"))
            request.httpMethod = "POST"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Liking twice shouldn't error — treat it as idempotent.
            request.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "recommendation_id": recommendationId, "user_id": userId,
            ])
            _ = try await URLSession.shared.data(for: request)
        } else {
            var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendation_likes"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "recommendation_id", value: "eq.\(recommendationId)"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            ]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "DELETE"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try await URLSession.shared.data(for: request)
        }
    }

    /// Comment counts for a page of recs, in one round trip.
    func fetchCommentCounts(recommendationIds: [String]) async throws -> [String: Int] {
        guard !recommendationIds.isEmpty else { return [:] }
        let token = try await validToken()
        let list = recommendationIds.joined(separator: ",")
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendation_comments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "recommendation_id"),
            URLQueryItem(name: "recommendation_id", value: "in.(\(list))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [:] }
        struct Row: Codable { let recommendation_id: String }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        return rows.reduce(into: [:]) { $0[$1.recommendation_id, default: 0] += 1 }
    }

    /// Puts a Rex into one of your collections. This is the only path that
    /// writes saved_posts.list_id, which is how a hitlist_list gets contents.
    func addToCollection(recommendationId: String, listId: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": userId, "recommendation_id": recommendationId, "list_id": listId,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't add that to your collection. \(body)")
        }
    }

    func removeFromCollection(recommendationId: String, listId: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "recommendation_id", value: "eq.\(recommendationId)"),
            URLQueryItem(name: "list_id", value: "eq.\(listId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    /// Which of your collections a Rex is already in.
    func collectionsContaining(recommendationId: String) async throws -> Set<String> {
        let token = try await validToken()
        guard let userId = currentUserId else { return [] }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "list_id"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "recommendation_id", value: "eq.\(recommendationId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        struct Row: Codable { let list_id: String? }
        return Set(((try? JSONDecoder().decode([Row].self, from: data)) ?? []).compactMap { $0.list_id })
    }

    func createCollection(name: String, emoji: String?, itemType: String) async throws -> String {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/hitlist_lists"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        // New collections start private. `draft` is the schema's private state —
        // the enum is draft | friends | public, same as the web app uses.
        var body: [String: Any] = [
            "user_id": userId, "name": name, "item_type": itemType, "visibility": "draft",
        ]
        body["emoji"] = emoji ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't create that collection. \(body)")
        }
        struct Created: Codable { let id: String }
        guard let id = (try? JSONDecoder().decode([Created].self, from: data))?.first?.id else {
            throw RexAPIError.invalidResponse
        }
        return id
    }

    func renameCollection(id: String, name: String, emoji: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/hitlist_lists"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["name": name]
        body["emoji"] = emoji?.isEmpty == false ? emoji! : NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't rename that collection. \(body)")
        }
    }

    /// `draft` (only you), `friends`, or `public`.
    func setCollectionVisibility(id: String, visibility: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/hitlist_lists"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["visibility": visibility])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't change who can see that. \(body)")
        }
    }

    func deleteCollection(id: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/hitlist_lists"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't delete that collection. \(body)")
        }
    }

    /// Blasts, for the feed. A blast is a question, and a question sitting on
    /// its own screen doesn't get answered — so it goes where people look.
    ///
    /// Shaped as a recommendation, like wants, so the feed renders one list.
    func fetchBlastsFeed() async throws -> [FeedRecommendation] {
        let token = try await validToken()
        let select = "id,created_at,title,note,type,user_id," +
            "profiles!requests_user_id_profiles_fkey(username,display_name,avatar_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/requests"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "20"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        struct Row: Codable {
            let id: String
            let created_at: String
            let title: String
            let note: String?
            let type: String?
            let user_id: String
            let profiles: RexProfile?
        }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        return rows.map { row in
            FeedRecommendation(
                id: "blast-\(row.id)",
                rating: 0,
                note: row.note,
                created_at: row.created_at,
                photo_url: nil,
                photo_urls: nil,
                tags: nil,
                user_id: row.user_id,
                // A blast has no item — the ask itself is the content.
                item_id: "blast-\(row.id)",
                items: RexItem(
                    id: "blast-\(row.id)",
                    type: row.type ?? "other",
                    title: row.title,
                    subtitle: nil,
                    image_url: nil,
                    genre: nil
                ),
                profiles: row.profiles,
                creators: nil,
                trip_section: nil,
                is_anonymous: false
            )
        }
    }

    /// A blast — asking friends for a recommendation.
    func createRequest(type: String, title: String, note: String?) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/requests"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["user_id": userId, "type": type, "title": title]
        body["note"] = note ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't send your blast. \(body)")
        }
    }

    /// Anonymous feedback goes in with user_id null so it can't be traced back.
    func sendFeedback(message: String, anonymous: Bool, page: String?) async throws {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/feedback"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "message": message, "kind": "app", "is_anonymous": anonymous,
        ]
        body["page"] = page ?? NSNull()
        body["user_id"] = anonymous ? NSNull() : (currentUserId ?? NSNull())
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't send that. \(body)")
        }
    }

    func fetchComments(recommendationId: String) async throws -> [RexComment] {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendation_comments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,body,created_at,user_id,profiles!recommendation_comments_user_id_fkey(username,display_name,avatar_url)"),
            URLQueryItem(name: "recommendation_id", value: "eq.\(recommendationId)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't load comments. \(body)")
        }
        return try JSONDecoder().decode([RexComment].self, from: data)
    }

    func addComment(recommendationId: String, body text: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/recommendation_comments"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "recommendation_id": recommendationId, "user_id": userId, "body": text,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't post your comment. \(body)")
        }
    }

    /// The user's own curated lists (hitlist_lists) — e.g. "Baby Recs".
    func fetchLists() async throws -> [RexList] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/hitlist_lists"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,name,emoji,item_type,visibility,created_at"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load your lists.")
        }
        return try JSONDecoder().decode([RexList].self, from: data)
    }

    /// Collections you follow (read-only) — someone else's list you've saved.
    func fetchFollowedLists() async throws -> [RexList] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/list_follows"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "hitlist_lists(id,name,emoji,item_type,visibility,created_at,user_id)"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        // The table may not exist yet (migration pending) — treat that as empty
        // rather than failing the whole screen.
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        struct Row: Codable { let hitlist_lists: RexList? }
        return ((try? JSONDecoder().decode([Row].self, from: data)) ?? []).compactMap { $0.hitlist_lists }
    }

    /// Collections shared with you to co-edit.
    func fetchCollaboratingLists() async throws -> [RexList] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/list_collaborators"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "hitlist_lists(id,name,emoji,item_type,visibility,created_at,user_id)"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        struct Row: Codable { let hitlist_lists: RexList? }
        return ((try? JSONDecoder().decode([Row].self, from: data)) ?? []).compactMap { $0.hitlist_lists }
    }

    /// Posts saved from other people — the Pinterest-style half of Collections.
    func fetchSavedPosts() async throws -> [SavedPost] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let select = "id,created_at,list_id,recommendation_id," +
            "recommendations(id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id," +
            "items(id,type,title,subtitle,image_url,genre)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"), resolvingAgainstBaseURL: false)!
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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't load your saved posts. \(body)")
        }
        return try JSONDecoder().decode([SavedPost].self, from: data)
    }

    /// What's inside one collection. Unlike `fetchSavedPosts` this isn't scoped
    /// to you — it's how you browse a friend's collection too, so RLS on
    /// hitlist_lists is what decides whether you can see it.
    func fetchCollectionItems(listId: String) async throws -> [SavedPost] {
        let token = try await validToken()
        let select = "id,created_at,list_id,recommendation_id," +
            "recommendations(id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id," +
            "items(id,type,title,subtitle,image_url,genre)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "list_id", value: "eq.\(listId)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RexAPIError.server("Couldn't load that collection. \(body)")
        }
        return try JSONDecoder().decode([SavedPost].self, from: data)
    }

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
    /// Wants worth putting in the feed — someone saying "I want to try this"
    /// is an invitation for friends to chime in, which they can't do while it
    /// sits on a private list.
    ///
    /// Presented as recommendations with no rating so the feed can render them
    /// with everything else; `rating: 0` is what marks them as a want.
    func fetchWantsFeed() async throws -> [FeedRecommendation] {
        let token = try await validToken()
        guard let userId = currentUserId else { return [] }
        let noteField = await wantNoteField()
        let select = "id,created_at,item_id,user_id\(noteField)," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
            "profiles!wants_user_id_fkey(username,display_name,avatar_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            // Your own wants already live on your list; the feed is other people.
            URLQueryItem(name: "user_id", value: "neq.\(userId)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "30"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        struct Row: Codable {
            let id: String
            let created_at: String
            let item_id: String
            let user_id: String
            let note: String?
            let items: RexItem?
            let profiles: RexProfile?
        }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        return rows.map { row in
            FeedRecommendation(
                id: "want-\(row.id)",
                rating: 0,
                note: row.note,
                created_at: row.created_at,
                photo_url: nil,
                photo_urls: nil,
                tags: nil,
                user_id: row.user_id,
                item_id: row.item_id,
                items: row.items,
                profiles: row.profiles,
                creators: nil,
                trip_section: nil,
                is_anonymous: false
            )
        }
    }

    /// Same guard as the anonymous column — the note only exists once that
    /// migration has been run, and selecting it blind would fail the query.
    private var wantNoteColumn: Bool?

    private func wantNoteField() async -> String {
        if let wantNoteColumn { return wantNoteColumn ? ",note" : "" }
        guard let token = try? await validToken() else { return "" }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "note"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let ok = (try? await URLSession.shared.data(for: request))
            .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
            .map { $0 < 400 } ?? false
        wantNoteColumn = ok
        return ok ? ",note" : ""
    }

    /// How many people have Rex'd each of these items. Counted client-side
    /// because PostgREST has no group-by; the id list is one feed page, so this
    /// stays small.
    func fetchRexCounts(itemIds: [String]) async throws -> [String: Int] {
        guard !itemIds.isEmpty else { return [:] }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "item_id"),
            URLQueryItem(name: "item_id", value: "in.(\(itemIds.joined(separator: ",")))"),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "limit", value: "2000"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [:] }
        struct Row: Codable { let item_id: String }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        return rows.reduce(into: [:]) { counts, row in counts[row.item_id, default: 0] += 1 }
    }

    /// Titles for a set of trips, keyed by the trip's recommendation id — what
    /// map pins carry in `trip_id`.
    func fetchTripTitles(recommendationIds: [String]) async throws -> [String: String] {
        guard !recommendationIds.isEmpty else { return [:] }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,items(title)"),
            URLQueryItem(name: "id", value: "in.(\(recommendationIds.joined(separator: ",")))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [:] }
        struct Row: Codable {
            let id: String
            struct Item: Codable { let title: String }
            let items: Item?
        }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            row.items.map { (row.id, $0.title) }
        })
    }

    func fetchMapPlaces() async throws -> [MapPlace] {
        let token = try await validToken()
        let select = "id,title,subtitle,type,genre,address,lat,lng,image_url," +
            "recommendations!inner(id,rating,user_id,trip_id,profiles(username,display_name,avatar_url))"
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
