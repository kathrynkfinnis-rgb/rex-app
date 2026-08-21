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

/// PostgREST error bodies are raw Postgres internals — e.g. the trip-posting
/// bug this was written for surfaced `{"code":"23514","details":null,
/// "hint":null,"message":"new row for relation \"recommendations\" violates
/// check constraint \"recommendations_rating_check\""}` directly in an alert.
/// Every `throw RexAPIError.server(...)` in this file used to interpolate
/// the raw response body straight into the message shown to the user; this
/// picks a friendly line for the Postgres error codes worth naming and
/// otherwise just returns the fallback, never the raw JSON.
private func friendlyError(_ data: Data, fallback: String) -> String {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let code = obj["code"] as? String else {
        return fallback
    }
    switch code {
    case "23505": return "\(fallback) That already exists."
    case "23514": return "\(fallback) One of the values wasn't valid — please try again."
    case "23503": return "\(fallback) Something it depends on is missing."
    case "42501": return "\(fallback) You don't have permission to do that."
    default: return fallback
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

    /// An in-flight refresh, if one's already running — see validToken() below.
    private var refreshTask: Task<String, Error>?

    /// Returns a valid (non-expired) access token, transparently refreshing it first if needed.
    /// This is what actually fixes the "logged out after an hour" bug — every authenticated call
    /// routes through here instead of reading the possibly-stale token directly.
    private func validToken() async throws -> String {
        guard let token = accessToken else { throw RexAPIError.notSignedIn }
        if !accessTokenNeedsRefresh { return token }

        // Piggyback on an already-running refresh rather than starting a
        // second one. This used to be THE cause of "logged out constantly":
        // opening the app after the token expired fires a dozen-plus
        // concurrent authenticated calls at once (feed, profile, and every
        // card's likes/comments/want state), and every one of them called
        // validToken() independently. Supabase rotates the refresh token on
        // every use, so only the first of those concurrent refresh requests
        // succeeds — every other one gets "already used" back and hit
        // signOut(), wiping out the session the winning request had just
        // written moments earlier. Single-flighting the refresh means there
        // is only ever one request in flight, and everyone else just awaits
        // its result.
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task<String, Error> {
            defer { refreshTask = nil }
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
        refreshTask = task
        return try await task.value
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

    /// `category`/`searchText` are the fix for a real bug: the default,
    /// unfiltered call caps at 50 (below) purely to keep the everyday feed
    /// fast — but the category chips and the search bar were just
    /// re-slicing that same capped, unfiltered 50 client-side, so
    /// filtering to a rare category ("only 1 film") or searching for
    /// something older than the last 50 posts ("recent Rex's also don't
    /// come up") came back near-empty even though the content exists.
    /// Passing either one switches to a real server-side filter with a
    /// much higher limit instead of trusting whatever happened to be in
    /// the unfiltered page.
    func fetchFeed(category: String? = nil, searchText: String? = nil) async throws -> [FeedRecommendation] {
        let token = try await validToken()

        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)," +
            "creators(slug,name,color,emoji)"

        let trimmedSearch = searchText?.trimmingCharacters(in: .whitespaces)
        let isFiltered = category != nil || !(trimmedSearch ?? "").isEmpty
        // The default view stays capped at 50 — fast, and everything on
        // screen is recent enough that it's never actually been an issue.
        // A filter or search means the match could be anywhere in your
        // history, so it needs real range to find it.
        let limit = isFiltered ? 300 : 50

        // Trip stops are unconditionally hidden (trip_id.is.null). Anything
        // else defaults visible but can be toggled off individually — #134
        // widened this from list items only (show it if it isn't a list
        // item, or if it is one that's been left on) to any Rex at all, so
        // the check is just the column itself: absent/null (never touched,
        // the vast majority of rows) or explicitly true both show; only an
        // explicit false hides. Filters on show_in_feed, which doesn't exist
        // until migration 20260816230000 is run — this is the core feed,
        // not a best-effort feature, so it can't just break for everyone in
        // the meantime the way a missing column elsewhere in the app gets a
        // quiet ?? [] fallback. Try the real query first; a 400 specifically
        // (not any other failure) falls back to the pre-migration shape
        // once, rather than the feed going blank for every user until the
        // migration happens to be run.
        //
        // `extraFilter` is one more (name, value) query item AND'd onto
        // the request — used both for the category filter and, for
        // search, for exactly one field at a time (see below for why).
        func fetch(includeListFilter: Bool, extraFilter: (String, String)? = nil) async throws -> (Data, HTTPURLResponse) {
            var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
            var queryItems = [
                URLQueryItem(name: "select", value: select),
                URLQueryItem(name: "trip_id", value: "is.null"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "\(limit)"),
            ]
            if let extraFilter { queryItems.append(URLQueryItem(name: extraFilter.0, value: extraFilter.1)) }
            if includeListFilter {
                queryItems.append(URLQueryItem(name: "or", value: "(show_in_feed.is.null,show_in_feed.eq.true)"))
            }
            components.queryItems = queryItems
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RexAPIError.invalidResponse }
            return (data, http)
        }

        func decodedPage(includeListFilter: Bool, extraFilter: (String, String)? = nil) async throws -> [FeedRecommendation] {
            var (data, http) = try await fetch(includeListFilter: includeListFilter, extraFilter: extraFilter)
            if http.statusCode == 400, includeListFilter {
                (data, http) = try await fetch(includeListFilter: false, extraFilter: extraFilter)
            }
            if http.statusCode >= 400 {
                throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load your feed (\(http.statusCode))."))
            }
            return try JSONDecoder().decode([FeedRecommendation].self, from: data)
        }

        if let trimmedSearch, !trimmedSearch.isEmpty {
            // PostgREST's or=() logic tree doesn't support embedded-
            // resource references at all in this project's version —
            // verified live: or=(items.title.ilike...) 400s even on its
            // own, while items.title=ilike... as a plain standalone filter
            // is fine. So instead of one query that ORs across title/note/
            // username/display_name, this runs one query per field (each a
            // valid standalone filter) and merges + dedupes the results —
            // same net effect, just four small requests instead of one.
            let q = trimmedSearch
            async let byTitle = decodedPage(includeListFilter: true, extraFilter: ("items.title", "ilike.*\(q)*"))
            async let byNote = decodedPage(includeListFilter: true, extraFilter: ("note", "ilike.*\(q)*"))
            async let byUsername = decodedPage(includeListFilter: true, extraFilter: ("profiles.username", "ilike.*\(q)*"))
            async let byDisplayName = decodedPage(includeListFilter: true, extraFilter: ("profiles.display_name", "ilike.*\(q)*"))
            let pages = try await [byTitle, byNote, byUsername, byDisplayName]
            var seen = Set<String>()
            var merged: [FeedRecommendation] = []
            for rec in pages.flatMap({ $0 }) where !seen.contains(rec.id) {
                seen.insert(rec.id)
                merged.append(rec)
            }
            return merged.sorted { $0.created_at > $1.created_at }
        }

        return try await decodedPage(
            includeListFilter: true,
            extraFilter: category.map { ("items.type", "eq.\($0)") }
        )
    }

    /// One recommendation by id, same shape as fetchFeed's rows. #138 —
    /// editing a Rex used to call the full loadFeed() to pick up the
    /// change, which replaces the entire feed array and reset scroll to
    /// the top even though the edited row's id and sort position hadn't
    /// moved. Fetching just the one changed row lets the caller splice it
    /// back into the existing array in place instead, so nothing else in
    /// the list re-renders and scroll position holds.
    func fetchRecommendation(id: String) async throws -> FeedRecommendation {
        let token = try await validToken()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)," +
            "creators(slug,name,color,emoji)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "id", value: "eq.\(id)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RexAPIError.invalidResponse }
        if http.statusCode >= 400 {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't refresh this Rex (\(http.statusCode))."))
        }
        let rows = try JSONDecoder().decode([FeedRecommendation].self, from: data)
        guard let row = rows.first else { throw RexAPIError.server("That Rex no longer exists.") }
        return row
    }

    /// Every trip (not stops — trip_id is.null the same way fetchFeed's main
    /// pass is) visible under RLS, for the dedicated trip search screen.
    /// fetchFeed caps at 50 most-recent-of-everything, which is exactly what
    /// stops scaling once there are many trips mixed in with everything
    /// else — this is trip-only and capped much higher.
    func fetchTrips() async throws -> [FeedRecommendation] {
        let token = try await validToken()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "items.type", value: "eq.trip"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "300"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load trips."))
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
    }

    func fetchItem(id: String) async throws -> RexItem {
        // The Google rating columns only exist once that migration has been run.
        // Ask for them, but fall back to the base columns rather than failing the
        // whole page — an item detail that can't open is far worse than a missing
        // star rating. Drop the fallback once the migration is everywhere.
        // #126 — recipe_text was written on create (createItem already sent
        // it) but never read back: fetchItem's select stopped at "address",
        // so a pasted/auto-populated recipe saved fine and then simply had
        // nowhere to display, matching "doesn't seem to have pulled
        // through... even though I checked it and posted it."
        let base = "id,type,title,subtitle,image_url,genre,address,recipe_text"
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

    /// Whether a trip (or any recommendation) is still a draft — see
    /// migration 20260815162631. Own drafts stay visible to their author via
    /// RLS, so this is safe to call for a trip you're looking at even before
    /// it's published.
    func isDraft(recommendationId: String) async throws -> Bool {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "published_at"),
            URLQueryItem(name: "id", value: "eq.\(recommendationId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.pgrst.object+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't check this trip's status.")
        }
        struct Row: Codable { let published_at: String? }
        let row = try JSONDecoder().decode(Row.self, from: data)
        return row.published_at == nil
    }

    /// Publishes a draft trip and every stop journaled onto it in one go —
    /// the whole point of drafting a trip is adding stops over time and
    /// then sharing the finished itinerary all at once, not stop by stop.
    func publishTrip(tripRecommendationId: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "or", value: "(id.eq.\(tripRecommendationId),trip_id.eq.\(tripRecommendationId))"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "published_at": ISO8601DateFormatter().string(from: Date()),
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't publish this trip."))
        }
    }

    /// Your own trips (draft or published) to add a new stop to — task #104's
    /// "Add to trip" card action. trip_id is.null means it's a trip itself,
    /// not one of its own stops.
    func fetchMyTrips() async throws -> [FeedRecommendation] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags,user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "items.type", value: "eq.trip"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load your trips."))
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
    }

    /// Your own draft trips — trip_id is.null (a trip itself, not a stop)
    /// and published_at is.null (never published). Only ever your own by
    /// construction: RLS hides anyone else's drafts before this query even
    /// runs, so there's no need to filter user_id client-side too.
    func fetchDraftTrips() async throws -> [FeedRecommendation] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags,user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "published_at", value: "is.null"),
            URLQueryItem(name: "items.type", value: "eq.trip"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load your drafts."))
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load this trip."))
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
    }

    /// Items on a List — list_id/list_section mirror trip_id/trip_section
    /// exactly, see fetchTripStops.
    func fetchListItems(listRecommendationId: String) async throws -> [FeedRecommendation] {
        let token = try await validToken()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,list_id,list_section,show_in_feed," +
            "items!inner(id,type,title,subtitle,image_url,genre,address)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "list_id", value: "eq.\(listRecommendationId)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load this list."))
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
    }

    /// Post-hoc "show on feed" toggle from ListDetailView — the same
    /// visibility choice made during import, editable indefinitely
    /// afterward, not just at import time.
    func updateShowInFeed(recommendationId: String, showInFeed: Bool) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(recommendationId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["show_in_feed": showInFeed])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't update that."))
        }
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

    /// Other books by the same author. There's no normalized author field —
    /// a book's subtitle is just the joined author names as OpenLibrary
    /// returned them (see RexSearch) — so this is a substring match against
    /// subtitle rather than an exact/foreign-key lookup. Good enough for
    /// "tap an author, see what else they wrote" without a schema change.
    func fetchBooksByAuthor(_ author: String) async throws -> [RexItem] {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,type,title,subtitle,image_url,genre"),
            URLQueryItem(name: "type", value: "eq.book"),
            URLQueryItem(name: "subtitle", value: "ilike.*\(author)*"),
            URLQueryItem(name: "order", value: "title.asc"),
            URLQueryItem(name: "limit", value: "100"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load books by this author.")
        }
        return try JSONDecoder().decode([RexItem].self, from: data)
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save your take."))
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

        // The catalogue has a uniqueness constraint on (external_source,
        // external_id) — two people picking the same Ticketmaster event or
        // Google place must land on the same item row. The web importer
        // already checks before inserting; this didn't, so re-adding
        // anything that already existed threw a raw Postgres 23505 straight
        // at the user ("Couldn't create this item... duplicate key value
        // violates unique constraint"). Look it up first and reuse it.
        let resolvedExternalId = externalId ?? hit?.externalId
        let resolvedExternalSource = externalSource ?? hit?.externalSource
        if let resolvedExternalId, let resolvedExternalSource,
           let existingId = try? await findItem(externalId: resolvedExternalId, externalSource: resolvedExternalSource) {
            return existingId
        }

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
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            // The lookup above closes the normal case; this only fires when
            // someone else's insert lands in the gap between our lookup and
            // our own insert. One more lookup resolves it instead of
            // surfacing Postgres's constraint error.
            if responseBody.contains("23505"), let resolvedExternalId, let resolvedExternalSource,
               let existingId = try? await findItem(externalId: resolvedExternalId, externalSource: resolvedExternalSource) {
                return existingId
            }
            throw RexAPIError.server("Couldn't create this item. \(responseBody)")
        }
        struct CreatedItem: Codable { let id: String }
        let created = try JSONDecoder().decode([CreatedItem].self, from: data)
        guard let itemId = created.first?.id else { throw RexAPIError.server("Item wasn't created.") }
        return itemId
    }

    /// An item already in the catalogue under this external id, if any.
    private func findItem(externalId: String, externalSource: String) async throws -> String? {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "external_id", value: "eq.\(externalId)"),
            URLQueryItem(name: "external_source", value: "eq.\(externalSource)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
        struct Row: Codable { let id: String }
        return (try? JSONDecoder().decode([Row].self, from: data))?.first?.id
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
        listId: String? = nil,
        listSection: String? = nil,
        showInFeed: Bool? = nil,
        anonymous: Bool = false,
        returningId: Bool = false,
        asDraft: Bool = false
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
        if let listId { body["list_id"] = listId }
        if let listSection, !listSection.isEmpty { body["list_section"] = listSection }
        if let showInFeed { body["show_in_feed"] = showInFeed }
        if anonymous { body["is_anonymous"] = true }
        // NULL published_at is what makes a row a draft — see migration
        // 20260815162631. Everything else (feed, item pages, map,
        // leaderboard) already excludes these via RLS, not a client filter,
        // so there's nothing else to thread this through.
        if asDraft { body["published_at"] = NSNull() }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        if returningId {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't post your Rex."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save."))
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

    /// #128 — this used to SELECT /rest/v1/profiles directly with an
    /// ilike filter, which reads correctly but was silently defeated by
    /// the RLS policy migration 20260727142816 tightened profiles SELECT
    /// down to "self, friends, or a pending friendship row" — so searching
    /// for anyone you're not already connected to (the whole point of
    /// searching) came back empty, 200 OK, no error. That same migration
    /// added a search_profiles() SECURITY DEFINER RPC specifically to
    /// bypass this for search, but the native app never called it. Now it
    /// does.
    func searchProfilesByUsername(_ query: String) async throws -> [RexProfileDetail] {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/rpc/search_profiles"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["_query": query, "_limit": 15])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Search failed."))
        }
        return try JSONDecoder().decode([RexProfileDetail].self, from: data)
    }

    /// Friends-of-friends, ranked by mutual count. Calls
    /// suggested_friends_for_me rather than the web's suggested_friends_for
    /// — that one takes an explicit _caller argument and is locked to
    /// service_role only (safe for the web's own server function, not safe
    /// to open up to any authenticated caller, who could pass someone
    /// else's id). The _for_me version reads auth.uid() internally instead,
    /// so it's safe to call directly. Needs migration
    /// 20260815151101_suggested_friends_for_me.sql run first.
    func fetchSuggestedFriends(limit: Int = 20) async throws -> [SuggestedFriend] {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/rpc/suggested_friends_for_me"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["_limit": limit])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load suggested friends."))
        }
        return try JSONDecoder().decode([SuggestedFriend].self, from: data)
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't send request."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't update request."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load notifications."))
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
            throw RexAPIError.server(friendlyError(upData, fallback: "Couldn't upload that photo."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save your profile."))
        }
    }

    /// #102 onboarding's "what are you interested in" step. Best-effort by
    /// design — called with `try?` from OnboardingView, since a failed save
    /// here shouldn't block someone from reaching their feed. Needs
    /// migration 20260816070000 run first; until then this just 400s
    /// quietly and the answer is lost, same tradeoff fetchRexCounts and
    /// friends make elsewhere in this file for not-yet-migrated columns.
    func updateInterests(_ categories: [RexCategory]) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["interests": categories.map(\.rawValue)])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save that."))
        }
    }

    // MARK: - Photos

    /// Uploads image data to the rec-photos bucket and returns a long-lived
    /// signed URL. Files go under the user's own folder, which is what the
    /// storage RLS policy checks.
    /// Downloads a Google Places photo using the headers its key restriction
    /// requires, and re-hosts it in our own storage. Returns nil rather than
    /// failing the save — a place without a picture still beats no place.
    /// Places thumbnails saved before this fix still carry Google's media URL,
    /// which never rendered (see copyGooglePhoto). There's no SQL backfill for
    /// this — Postgres can't fetch an external image — and items aren't
    /// per-user, so a one-off migration script would only fix what one
    /// session touches. Self-healing instead: cards call this once when they
    /// render, and whichever device happens to see a broken photo first
    /// fixes it for everyone, since the row is shared.
    private static var repairedItemIds = Set<String>()

    /// #146: same self-healing idea, for place/event items missing lat/lng —
    /// mostly Lovable-era Rex predating #135's geocode-on-add, which just
    /// silently never got a map pin (fetchMapPlaces drops anything without
    /// coordinates). No SQL backfill here either, for the same reason as
    /// repairPlacePhotoIfNeeded: geocoding needs an external API call.
    private static var geocodeRepairedItemIds = Set<String>()

    /// Geocodes `address` and writes the result back onto the item if it
    /// resolves. Returns the coordinates so the caller can show the pin
    /// immediately rather than waiting for the next map load.
    func repairPlaceCoordsIfNeeded(itemId: String, address: String) async -> (lat: Double, lng: Double)? {
        guard !Self.geocodeRepairedItemIds.contains(itemId) else { return nil }
        Self.geocodeRepairedItemIds.insert(itemId)

        guard let located = await RexSearch.geocode(address) else { return nil }
        guard let token = try? await validToken() else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["lat": located.lat, "lng": located.lng])
        _ = try? await URLSession.shared.data(for: request)
        return located
    }

    func repairPlacePhotoIfNeeded(itemId: String, imageURL: String?) async {
        guard let imageURL, imageURL.contains("places.googleapis.com") else { return }
        guard !Self.repairedItemIds.contains(itemId) else { return }
        Self.repairedItemIds.insert(itemId)

        guard let fixed = await copyGooglePhoto(imageURL) else { return }
        let token = try? await validToken()
        guard let token else { return }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["image_url": fixed])
        _ = try? await URLSession.shared.data(for: request)
    }

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
            throw RexAPIError.server(friendlyError(upData, fallback: "Couldn't upload that photo."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save your changes."))
        }
    }

    /// Items are shared across everyone who's Rex'd them (not per-user like
    /// the fields above), so this fixes the title for the catalogue entry
    /// itself, not just your own take on it — same model already used for
    /// repairPlacePhotoIfNeeded, and RLS already permits any authenticated
    /// user to update an item, not just whoever first created it.
    func updateItemTitle(itemId: String, title: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't update the title."))
        }
    }

    /// #125 — same "shared catalogue entry, not your own take" model as
    /// updateItemTitle, for the thumbnail instead. nil clears it back to the
    /// category's generic placeholder icon rather than leaving a broken URL.
    func updateItemImageURL(itemId: String, imageURL: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["image_url": imageURL ?? (NSNull() as Any)]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't update the thumbnail."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't delete that Rex."))
        }
    }

    // MARK: - Trip editing (#122)

    /// Bulk-renames a heading across every stop that carries it. A heading
    /// isn't its own row anywhere — it's just the trip_section string
    /// repeated on however many stops share it — so renaming means patching
    /// every one of them in a single request rather than one row.
    func renameTripSection(tripId: String, from: String?, to: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "trip_id", value: "eq.\(tripId)"),
            URLQueryItem(name: "trip_section", value: (from?.isEmpty ?? true) ? "is.null" : "eq.\(from!)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["trip_section": (to?.isEmpty ?? true) ? NSNull() : to!]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't rename that heading."))
        }
    }

    /// Reordering has no dedicated sort column to write to — a stop's
    /// position is just where its created_at falls among its trip siblings
    /// (see fetchTripStops' order: created_at.asc). To move one stop up or
    /// down within its heading, swap timestamps with its neighbour instead
    /// of inventing a new one — that way both stops stay inside the same
    /// heading's original time range, so this can never accidentally bleed
    /// a stop into a different heading's position in the overall itinerary.
    func setRecommendationCreatedAt(id: String, createdAt: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["created_at": createdAt])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't reorder that stop."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load the leaderboard."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't add that to your collection."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't create that collection."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't rename that collection."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't change who can see that."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't delete that collection."))
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
                is_anonymous: false,
                list_section: nil,
                show_in_feed: nil
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't send your blast."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't send that."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load comments."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't post your comment."))
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

    /// A friend's collections worth discovering — never their private
    /// (`draft`) ones, those aren't yours to see.
    func fetchLists(forUser userId: String) async throws -> [RexList] {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/hitlist_lists"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,name,emoji,item_type,visibility,created_at,user_id"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "visibility", value: "in.(public,friends)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        return (try? JSONDecoder().decode([RexList].self, from: data)) ?? []
    }

    /// Save a friend's collection into your own "Friends' Collections" shelf.
    func followList(listId: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/list_follows"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["user_id": userId, "list_id": listId])
        var urlComponents = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,list_id")]
        request.url = urlComponents.url
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save that collection."))
        }
    }

    func unfollowList(listId: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/list_follows"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "list_id", value: "eq.\(listId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
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

    /// Explore tab's "missed from your friends" shelf: every accepted
    /// friend's visible collections, minus ones already followed or
    /// collaborated on (those already have a home on the Collections tab,
    /// so surfacing them again here would just be noise). One request per
    /// friend, run concurrently — fine at friend-list sizes this app deals
    /// with, same tradeoff CollectionsView's loadContents already makes.
    func fetchFriendsCollectionsToExplore(limit: Int = 12) async throws -> [RexList] {
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        async let friendshipsTask = fetchFriendships()
        async let followedTask = fetchFollowedLists()
        async let collaboratingTask = fetchCollaboratingLists()
        let (friendships, followed, collaborating) = try await (friendshipsTask, followedTask, collaboratingTask)

        let friendIds = friendships
            .filter { $0.status == "accepted" }
            .map { $0.requester_id == userId ? $0.addressee_id : $0.requester_id }
        guard !friendIds.isEmpty else { return [] }

        let alreadyHave = Set((followed + collaborating).map(\.id))
        let lists = await withTaskGroup(of: [RexList].self) { group in
            for friendId in friendIds {
                group.addTask { (try? await self.fetchLists(forUser: friendId)) ?? [] }
            }
            var all: [RexList] = []
            for await lists in group { all.append(contentsOf: lists) }
            return all
        }

        return lists
            .filter { !alreadyHave.contains($0.id) }
            .sorted { ($0.created_at ?? "") > ($1.created_at ?? "") }
            .prefix(limit)
            .map { $0 }
    }

    /// Explore tab's "trending this week" shelf.
    func fetchTrendingItems(limit: Int = 12) async throws -> [TrendingItem] {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/rpc/trending_items_weekly"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["_limit": limit])

        let (data, response) = try await URLSession.shared.data(for: request)
        // Best-effort: needs migration 20260816094500 run first.
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        return (try? JSONDecoder().decode([TrendingItem].self, from: data)) ?? []
    }

    /// Explore tab's REX-curated shelves ("REX Team" picks and anything
    /// credited to an outside source, both written by the three named
    /// curators — see is_rex_curator() in the migration).
    func fetchEditorialCollections() async throws -> [EditorialCollection] {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/editorial_collections"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,title,source_label,category,editorial_collection_items(id,title,subtitle,image_url,item_id,link_url,sort_order)"),
            URLQueryItem(name: "order", value: "sort_order.asc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        // Best-effort: needs migration 20260816094500 run first.
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        return (try? JSONDecoder().decode([EditorialCollection].self, from: data)) ?? []
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load your saved posts."))
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load that collection."))
        }
        return try JSONDecoder().decode([SavedPost].self, from: data)
    }

    func fetchWants() async throws -> [WantRow] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,created_at,item_id,list_id,items(id,type,title,subtitle,image_url,genre,address)"),
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

    /// Puts a want in a collection, or takes it out (listId: nil). Unlike a
    /// Rex — which can sit in several collections via saved_posts — a want
    /// only ever belongs to one, directly via wants.list_id (that column
    /// already existed, just unused by any client until now).
    func setWantList(wantId: String, listId: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(wantId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["list_id": listId == nil ? NSNull() : listId!]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't update that collection."))
        }
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
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't remove."))
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
            // Used to be neq.\(userId) — "your own wants already live on
            // your list; the feed is other people." Kathryn asked directly
            // to see her own want-to-trys on her own feed too, so this now
            // pulls everyone's, same as the rest of the feed does.
            URLQueryItem(name: "order", value: "created_at.desc"),
            // Was 30 — a want to try has no rating and often no note either,
            // so it's easy for a page this small to end up entirely stale
            // ones from a quiet week rather than anything recent.
            URLQueryItem(name: "limit", value: "100"),
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
                is_anonymous: false,
                list_section: nil,
                show_in_feed: nil
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

    /// Item ids for a set of recommendations, keyed by the recommendation id —
    /// what a "rec_like"/"rec_comment"/"rec_saved"/"mention"/"friend_new_rec"
    /// notification carries in entity_id. Notifications can outlive the
    /// recommendation they point at (e.g. you deleted the Rex after someone
    /// liked it), so a missing key here just means "nothing to open" rather
    /// than an error — callers should treat an absent id as non-fatal.
    func fetchItemIds(forRecommendations recommendationIds: [String]) async throws -> [String: String] {
        guard !recommendationIds.isEmpty else { return [:] }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,item_id"),
            URLQueryItem(name: "id", value: "in.(\(recommendationIds.joined(separator: ",")))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [:] }
        struct Row: Codable { let id: String; let item_id: String }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.item_id) })
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
        // lat/lng are nullable in the schema even though we need them to
        // place a pin. #146: rather than just dropping every place that's
        // missing one — mostly Lovable-era Rex from before #135 added
        // geocoding to the add-a-place flow — try to geocode it from its
        // address first, same self-healing pattern as repairPlacePhotoIfNeeded.
        let repaired = await withTaskGroup(of: MapPlace.self) { group in
            for place in places {
                group.addTask {
                    guard place.lat == nil || place.lng == nil,
                          let address = place.address, !address.isEmpty,
                          let located = await self.repairPlaceCoordsIfNeeded(itemId: place.id, address: address)
                    else { return place }
                    return MapPlace(
                        id: place.id, title: place.title, subtitle: place.subtitle, type: place.type,
                        genre: place.genre, address: place.address, lat: located.lat, lng: located.lng,
                        image_url: place.image_url, recommendations: place.recommendations
                    )
                }
            }
            var results: [MapPlace] = []
            for await place in group { results.append(place) }
            return results
        }
        return repaired.filter { $0.lat != nil && $0.lng != nil }
    }

    /// A specific trip's own stops, regardless of whether they're in
    /// fetchMapPlaces' most-recent-200 sample. "Following" a trip used to
    /// only work if its stops happened to already be loaded, which was fine
    /// when the only way to pick a trip was tapping a chip built from that
    /// same sample — TripSearchView breaks that assumption by letting you
    /// pick any trip, so following it needs its own fetch.
    func fetchMapPlaces(forTrip tripRecommendationId: String) async throws -> [MapPlace] {
        let token = try await validToken()
        let select = "id,title,subtitle,type,genre,address,lat,lng,image_url," +
            "recommendations!inner(id,rating,user_id,trip_id,profiles(username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "type", value: "in.(place,event)"),
            URLQueryItem(name: "recommendations.trip_id", value: "eq.\(tripRecommendationId)"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load this trip's stops."))
        }
        let places = try JSONDecoder().decode([MapPlace].self, from: data)
        return places.filter { $0.lat != nil && $0.lng != nil }
    }

    /// One specific place/event, regardless of whether it's in
    /// fetchMapPlaces' most-recent-200 sample — #133's "view on map" needs
    /// to guarantee the pin it's jumping to actually loads, the same reason
    /// fetchMapPlaces(forTrip:) exists rather than trusting the sample.
    func fetchMapPlace(itemId: String) async throws -> MapPlace? {
        let token = try await validToken()
        let select = "id,title,subtitle,type,genre,address,lat,lng,image_url," +
            "recommendations!inner(id,rating,user_id,trip_id,profiles(username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "id", value: "eq.\(itemId)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load that place."))
        }
        var place = (try? JSONDecoder().decode([MapPlace].self, from: data))?.first
        // Same self-heal as fetchMapPlaces — jumping to a place with no
        // coordinates yet (#146) should still work, not just show nothing.
        if let p = place, p.lat == nil || p.lng == nil, let address = p.address, !address.isEmpty,
           let located = await repairPlaceCoordsIfNeeded(itemId: p.id, address: address) {
            place = MapPlace(
                id: p.id, title: p.title, subtitle: p.subtitle, type: p.type,
                genre: p.genre, address: p.address, lat: located.lat, lng: located.lng,
                image_url: p.image_url, recommendations: p.recommendations
            )
        }
        return place
    }

    // MARK: - Import (#109 "Lists" category, #15/#38 native trip import)

    /// Sends pasted text to the extract-recommendations edge function and
    /// gets back the parsed items — nothing touches the database here. The
    /// LLM call is the one piece of this pipeline that needs a secret
    /// (ANTHROPIC_API_KEY), which is why it's the one piece not done as a
    /// plain PostgREST call the way everything else in this file is.
    func extractRecommendations(text: String) async throws -> [ExtractedRec] {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("/functions/v1/extract-recommendations"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't read recommendations out of that text."))
        }
        struct Response: Codable { let items: [ExtractedRec] }
        return try JSONDecoder().decode(Response.self, from: data).items
    }

    /// #21 — a photo of a recipe (cookbook page, handwritten card,
    /// screenshot) transcribed to plain text. The caller feeds the result
    /// through RexRecipe.parse(), same as "paste whole recipe" — this only
    /// does the OCR/transcription step, not structured extraction, so
    /// photo-import and paste-import end up behaving identically.
    func extractRecipeFromPhoto(_ jpegData: Data) async throws -> (title: String?, text: String) {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("/functions/v1/extract-recipe-photo"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "imageBase64": jpegData.base64EncodedString(),
            "mediaType": "image/jpeg",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't read that recipe photo."))
        }
        struct Response: Codable { let title: String?; let text: String }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.title, decoded.text)
    }

    /// Stages extracted items for review — nothing becomes a real Rex until
    /// the user approves it (individually, or in bulk as a trip/collection).
    @discardableResult
    func insertStagingRows(_ items: [ExtractedRec], source: String) async throws -> Int {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let rows: [[String: Any]] = items.prefix(200).map { item in
            var row: [String: Any] = [
                "user_id": userId,
                "source": source,
                "raw_title": String(item.title.prefix(300)),
                "status": "pending",
            ]
            row["raw_creator"] = item.creator.map { String($0.prefix(200)) } ?? NSNull()
            row["raw_note"] = item.note.map { String($0.prefix(2000)) } ?? NSNull()
            row["raw_rating"] = item.rating.map { max(1, min(10, $0)) } ?? NSNull()
            row["suggested_type"] = item.type ?? NSNull()
            let section = item.section?.trimmingCharacters(in: .whitespaces)
            row["raw_section"] = (section?.isEmpty == false ? String(section!.prefix(120)) : nil) ?? NSNull()
            let url = item.url?.trimmingCharacters(in: .whitespaces)
            row["raw_url"] = (url?.isEmpty == false ? String(url!.prefix(2000)) : nil) ?? NSNull()
            return row
        }
        guard !rows.isEmpty else { return 0 }

        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/import_staging"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: rows)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save the extracted items."))
        }
        return rows.count
    }

    func fetchStagingRows(source: String) async throws -> [ImportStagingRow] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/import_staging"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "source", value: "eq.\(source)"),
            URLQueryItem(name: "status", value: "eq.pending"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load what was extracted."))
        }
        return try JSONDecoder().decode([ImportStagingRow].self, from: data)
    }

    /// Drops rows the user deselected during review — declining is real
    /// deletion, not just a client-side filter, so a re-opened review
    /// doesn't resurrect things already dismissed.
    func deleteStagingRows(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/import_staging"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't remove that."))
        }
    }

    /// Fixes up a row before it's approved — the AI's guess at title,
    /// creator, note, rating, or type isn't always right, and there was no
    /// way to correct that short of discarding the row and posting as-is.
    /// A cleared resolved_item_id/resolved_external_id forces
    /// approveOneStagingRow to create a fresh item on next approval rather
    /// than reusing whatever resolveStagingRow matched against the old
    /// (now-edited) title.
    func updateStagingRow(
        id: String, title: String, creator: String?, note: String?, rating: Double?, type: String
    ) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/import_staging"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "raw_title": title,
            "suggested_type": type,
            "resolved_item_id": NSNull(),
            "resolved_external_id": NSNull(),
            "resolved_external_source": NSNull(),
        ]
        body["raw_creator"] = creator?.isEmpty == false ? creator : NSNull()
        body["raw_note"] = note?.isEmpty == false ? note : NSNull()
        body["raw_rating"] = rating ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save that change."))
        }
    }

    /// Best-effort match against the app's own search — same catalogues
    /// (OpenLibrary, TMDB, Google Places) Add-a-Rex already searches, run
    /// client-side rather than through a server round trip since the native
    /// app already has direct clients for all four. A miss just leaves the
    /// row unresolved; approving it still works, it just creates a plain
    /// unlinked item the way manual entry always has.
    func resolveStagingRow(_ row: ImportStagingRow) async throws {
        guard let type = row.suggested_type else { return }
        let category: RexCategory
        switch type {
        case "book": category = .book
        case "movie": category = .movie
        case "tv": category = .tv
        case "place": category = .place
        default: return
        }
        let query = [row.raw_title, row.raw_creator].compactMap { $0 }.joined(separator: " ")
        guard let hit = await RexSearch.search(category: category, query: query).first else { return }

        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/import_staging"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(row.id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var patchBody: [String: Any] = [
            "resolved_external_id": hit.externalId,
            "resolved_external_source": hit.externalSource,
        ]
        patchBody["resolved_image_url"] = hit.imageURL ?? NSNull()
        patchBody["resolved_subtitle"] = hit.subtitle ?? row.raw_creator ?? NSNull()
        patchBody["resolved_genre"] = hit.genre ?? NSNull()
        request.httpBody = try JSONSerialization.data(withJSONObject: patchBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't resolve this item."))
        }
    }

    /// A staged row succeeded or failed to become a real Rex; batch imports
    /// name every miss instead of letting it vanish silently, matching the
    /// web importer's own "16 of 36 stops landed" transparency.
    struct ImportFailure { let title: String; let reason: String }

    /// One staging row -> a real item (find-or-create) + recommendation,
    /// then marks the row imported. Mirrors the web importer's approveRow
    /// (src/lib/import.functions.ts) step for step, including reusing
    /// createItem's own find-or-create-by-external-id behavior rather than
    /// re-implementing that lookup here.
    @discardableResult
    private func approveOneStagingRow(
        _ row: ImportStagingRow,
        rating: Double?,
        note: String?,
        tripId: String?,
        tripSection: String?,
        listId: String?,
        // Named docListId/docListSection to keep clear of the parameter
        // above — that `listId` means "add to this Collection"
        // (saved_posts), an entirely different thing from a List-type Rex's
        // own list_id linkage. showInFeed only applies alongside docListId.
        docListId: String? = nil,
        docListSection: String? = nil,
        showInFeed: Bool? = nil
    ) async throws -> String {
        guard let type = row.suggested_type, !type.isEmpty else {
            throw RexAPIError.server("Set a type before approving.")
        }
        let itemId: String
        if let existing = row.resolved_item_id {
            itemId = existing
        } else {
            // #135 — the document importer never geocoded anything, so a
            // trip/list brought in this way had stops with no coordinates
            // at all and no pins on the map. raw_creator often carries a
            // city or cuisine for a place row ("cuisine or city for
            // places", same convention the extraction prompt uses), which
            // helps disambiguate a name like "The Ivy" that exists in
            // several cities. Best-effort — a row that doesn't geocode
            // just stays pinless the way it already did.
            var geocodedLat: Double?
            var geocodedLng: Double?
            if type == "place" || type == "event" {
                let query = [row.raw_title, row.raw_creator]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                if let located = await RexSearch.geocode(query) {
                    geocodedLat = located.lat
                    geocodedLng = located.lng
                }
            }
            itemId = try await createItem(
                type: type,
                title: row.raw_title,
                subtitle: row.resolved_subtitle ?? row.raw_creator,
                address: nil,
                genre: row.resolved_genre,
                linkURL: row.raw_url,
                externalId: row.resolved_external_id,
                externalSource: row.resolved_external_source,
                imageURL: row.resolved_image_url,
                lat: geocodedLat,
                lng: geocodedLng
            )
        }

        let finalRating = rating ?? row.raw_rating.map { max(1, min(10, $0.rounded())) } ?? 8
        let recId = try await createRecommendation(
            itemId: itemId,
            rating: finalRating,
            note: note ?? row.raw_note,
            tripId: tripId,
            tripSection: tripId != nil ? tripSection : nil,
            listId: docListId,
            listSection: docListId != nil ? docListSection : nil,
            showInFeed: docListId != nil ? showInFeed : nil,
            returningId: true
        )

        if let listId {
            try await addToCollection(recommendationId: recId, listId: listId)
        }

        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/import_staging"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(row.id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": "imported", "resolved_item_id": itemId])
        _ = try? await URLSession.shared.data(for: request)

        return itemId
    }

    /// Approves one staged row on its own — the individual-review path,
    /// as opposed to the batch trip/collection/list paths below.
    @discardableResult
    func approveStagingRow(_ row: ImportStagingRow, rating: Double? = nil, note: String? = nil) async throws -> String {
        try await approveOneStagingRow(row, rating: rating, note: note, tripId: nil, tripSection: nil, listId: nil)
    }

    /// Turns a batch of staged rows into one new Trip, each row becoming a
    /// stop under the heading it was extracted with (raw_section) — the
    /// document's own structure carries straight through, same as the web
    /// importer's approveStagingAsTrip.
    func approveStagingAsTrip(
        rows: [ImportStagingRow], tripName: String, note: String?
    ) async throws -> (tripId: String, added: Int, failed: [ImportFailure]) {
        guard !rows.isEmpty else { throw RexAPIError.server("Nothing to import.") }
        let tripItemId = try await createItem(type: "trip", title: tripName.trimmingCharacters(in: .whitespaces), subtitle: nil, address: nil)
        let tripRecId = try await createRecommendation(itemId: tripItemId, rating: 8, note: note, returningId: true)

        var added = 0
        var failed: [ImportFailure] = []
        for row in rows {
            do {
                try await approveOneStagingRow(row, rating: nil, note: nil, tripId: tripRecId, tripSection: row.raw_section, listId: nil)
                added += 1
            } catch {
                failed.append(ImportFailure(title: row.raw_title, reason: error.localizedDescription))
            }
        }
        return (tripRecId, added, failed)
    }

    /// Turns a batch of staged rows into one new List — structurally
    /// identical to approveStagingAsTrip (one parent Rex, items linked
    /// underneath via list_id/list_section instead of trip_id/trip_section)
    /// with one difference: showInFeedIds carries which rows should default
    /// visible on the main feed on their own, since unlike trip stops
    /// (always hidden) a list item's visibility is a per-row choice made on
    /// the review screen.
    func approveStagingAsList(
        rows: [ImportStagingRow], listName: String, kind: String, note: String?, showInFeedIds: Set<String>
    ) async throws -> (listId: String, added: Int, failed: [ImportFailure]) {
        guard !rows.isEmpty else { throw RexAPIError.server("Nothing to import.") }
        let listItemId = try await createItem(
            type: "list", title: listName.trimmingCharacters(in: .whitespaces), subtitle: nil, address: nil,
            genre: kind.isEmpty ? nil : kind
        )
        let listRecId = try await createRecommendation(itemId: listItemId, rating: 8, note: note, returningId: true)

        var added = 0
        var failed: [ImportFailure] = []
        for row in rows {
            do {
                try await approveOneStagingRow(
                    row, rating: nil, note: nil, tripId: nil, tripSection: nil, listId: nil,
                    docListId: listRecId, docListSection: row.raw_section, showInFeed: showInFeedIds.contains(row.id)
                )
                added += 1
            } catch {
                failed.append(ImportFailure(title: row.raw_title, reason: error.localizedDescription))
            }
        }
        return (listRecId, added, failed)
    }

    /// Turns a batch of staged rows into one or more Collections. With
    /// splitBySection on, a document organised under headings ("Pubs",
    /// "Galleries") becomes one collection per heading instead of a single
    /// dumping-ground list — same behavior as the web importer's
    /// approveStagingAsCollections.
    func approveStagingAsCollections(
        rows: [ImportStagingRow], name: String, splitBySection: Bool
    ) async throws -> (added: Int, collections: Int, failed: [ImportFailure]) {
        guard !rows.isEmpty else { throw RexAPIError.server("Nothing to import.") }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        var order: [String] = []
        var groups: [String: [ImportStagingRow]] = [:]
        for row in rows {
            let section = splitBySection ? row.raw_section?.trimmingCharacters(in: .whitespaces) : nil
            let key = (section?.isEmpty == false ? section! : nil) ?? trimmedName
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }

        var added = 0
        var failed: [ImportFailure] = []
        for key in order {
            let groupRows = groups[key] ?? []
            var counts: [String: Int] = [:]
            for r in groupRows {
                if let t = r.suggested_type { counts[t, default: 0] += 1 }
            }
            let itemType = counts.max(by: { $0.value < $1.value })?.key ?? "other"
            let listId = try await createCollection(name: key, emoji: nil, itemType: itemType)

            for row in groupRows {
                do {
                    try await approveOneStagingRow(row, rating: nil, note: nil, tripId: nil, tripSection: nil, listId: listId)
                    added += 1
                } catch {
                    failed.append(ImportFailure(title: row.raw_title, reason: error.localizedDescription))
                }
            }
        }
        return (added, order.count, failed)
    }
}
