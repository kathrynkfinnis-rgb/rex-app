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

    /// #182 — records that this account explicitly agreed to the Terms of
    /// Use / Privacy Policy at sign-up (the LegalContentView checkbox),
    /// so there's a real timestamped record rather than just trusting the
    /// UI state. Best-effort: a failure here shouldn't block someone from
    /// actually getting into the app they just signed up for — the
    /// checkbox itself is still the real gate on the sign-up screen.
    // MARK: - Privacy: consent, export, deletion (15 Sept)

    /// Records agreement to the current Terms of Use + Privacy Policy: a
    /// new row in consent_log (never overwritten — that's what makes it a
    /// record), and the latest version on the profile so the app can tell
    /// when to ask again. Falls back to just the old timestamp column if
    /// the 15 Sept migration hasn't run yet.
    func recordConsent(source: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let appVersion = [Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                          Bundle.main.infoDictionary?["CFBundleVersion"] as? String]
            .compactMap { $0 }.joined(separator: " (") + ")"

        var logRequest = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/consent_log"))
        logRequest.httpMethod = "POST"
        logRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        logRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        logRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        logRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": userId, "document": "terms_privacy", "version": RexLegal.version,
            "source": source, "app_version": appVersion,
        ])
        let (_, logResponse) = try await URLSession.shared.data(for: logRequest)
        let logged = ((logResponse as? HTTPURLResponse)?.statusCode ?? 500) < 400

        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["accepted_terms_at": ISO8601DateFormatter().string(from: Date())]
        if logged { body["accepted_terms_version"] = RexLegal.version }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't record that — please try again."))
        }
    }

    /// True when this account hasn't agreed to the current version. False
    /// before the migration runs (nothing to compare against), so nobody is
    /// stopped at the door by a question the database can't record.
    func consentNeedsUpdate() async -> Bool {
        guard let userId = currentUserId, let token = try? await validToken() else { return false }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "accepted_terms_version"),
            URLQueryItem(name: "id", value: "eq.\(userId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400 else { return false }
        struct Row: Codable { let accepted_terms_version: String? }
        guard let row = (try? JSONDecoder().decode([Row].self, from: data))?.first else { return false }
        return row.accepted_terms_version != RexLegal.version
    }

    /// Everything REX holds about you, as one JSON document — the "download
    /// my data" right. Read with your own session, so it's exactly what the
    /// database's access rules say is yours. A section that fails is
    /// recorded as such in the file rather than failing the whole export.
    func exportMyData() async throws -> URL {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }

        func get(_ path: String, _ query: [String: String]) async -> Any {
            var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, response) = try? await URLSession.shared.data(for: request) else {
                return ["error": "couldn't be read"]
            }
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
                return ["error": "couldn't be read (\((response as? HTTPURLResponse)?.statusCode ?? 0))"]
            }
            return (try? JSONSerialization.jsonObject(with: data)) ?? ["error": "unreadable"]
        }
        let mine = "eq.\(userId)"

        var export: [String: Any] = [
            "about": "Your REX data, exported \(ISO8601DateFormatter().string(from: Date())). Photos are linked by URL rather than included.",
            "account": await get("/auth/v1/user", [:]),
        ]
        export["profile"] = await get("/rest/v1/profiles", ["id": mine, "select": "*"])
        export["recommendations"] = await get("/rest/v1/recommendations", ["user_id": mine, "select": "*,items(*)", "order": "created_at.asc"])
        export["wants_to_try"] = await get("/rest/v1/wants", ["user_id": mine, "select": "*,items(*)", "order": "created_at.asc"])
        export["collections"] = await get("/rest/v1/hitlist_lists", ["user_id": mine, "select": "*"])
        export["collection_entries"] = await get("/rest/v1/saved_posts", ["user_id": mine, "select": "*"])
        export["followed_collections"] = await get("/rest/v1/list_follows", ["user_id": mine, "select": "*"])
        export["blasts"] = await get("/rest/v1/requests", ["user_id": mine, "select": "*"])
        export["comments"] = [
            "on_rex": await get("/rest/v1/recommendation_comments", ["user_id": mine, "select": "*"]),
            "on_wants": await get("/rest/v1/want_comments", ["user_id": mine, "select": "*"]),
            "on_blasts": await get("/rest/v1/request_comments", ["user_id": mine, "select": "*"]),
        ]
        export["likes"] = [
            "rex": await get("/rest/v1/recommendation_likes", ["user_id": mine, "select": "*"]),
            "wants": await get("/rest/v1/want_likes", ["user_id": mine, "select": "*"]),
            "blast_replies": await get("/rest/v1/request_comment_likes", ["user_id": mine, "select": "*"]),
        ]
        export["friendships"] = await get("/rest/v1/friendships", ["select": "*"])
        export["top_friends"] = await get("/rest/v1/top_friends", ["user_id": mine, "select": "*"])
        export["notification_settings"] = await get("/rest/v1/notification_preferences", ["user_id": mine, "select": "*"])
        export["notifications"] = await get("/rest/v1/notifications", ["user_id": mine, "select": "*"])
        export["feedback_sent"] = await get("/rest/v1/feedback", ["user_id": mine, "select": "*"])
        export["consent_history"] = await get("/rest/v1/consent_log", ["user_id": mine, "select": "*", "order": "accepted_at.asc"])

        let data = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rex-data-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Deletes every photo you've uploaded, from both buckets. Photos live
    /// under a folder named for your user id (the Storage policies only let
    /// you touch your own folder), so it's list-then-delete per bucket.
    private func deleteMyStorageFiles() async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        for bucket in ["avatars", "rec-photos"] {
            while true {
                var list = URLRequest(url: baseURL.appendingPathComponent("/storage/v1/object/list/\(bucket)"))
                list.httpMethod = "POST"
                list.setValue(anonKey, forHTTPHeaderField: "apikey")
                list.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                list.setValue("application/json", forHTTPHeaderField: "Content-Type")
                list.httpBody = try JSONSerialization.data(withJSONObject: ["prefix": "\(userId)/", "limit": 500, "offset": 0])
                let (data, response) = try await URLSession.shared.data(for: list)
                guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { break }
                struct Object: Codable { let name: String }
                let names = ((try? JSONDecoder().decode([Object].self, from: data)) ?? []).map { "\(userId)/\($0.name)" }
                if names.isEmpty { break }

                var remove = URLRequest(url: baseURL.appendingPathComponent("/storage/v1/object/\(bucket)"))
                remove.httpMethod = "DELETE"
                remove.setValue(anonKey, forHTTPHeaderField: "apikey")
                remove.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                remove.setValue("application/json", forHTTPHeaderField: "Content-Type")
                remove.httpBody = try JSONSerialization.data(withJSONObject: ["prefixes": names])
                let (_, removed) = try await URLSession.shared.data(for: remove)
                guard ((removed as? HTTPURLResponse)?.statusCode ?? 500) < 400 else {
                    throw RexAPIError.server("Couldn't delete your photos — nothing else has been deleted yet. Please try again.")
                }
                if names.count < 500 { break }
            }
        }
    }

    /// "Delete my account and data." Photos first (the database can't reach
    /// Storage), then delete_my_account(), which removes the login and
    /// everything that hangs off it. Signs out locally at the end.
    func deleteMyAccount() async throws {
        let token = try await validToken()
        try await deleteMyStorageFiles()

        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/rpc/delete_my_account"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't delete your account. Please try again, or email kathryn.k.finnis@gmail.com."))
        }

        // Nothing of this account should linger on the phone either.
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("rex.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        TripDraftStore.clear()
        signOut()
    }

    /// Kept for the existing sign-up call sites — see recordConsent.
    func recordTermsAcceptance() async {
        try? await recordConsent(source: "signup")
    }

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
    /// #181 — whether the recommendations_display view (the anonymous-post
    /// identity mask: null profile instead of the real one, whenever
    /// is_anonymous and you're not the owner) exists yet. Same
    /// probe-once-and-remember shape as anonymousColumn/wantNoteColumn,
    /// but a missing VIEW isn't something you can drop a column to work
    /// around — the whole resource 400s — so fetchFeed falls all the way
    /// back to querying the base table (with the un-masked embed, i.e.
    /// today's pre-#181 behaviour) rather than the entire main feed going
    /// blank until this migration's been run.
    private var recommendationsDisplayView: Bool?

    private func useRecommendationsDisplayView() async -> Bool {
        if let recommendationsDisplayView { return recommendationsDisplayView }
        guard let token = try? await validToken() else { return false }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations_display"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "select", value: "id"), URLQueryItem(name: "limit", value: "1")]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let ok = (try? await URLSession.shared.data(for: request))
            .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
            .map { $0 < 400 } ?? false
        recommendationsDisplayView = ok
        return ok
    }

    /// #181, part two — fetchFeed got its own inline version of this dance
    /// (it also needs `useView` separately, for the search-filter
    /// dot-vs-jsonb-arrow syntax). Every other function that reads straight
    /// from recommendations just needs the resource path and the profiles
    /// select fragment, so they go through this instead of repeating the
    /// probe-and-fallback inline each time.
    private func recommendationsReadPath() async -> (path: String, profilesSelect: String) {
        let useView = await useRecommendationsDisplayView()
        return (
            useView ? "/rest/v1/recommendations_display" : "/rest/v1/recommendations",
            useView ? "profiles" : "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)"
        )
    }

    /// `offset` pages the unfiltered feed — see FeedView.loadMore.
    func fetchFeed(category: String? = nil, searchText: String? = nil, offset: Int = 0) async throws -> [FeedRecommendation] {
        let token = try await validToken()
        let useView = await useRecommendationsDisplayView()
        let resourcePath = useView ? "/rest/v1/recommendations_display" : "/rest/v1/recommendations"
        // The view returns profiles as a plain (already-masked) jsonb
        // column instead of an automatic FK embed — replacing the embed
        // with a CASE would have broken PostgREST's relationship
        // inference, which needs a plain, unmodified FK column to trace.
        // Everything else about the row is an untouched passthrough, so
        // items!inner(...)/creators(...)/recommendation_tags(...) keep
        // working exactly as before either way.
        // "can't edit any of the details" on a recipe — recipe_text was
        // missing from every one of this select string's copies across
        // this file (fetchFeed and its siblings), so whatever recommendation
        // EditRexView opened from always carried a nil recipe_text
        // regardless of what was actually saved. RecipeEditorView's own
        // onAppear guard (`if !parsed.ingredients.isEmpty { ingredients =
        // parsed.ingredients }`) then had nothing to parse, so it never
        // overwrote its default single blank row — the editor opened, it
        // just always looked empty. Added to every occurrence of this
        // select shape in the file, not just this one.
        let profilesSelect = useView ? "profiles" : "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)"
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)," +
            "\(profilesSelect)," +
            "creators(slug,name,color,emoji)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"

        let trimmedSearch = searchText?.trimmingCharacters(in: .whitespaces)
        let isFiltered = category != nil || !(trimmedSearch ?? "").isEmpty
        // The default view loads a page at a time — 50, then another 50 as
        // you reach the bottom (see `offset` and FeedView.loadMore).
        //
        // Sept 5 — "the search bar on the feed should search the full
        // database, not just what is automatically loaded". It already
        // queried the server rather than re-slicing the loaded page, but
        // 300 was still a cap someone with a lot of history could hit, so
        // it's 1000 now: a search is deliberate, runs once, and finding
        // the thing matters more than shaving a few hundred milliseconds.
        let limit = isFiltered ? 1000 : 50

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
        // `extraFilters` is a list of (name, value) query items, all AND'd
        // onto the request — #151: this used to be a single optional tuple,
        // which meant search (needing one field-match filter) and the
        // category chip (needing its own type filter) could never both
        // apply at once. Picking "Trip" and typing a search query silently
        // dropped the category and searched every type instead.
        func fetch(includeListFilter: Bool, extraFilters: [(String, String)] = []) async throws -> (Data, HTTPURLResponse) {
            var components = URLComponents(url: baseURL.appendingPathComponent(resourcePath), resolvingAgainstBaseURL: false)!
            var queryItems = [
                URLQueryItem(name: "select", value: select),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)"),
            ]
            // Sept 2 — "individual Rex should still be searchable in the
            // feed though". trip_id.is.null used to be unconditional here,
            // which correctly keeps a trip's stops out of the browse feed
            // (you want the trip, not fifteen cards for its stops) but also
            // meant searching for a restaurant you'd Rex'd *as a stop on a
            // trip* found nothing at all. Browsing still hides them; an
            // active search or category filter now reaches them, which is
            // the only time you've actually asked for something specific.
            if !isFiltered {
                queryItems.append(URLQueryItem(name: "trip_id", value: "is.null"))
            }
            for filter in extraFilters { queryItems.append(URLQueryItem(name: filter.0, value: filter.1)) }
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

        func decodedPage(includeListFilter: Bool, extraFilters: [(String, String)] = []) async throws -> [FeedRecommendation] {
            var (data, http) = try await fetch(includeListFilter: includeListFilter, extraFilters: extraFilters)
            if http.statusCode == 400, includeListFilter {
                (data, http) = try await fetch(includeListFilter: false, extraFilters: extraFilters)
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
            // Each still carries the category filter too, if one's active.
            // profiles is a plain jsonb column on the view (not an embed —
            // see profilesSelect above), so matching into it needs the
            // ->> jsonb operator instead of the embedded-resource dot
            // syntax the base-table fallback still uses.
            let q = trimmedSearch
            let categoryFilter: [(String, String)] = category.map { [("items.type", "eq.\($0)")] } ?? []
            let usernameFilter = useView ? "profiles->>username" : "profiles.username"
            let displayNameFilter = useView ? "profiles->>display_name" : "profiles.display_name"
            async let byTitle = decodedPage(includeListFilter: true, extraFilters: categoryFilter + [("items.title", "ilike.*\(q)*")])
            // "If you search the author of a book Rex'd it should also be
            // searchable rather than just the title" — a book's subtitle
            // *is* its author (see fetchBooksByAuthor's doc comment: no
            // normalized author field, subtitle is the joined author names
            // OpenLibrary returned). The unfiltered client-side `matching`
            // filter already searches subtitle, so author search quietly
            // worked right up until you actually typed something — the
            // moment that switches to this wider server-side fetch, which
            // never had a subtitle variant to begin with.
            async let bySubtitle = decodedPage(includeListFilter: true, extraFilters: categoryFilter + [("items.subtitle", "ilike.*\(q)*")])
            async let byNote = decodedPage(includeListFilter: true, extraFilters: categoryFilter + [("note", "ilike.*\(q)*")])
            async let byUsername = decodedPage(includeListFilter: true, extraFilters: categoryFilter + [(usernameFilter, "ilike.*\(q)*")])
            async let byDisplayName = decodedPage(includeListFilter: true, extraFilters: categoryFilter + [(displayNameFilter, "ilike.*\(q)*")])
            let pages = try await [byTitle, bySubtitle, byNote, byUsername, byDisplayName]
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
            extraFilters: category.map { [("items.type", "eq.\($0)")] } ?? []
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
        let (resourcePath, profilesSelect) = await recommendationsReadPath()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)," +
            "\(profilesSelect)," +
            "creators(slug,name,color,emoji)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent(resourcePath), resolvingAgainstBaseURL: false)!
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
        let (resourcePath, profilesSelect) = await recommendationsReadPath()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)," +
            "\(profilesSelect)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent(resourcePath), resolvingAgainstBaseURL: false)!
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
        // Sept 15 — "You can't see the product link" (Phoebe). It was saved
        // on every list item and never selected back here, so the item page
        // had nothing to show.
        let base = "id,type,title,subtitle,image_url,genre,address,recipe_text,link_url"
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
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"
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

    /// #183 — "pool all your Rex into a trip": every place/event you've
    /// rated standalone (not already a stop on some other trip, not a list
    /// item) that BuildTripFromRexView can offer to fold into a brand-new
    /// trip. Oldest first — "simplest: just the order added" was the call
    /// on itinerary ordering, and fetchTripStops already sorts stops by
    /// created_at.asc, so keeping this fetch in the same order means
    /// whatever you tick becomes the itinerary order with no reordering
    /// step at all.
    /// Sept 2 — "when you type in the 'name' it allows you to search the
    /// general internet but also your own rexes if it has already been
    /// rex'd". Your own Rex only, matched on the item's title, so adding a
    /// trip stop somewhere you've already been reuses that catalogue item
    /// (and its photo, address and coordinates) instead of creating a
    /// near-duplicate of it.
    func searchMyRexItems(query: String) async throws -> [MyRexHit] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let userId = currentUserId else { return [] }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "item_id,rating,note,items!inner(id,type,title,subtitle,image_url,genre,address,lat,lng,external_id,external_source)"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "items.title", value: "ilike.*\(trimmed)*"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "8"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        struct Row: Codable {
            struct Item: Codable {
                let id: String
                let type: String
                let title: String
                let subtitle: String?
                let image_url: String?
                let genre: String?
                let address: String?
                let lat: Double?
                let lng: Double?
                let external_id: String?
                let external_source: String?
            }
            let items: Item
            // Sept 7 — "comes up with my Rex but when I click on it it
            // doesn't auto populate with the previous Rex". The search only
            // ever returned the catalogue entry, so picking your own Rex
            // filled in a name and nothing else. Carrying your rating and
            // note across is the whole point of recognising it as yours.
            let rating: Double?
            let note: String?
        }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        // Same item Rex'd more than once (standalone and as a trip stop, say)
        // should offer itself once.
        var seen = Set<String>()
        return rows.compactMap { row -> MyRexHit? in
            guard seen.insert(row.items.id).inserted else { return nil }
            let hit = RexSearchHit(
                // A Rex of your own that came from a manual entry has no
                // external id at all; keying it by the catalogue item id
                // keeps RexSearchHit.id unique either way, and "rex" as the
                // source is what marks it as already-yours in the picker.
                externalId: row.items.external_id ?? row.items.id,
                externalSource: row.items.external_source ?? "rex",
                title: row.items.title,
                subtitle: row.items.subtitle,
                imageURL: row.items.image_url,
                genre: row.items.genre,
                address: row.items.address,
                lat: row.items.lat,
                lng: row.items.lng
            )
            return MyRexHit(hit: hit, rating: row.rating ?? 0, note: row.note)
        }
    }

    func fetchStandalonePlaceRex() async throws -> [FeedRecommendation] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags,user_id,item_id,trip_id,list_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "list_id", value: "is.null"),
            URLQueryItem(name: "items.type", value: "in.(place,event)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
            URLQueryItem(name: "limit", value: "500"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load your Rex."))
        }
        return try JSONDecoder().decode([FeedRecommendation].self, from: data)
    }

    /// #183 — folds an existing standalone Rex into a trip as a stop, in
    /// place, rather than creating a duplicate: the same partial-index
    /// reasoning as everywhere else this session (recommendations_unique
    /// only applies while trip_id/list_id are both null), so this UPDATE
    /// just moves the row out from under that constraint and under
    /// recommendations_unique_trip_stop instead — no new row, rating/note/
    /// photos/tags all come along untouched.
    func assignRecommendationToTrip(recommendationId: String, tripId: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(recommendationId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["trip_id": tripId])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't add that stop to the trip."))
        }
    }

    /// Your own draft trips — trip_id is.null (a trip itself, not a stop)
    /// and published_at is.null (never published). Only ever your own by
    /// construction: RLS hides anyone else's drafts before this query even
    /// runs, so there's no need to filter user_id client-side too.
    func fetchDraftTrips() async throws -> [FeedRecommendation] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags,user_id,item_id,trip_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)," +
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"
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
        let (resourcePath, profilesSelect) = await recommendationsReadPath()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,trip_id,trip_section," +
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,lat,lng)," +
            "\(profilesSelect)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent(resourcePath), resolvingAgainstBaseURL: false)!
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
        let (resourcePath, profilesSelect) = await recommendationsReadPath()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id,list_id,list_section,show_in_feed," +
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)," +
            "\(profilesSelect)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent(resourcePath), resolvingAgainstBaseURL: false)!
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
            "profiles!recommendations_user_id_fkey(username,display_name,avatar_url)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"
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

    /// #149 — used to lean on `on_conflict=user_id,item_id`, matching the
    /// table's old blanket UNIQUE(user_id,item_id) constraint. That
    /// constraint is what made adding an already-Rex'd place to a trip or
    /// list fail as a duplicate, so it's now three narrower partial indexes
    /// (see migration 20260821190000) — none of which "on_conflict" can
    /// target directly, since PostgREST only takes a plain column list, not
    /// a WHERE-qualified arbiter. Looks up the existing *standalone* row
    /// explicitly instead (trip_id/list_id both null) and PATCHes it if
    /// found, so re-rating something you've already Rex'd on its own still
    /// updates in place rather than erroring or duplicating.
    func upsertRecommendation(itemId: String, rating: Double, note: String?) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }

        var lookupComponents = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        lookupComponents.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "item_id", value: "eq.\(itemId)"),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "list_id", value: "is.null"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var lookupRequest = URLRequest(url: lookupComponents.url!)
        lookupRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        lookupRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        struct ExistingRow: Codable { let id: String }
        var existingId: String?
        if let (lookupData, lookupResponse) = try? await URLSession.shared.data(for: lookupRequest),
           let lookupHttp = lookupResponse as? HTTPURLResponse, lookupHttp.statusCode < 400 {
            existingId = (try? JSONDecoder().decode([ExistingRow].self, from: lookupData))?.first?.id
        }

        var body: [String: Any] = ["user_id": userId, "item_id": itemId, "rating": rating]
        body["note"] = note?.isEmpty == false ? note : NSNull()

        var request: URLRequest
        if let existingId {
            var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "id", value: "eq.\(existingId)")]
            request = URLRequest(url: components.url!)
            request.httpMethod = "PATCH"
        } else {
            request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/recommendations"))
            request.httpMethod = "POST"
        }
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save your take."))
        }
    }

    /// TestFlight feedback (Aug 24) found a case upsertRecommendation's own
    /// fix didn't cover: AddToTripView's "add to trip" flow called plain
    /// createRecommendation, which — being a bare INSERT, not an upsert —
    /// still throws a raw duplicate-key error if this exact place is
    /// already a stop on this exact trip (recommendations_unique_trip_stop,
    /// same partial-index reasoning as upsertRecommendation's own comment).
    /// Re-adding an existing stop should just be a no-op, not an error.
    func addPlaceToTrip(itemId: String, tripId: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }

        var lookupComponents = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        lookupComponents.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "item_id", value: "eq.\(itemId)"),
            URLQueryItem(name: "trip_id", value: "eq.\(tripId)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var lookupRequest = URLRequest(url: lookupComponents.url!)
        lookupRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        lookupRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (lookupData, lookupResponse) = try? await URLSession.shared.data(for: lookupRequest),
           let lookupHttp = lookupResponse as? HTTPURLResponse, lookupHttp.statusCode < 400,
           let rows = try? JSONDecoder().decode([[String: String]].self, from: lookupData), !rows.isEmpty {
            return // already a stop on this trip — nothing to do
        }
        try await createRecommendation(itemId: itemId, rating: 0, note: nil, tripId: tripId)
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

        // "Also Rex'd by" still missing — that count groups strictly by
        // item_id, and two people adding "the same place" through
        // different paths (one via search, one hand-typed; or picking two
        // slightly different Google matches for the same physical venue)
        // always landed on two separate item rows, so the count never saw
        // them as the same place. The external_id lookup above only
        // catches "picked the identical Google result" — this catches
        // "picked a different result, or typed it, for the same real
        // place" instead, before falling through to a genuine new row.
        if (type == "place" || type == "event"),
           let resolvedLat = lat ?? hit?.lat, let resolvedLng = lng ?? hit?.lng,
           let existingId = await findNearbyItem(type: type, title: title, lat: resolvedLat, lng: resolvedLng) {
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

    /// An existing item at (almost) the same coordinates with the same
    /// name, if any — see createItem's doc comment for why. No PostGIS
    /// filter available over PostgREST here, so this pre-filters with a
    /// plain lat/lng bounding box (~65m per side, comfortably wider than
    /// the real 30m radius check below) and does the actual distance math
    /// client-side over whatever small set of candidates that returns.
    /// Deliberately conservative — exact normalized-title match, not a
    /// fuzzy one — better to occasionally miss a real duplicate than merge
    /// two different shops that happen to share a building.
    private func findNearbyItem(type: String, title: String, lat: Double, lng: Double) async -> String? {
        guard let token = try? await validToken() else { return nil }
        let delta = 0.0006
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,title,lat,lng"),
            URLQueryItem(name: "type", value: "eq.\(type)"),
            URLQueryItem(name: "lat", value: "gte.\(lat - delta)"),
            URLQueryItem(name: "lat", value: "lte.\(lat + delta)"),
            URLQueryItem(name: "lng", value: "gte.\(lng - delta)"),
            URLQueryItem(name: "lng", value: "lte.\(lng + delta)"),
            URLQueryItem(name: "limit", value: "25"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400
        else { return nil }
        struct Candidate: Codable { let id: String; let title: String; let lat: Double?; let lng: Double? }
        let candidates = (try? JSONDecoder().decode([Candidate].self, from: data)) ?? []
        let target = Self.normalizeForMatch(title)
        for candidate in candidates {
            guard let clat = candidate.lat, let clng = candidate.lng,
                  Self.normalizeForMatch(candidate.title) == target,
                  Self.haversineMeters(lat, lng, clat, clng) <= 30
            else { continue }
            return candidate.id
        }
        return nil
    }

    private static func normalizeForMatch(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "['’‘\"]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func haversineMeters(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
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
    /// Sept 9 — `source` says how the want came to exist: "save" for the
    /// bookmark on somebody else's Rex, "add" for one you created from
    /// scratch. Only the second belongs in the feed — see fetchWantsFeed.
    /// Sent only when the column exists, same probe-and-skip the note field
    /// above uses, so this keeps working before the migration is run.
    func createWant(itemId: String, note: String? = nil, source: String = "save") async throws {
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
        if await wantSourceField() { body["source"] = source }
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
        let (resourcePath, profilesSelect) = await recommendationsReadPath()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)," +
            "\(profilesSelect)," +
            "creators(slug,name,color,emoji)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent(resourcePath), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            // "I just added this REX to a trip and now it has duplicated in
            // my feed" — reported on the profile page specifically. Adding
            // an existing standalone Rex to a trip (addPlaceToTrip) creates
            // a brand-new recommendation row for the same item — trip_id
            // set, rating 0, no photo/note of its own — that's meant to be
            // a stop, invisible outside the trip's own page, exactly like
            // fetchFeed's own trip_id.is.null already treats it. This query
            // had no such filter at all, so both the real standalone Rex
            // and the bare new stop row showed here side by side.
            URLQueryItem(name: "trip_id", value: "is.null"),
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

    /// Sept 8 — backs the "Add a Rex" picker inside a collection. Until
    /// now the only route into a collection was long-pressing a card in
    /// the feed, which means the thing you want has to happen to be
    /// scrolled past; filling a collection deliberately meant hunting for
    /// each Rex in turn.
    ///
    /// Same shape and same trip_id filter as fetchRecommendations(
    /// forUser:) — a bare trip-stop row isn't something you'd add to a
    /// collection on its own. An empty query returns your most recent,
    /// which is what you want the moment the sheet opens.
    func searchMyRecommendations(query: String, limit: Int = 40) async throws -> [FeedRecommendation] {
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let token = try await validToken()
        let (resourcePath, profilesSelect) = await recommendationsReadPath()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id," +
            "items!inner(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)," +
            "\(profilesSelect)," +
            "recommendation_tags(profiles(id,username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent(resourcePath), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "items.title", value: "ilike.*\(trimmed)*"))
        }
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load your Rex."))
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

    /// #162 — the friend picker for tagging people on a Rex. Same two-step
    /// friendships-then-profiles shape FriendsView already uses, just
    /// collapsed into one call and filtered to accepted only (no point
    /// offering to tag someone who hasn't accepted yet).
    func fetchAcceptedFriendProfiles() async throws -> [RexProfileDetail] {
        guard let me = currentUserId else { return [] }
        let friendships = try await fetchFriendships().filter { $0.status == "accepted" }
        let ids = friendships.map { $0.requester_id == me ? $0.addressee_id : $0.requester_id }
        return try await fetchProfiles(ids: ids)
    }

    /// Replaces the full set of friends tagged on a Rex with `userIds` —
    /// simplest correct thing (delete then re-insert) rather than diffing,
    /// since this only ever runs from a picker that already knows the
    /// intended final set, not an incremental add/remove.
    func setTaggedFriends(recommendationId: String, userIds: [String]) async throws {
        let token = try await validToken()

        var delComponents = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendation_tags"), resolvingAgainstBaseURL: false)!
        delComponents.queryItems = [URLQueryItem(name: "recommendation_id", value: "eq.\(recommendationId)")]
        var delRequest = URLRequest(url: delComponents.url!)
        delRequest.httpMethod = "DELETE"
        delRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        delRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: delRequest)

        guard !userIds.isEmpty else { return }
        var insRequest = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/recommendation_tags"))
        insRequest.httpMethod = "POST"
        insRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        insRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        insRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        insRequest.httpBody = try JSONSerialization.data(withJSONObject: userIds.map { ["recommendation_id": recommendationId, "user_id": $0] })
        let (data, response) = try await URLSession.shared.data(for: insRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't tag your friends."))
        }
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

    /// Sept 15 — "Maybe you could amp up people's dopamine when they submit.
    /// Congratulate them or thank them. Or like Duolingo have a posting
    /// streak" (Danny). How many Rex you've posted, and how many weeks in a
    /// row (this one included) you've posted at least one. Stops and list
    /// items don't count — they're part of a trip or list, not posts of
    /// their own.
    func fetchMyPostStats() async -> (count: Int, weekStreak: Int)? {
        guard let userId = currentUserId, let token = try? await validToken() else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "created_at"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "list_id", value: "is.null"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "2000"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
        struct Row: Codable { let created_at: String }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let weeks = Set(rows.compactMap { row -> Date? in
            guard let date = iso.date(from: row.created_at) ?? plain.date(from: row.created_at) else { return nil }
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
        })
        var streak = 0
        var cursor = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        while weeks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return (rows.count, streak)
    }

    // MARK: - Finding friends (14 Sept)

    /// A friend's own friends — "look at your friends' friends as another
    /// way to find users". friends_of() only answers for someone you're
    /// friends with; for anyone else it returns nothing, which the profile
    /// screen reads as "don't offer the list".
    func fetchFriendsOf(userId: String) async throws -> [FoundPerson] {
        try await callPeopleRPC("friends_of", body: ["_user": userId, "_limit": 300],
                                fallback: "Couldn't load their friends.")
    }

    /// Hashes of the emails in your contacts in, Rex profiles out. The
    /// hashing happens on the phone (ContactsFriendFinderView); no address
    /// ever leaves it.
    func matchContactEmails(hashes: [String]) async throws -> [FoundPerson] {
        guard !hashes.isEmpty else { return [] }
        var found: [String: FoundPerson] = [:]
        // The database caps a call at 2,000; a bigger address book goes in
        // batches.
        var start = 0
        while start < hashes.count {
            let batch = Array(hashes[start..<min(start + 2000, hashes.count)])
            let people = try await callPeopleRPC("match_contact_emails", body: ["_hashes": batch],
                                                 fallback: "Couldn't check your contacts.")
            for person in people { found[person.id] = person }
            start += 2000
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func callPeopleRPC(_ name: String, body: [String: Any], fallback: String) async throws -> [FoundPerson] {
        let token = try await validToken()
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: fallback))
        }
        return try JSONDecoder().decode([FoundPerson].self, from: data)
    }

    /// Sept 14 — "when Danny logged in, he wasn't asked to create a
    /// username". Returns nil when there's nothing to ask: the username is
    /// confirmed, or the column doesn't exist yet (before the migration
    /// runs, nobody should be stopped at the door by a question the
    /// database can't record the answer to).
    func pendingUsernameSetup() async -> (username: String, displayName: String?)? {
        guard let userId = currentUserId, let token = try? await validToken() else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "username,display_name,username_confirmed"),
            URLQueryItem(name: "id", value: "eq.\(userId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
        struct Row: Codable { let username: String; let display_name: String?; let username_confirmed: Bool? }
        guard let row = (try? JSONDecoder().decode([Row].self, from: data))?.first,
              row.username_confirmed == false else { return nil }
        return (row.username, row.display_name)
    }

    /// Sets your username (and name, if given) and marks it confirmed.
    /// Usernames are unique in the database, so "taken" comes back as a
    /// 409 rather than needing a separate availability check that could go
    /// stale between asking and saving.
    func claimUsername(_ username: String, displayName: String?) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["username": username, "username_confirmed": true]
        if let displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespaces)
            body["display_name"] = trimmed.isEmpty ? NSNull() : trimmed
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RexAPIError.server("Couldn't save your username.") }
        if http.statusCode == 409 || String(data: data, encoding: .utf8)?.contains("23505") == true {
            throw RexAPIError.server("@\(username) is taken \u{2014} try another.")
        }
        guard http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save your username."))
        }
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

    /// Sept 15 — "I've no way to X them" (Danny). Your own notifications
    /// are yours to delete (RLS: "Users delete own notifications").
    func deleteNotification(id: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/notifications"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't remove that notification."))
        }
    }

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

    /// #176 — the badge dot on the bell icon. `Prefer: count=exact` +
    /// limit=1 gets PostgREST to report the true total in the Content-Range
    /// response header (formatted "0-0/42") without transferring all the
    /// unread rows themselves.
    func fetchUnreadNotificationCount() async -> Int {
        guard let token = try? await validToken(), let userId = currentUserId else { return 0 }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/notifications"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "read_at", value: "is.null"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let range = http.value(forHTTPHeaderField: "Content-Range"),
              let total = range.split(separator: "/").last
        else { return 0 }
        return Int(total) ?? 0
    }

    /// #175 — mirrors the web's notification-settings page (same columns,
    /// same defaults), just grouped into sections instead of one flat list.
    /// Web's PrefRow/DEFAULT_PREFS also lists rec_saved/mention — those
    /// aren't real columns on this table (checked the migration directly),
    /// so they're left out here rather than copied over as a second bug.
    func fetchNotificationPreferences() async throws -> RexNotificationPreferences {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/notification_preferences"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load your notification settings."))
        }
        if let existing = (try? JSONDecoder().decode([RexNotificationPreferences].self, from: data))?.first {
            return existing
        }
        // No row yet (never touched a toggle) — same defaults DEFAULT_PREFS
        // uses on web, returned client-side rather than pre-creating a row
        // nobody's actually customized.
        return RexNotificationPreferences(user_id: userId)
    }

    /// One PATCH-or-create call — user_id is the table's actual primary key
    /// (not a partial index), so PostgREST's on_conflict works normally
    /// here, unlike recommendations' upsertRecommendation.
    func updateNotificationPreference(_ patch: [String: Bool]) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/notification_preferences"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = patch
        body["user_id"] = userId
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save that."))
        }
    }

    /// #175 — called once permission is granted and a device token is in
    /// hand (see AppDelegate). Upserts on (user_id, device_token) so a
    /// reinstall/re-login on the same device doesn't create a duplicate row
    /// the send-push function would then double-deliver to.
    func registerPushToken(deviceToken: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/push_tokens"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,device_token")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Sept 15 — "I have yet to get a push notification". This was
        // resolution=merge-duplicates, i.e. INSERT ... ON CONFLICT DO
        // UPDATE, which needs UPDATE permission on push_tokens — and the
        // table only grants INSERT and DELETE (20260826120000). Postgres
        // refuses the whole statement up front, conflict or not, so every
        // token save since 1 Sept failed and AppDelegate's try? swallowed
        // it. push_tokens was empty: nobody's phone was ever registered, so
        // there was nowhere to send to. ignore-duplicates (ON CONFLICT DO
        // NOTHING) needs only INSERT, and a token that's already saved has
        // nothing to update anyway.
        request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["user_id": userId, "device_token": deviceToken])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't register for push."))
        }
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

    /// Sept 10 — guards all three repair sets below. They're plain statics
    /// mutated from whatever task happens to call in, and
    /// fetchMapPlaces(forTrip:) calls repairPlaceCoordsIfNeeded from a task
    /// group — several at once, on different threads. Two concurrent
    /// inserts into one Set is a data race, and it crashed the app
    /// (EXC_BAD_ACCESS in Set.insert) the moment a trip card with
    /// un-located stops scrolled into the feed. It had always been a race;
    /// 9 Sept's no-address fallback is what made every such stop reach the
    /// insert instead of bailing out before it. Check-and-insert is now one
    /// locked step, so exactly one caller claims each id.
    private static let repairLock = NSLock()

    /// #146: same self-healing idea, for place/event items missing lat/lng —
    /// mostly Lovable-era Rex predating #135's geocode-on-add, which just
    /// silently never got a map pin (fetchMapPlaces drops anything without
    /// coordinates). No SQL backfill here either, for the same reason as
    /// repairPlacePhotoIfNeeded: geocoding needs an external API call.
    private static var geocodeRepairedItemIds = Set<String>()

    /// #141: same self-healing idea again, for items with no thumbnail at
    /// all — mostly pre-v10 Rex from before any category had automatic
    /// photo lookup. Re-runs that category's own search catalogue against
    /// the item's own title (RexSearch.search already knows book vs
    /// movie/tv vs podcast vs place/event vs other) and takes the first
    /// hit's photo, same shared-row self-heal as the others above.
    private static var thumbnailRepairedItemIds = Set<String>()

    func repairMissingThumbnailIfNeeded(itemId: String, type: String, title: String, subtitle: String?) async {
        guard Self.repairLock.withLock({ Self.thumbnailRepairedItemIds.insert(itemId).inserted }) else { return }

        // Recipe photos are always user-uploaded — there's no catalogue to
        // look one up in, so nothing to do there.
        let category = RexCategory(rawType: type)
        guard category != .recipe else { return }

        let query = [title, subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { return }
        let hits = await RexSearch.search(category: category, query: query)
        guard let imageURL = hits.first(where: { $0.imageURL != nil })?.imageURL else { return }

        guard let token = try? await validToken() else { return }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["image_url": imageURL])
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Geocodes `address` and writes the result back onto the item if it
    /// resolves. Returns the coordinates so the caller can show the pin
    /// immediately rather than waiting for the next map load.
    ///
    /// Sept 8 — `fallbackQuery` covers the case this repair could never
    /// reach before: a stop imported from a document has no address, only
    /// the coordinates the importer geocoded at the time, so a stop
    /// imported before that geocoding existed has neither. There is
    /// nothing to key off, and it has been invisible on every map since.
    /// The fallback is the same query the importer itself builds — the
    /// stop's own name plus whatever context is going ("The Ivy" alone
    /// geocodes to a same-named place anywhere in the world) — and the
    /// resolved address gets written back alongside the point, so the row
    /// stops being a special case from then on.
    func repairPlaceCoordsIfNeeded(
        itemId: String, address: String, fallbackQuery: String? = nil
    ) async -> (lat: Double, lng: Double)? {
        let query = address.isEmpty ? (fallbackQuery ?? "") : address
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard Self.repairLock.withLock({ Self.geocodeRepairedItemIds.insert(itemId).inserted }) else { return nil }

        let located: (lat: Double, lng: Double, address: String?)?
        if address.isEmpty {
            located = await RexSearch.locatePlace(query)
        } else {
            located = await RexSearch.geocodeDetailed(query)
        }
        guard let located else { return nil }
        guard let token = try? await validToken() else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["lat": located.lat, "lng": located.lng]
        // Only when we had none — never overwrite an address someone typed.
        if address.isEmpty, let resolved = located.address, !resolved.isEmpty {
            body["address"] = resolved
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
        return (located.lat, located.lng)
    }

    func repairPlacePhotoIfNeeded(itemId: String, imageURL: String?) async {
        guard let imageURL, imageURL.contains("places.googleapis.com") else { return }
        guard Self.repairLock.withLock({ Self.repairedItemIds.insert(itemId).inserted }) else { return }

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

    /// #170 — a trip-level note (the trip's own recommendation row, not any
    /// one stop's). A lighter PATCH than updateRecommendation() on purpose:
    /// that one always rewrites rating/tags/photos too, which the trip note
    /// editor has no business touching.
    func updateNote(recommendationId: String, note: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(recommendationId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = ["note": (trimmed?.isEmpty == false ? trimmed : nil) ?? (NSNull() as Any)]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save that note."))
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

    /// Same shared-catalogue model as updateItemTitle, for subtitle instead.
    /// Added specifically so a List's subtitle can be fixed after the fact —
    /// AddRexView's category-switch bug (see resetDraftFields) could leave a
    /// list carrying a different category's leftover subtitle text, and
    /// until this there was no field anywhere to clear or edit it.
    func updateItemSubtitle(itemId: String, subtitle: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["subtitle": subtitle?.isEmpty == false ? subtitle! : (NSNull() as Any)]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't update the subtitle."))
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

    /// #45 — same shared-catalogue model again, for the "Link" field
    /// AddRexView already collects at creation for place/event/recipe/other
    /// (everything except book/movie/tv/podcast/list, which come from a
    /// catalogue with their own page). This was write-once; there was no way
    /// to add one after the fact, or fix a dead one, without redoing the Rex.
    func updateItemLinkURL(itemId: String, linkURL: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["link_url": linkURL ?? (NSNull() as Any)]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't update the link."))
        }
    }

    /// #172 — recipe_text was write-once at creation (createItem), same gap
    /// title/link/thumbnail had before #45/#101/#125 fixed those. Same
    /// shared-catalogue pattern: anyone who's Rex'd this recipe sees the fix.
    func updateItemRecipeText(itemId: String, recipeText: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["recipe_text": recipeText?.isEmpty == false ? recipeText! : (NSNull() as Any)]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save the recipe."))
        }
    }

    /// #183 — trip stops (and any place/event) could only ever get an
    /// address/coordinates once, at creation — via a live search pick, or
    /// self-healing geocode-on-read if that missed. There was no way to fix
    /// one afterwards short of deleting and re-adding. Same shared-catalogue
    /// model as updateItemTitle: whoever's editing corrects it for anyone
    /// who's Rex'd the same place. lat/lng travel with address so a stale
    /// pin can't survive next to a freshly-typed address — see
    /// EditRexView's "Re-check location" flow, which always sets both.
    func updateItemAddressAndCoords(itemId: String, address: String?, lat: Double?, lng: Double?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "address": address?.isEmpty == false ? address! : (NSNull() as Any),
            "lat": lat ?? (NSNull() as Any),
            "lng": lng ?? (NSNull() as Any),
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't update the location."))
        }
    }

    /// #183 — genre (AddRexView's "subcategories" chips, e.g. Restaurant /
    /// Activity for a place, or a recipe's Pasta / Salad) was write-once at
    /// creation too, same gap title/link/recipe_text had before their own
    /// fixes. Stored as the same sorted, comma-joined string
    /// splitGenres() already reads everywhere else.
    func updateItemGenre(itemId: String, genre: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "genre": genre?.isEmpty == false ? genre! : (NSNull() as Any),
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't update the category."))
        }
    }

    // MARK: - List notes (10 Sept)

    /// Sept 10 — "a free text 'Notes' box at the bottom of lists so if the
    /// app can't work out what is in the list as it is misc, you have the
    /// opportunity to post free text instead. Especially helpful if there
    /// is lots of commentary."
    ///
    /// Its own column (recommendations.long_note) rather than the existing
    /// `note`, which is the one-line "why are you Rex'ing it" that shows on
    /// the list's feed card. This is the other kind of writing — pages of
    /// it, sometimes — and it lives on the list's own page, not the card.
    ///
    /// Read and written with requests of their own rather than folded into
    /// fetchRecommendation's select: that read can go through the
    /// recommendations_display view, which fixes its columns when it's
    /// created and wouldn't know about this one. Probed like the other
    /// late-arriving columns, so nothing breaks before the migration runs.
    private var longNoteColumn: Bool?

    func longNoteAvailable() async -> Bool {
        if let longNoteColumn { return longNoteColumn }
        guard let token = try? await validToken() else { return false }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "long_note"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let ok = (try? await URLSession.shared.data(for: request))
            .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
            .map { $0 < 400 } ?? false
        longNoteColumn = ok
        return ok
    }

    func fetchLongNote(recommendationId: String) async -> String? {
        guard await longNoteAvailable(), let token = try? await validToken() else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "long_note"),
            URLQueryItem(name: "id", value: "eq.\(recommendationId)"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
        struct Row: Codable { let long_note: String? }
        return (try? JSONDecoder().decode([Row].self, from: data))?.first?.long_note
    }

    func updateLongNote(recommendationId: String, text: String) async throws {
        guard await longNoteAvailable() else {
            throw RexAPIError.server("Notes aren't switched on yet — the database needs one more update.")
        }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(recommendationId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "long_note": trimmed.isEmpty ? (NSNull() as Any) : trimmed,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save the notes."))
        }
    }

    /// Sept 8 — "when you delete a trip, all individual stops should be
    /// deleted". A trip and its stops are all rows in `recommendations`;
    /// the trip is the parent and each stop carries `trip_id` pointing at
    /// it (lists work the same way with `list_id`). Deleting only the
    /// parent row left every stop behind as an orphan: invisible in the
    /// feed, since only the trip posts, but still turning up in search and
    /// on the map with no trip to belong to.
    ///
    /// Children go first so a failure part-way leaves the trip still
    /// standing over its stops, rather than a deleted trip with orphans
    /// underneath it — the state you can still see and retry from.
    /// Non-parent Rexes match nothing here, so this costs two empty
    /// deletes and no behaviour change.
    func deleteRecommendation(id: String) async throws {
        let token = try await validToken()
        for parentField in ["trip_id", "list_id"] {
            var childComponents = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
            childComponents.queryItems = [URLQueryItem(name: parentField, value: "eq.\(id)")]
            var childRequest = URLRequest(url: childComponents.url!)
            childRequest.httpMethod = "DELETE"
            childRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
            childRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (childData, childResponse) = try await URLSession.shared.data(for: childRequest)
            guard let childHTTP = childResponse as? HTTPURLResponse, childHTTP.statusCode < 400 else {
                throw RexAPIError.server(friendlyError(childData, fallback: "Couldn't delete that Rex."))
            }
        }
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

    /// Same as renameTripSection, list_id/list_section instead of
    /// trip_id/trip_section — "editing the heading doesn't work" was
    /// literally true for a list: TripDetailView got heading rename with
    /// #122, ListDetailView never got the equivalent.
    func renameListSection(listId: String, from: String?, to: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "list_id", value: "eq.\(listId)"),
            URLQueryItem(name: "list_section", value: (from?.isEmpty ?? true) ? "is.null" : "eq.\(from!)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["list_section": (to?.isEmpty ?? true) ? NSNull() : to!]
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
    /// Sept 5 — sets one stop's heading directly, which editing a posted
    /// trip needs and renameTripSection can't do: that one renames a
    /// heading across every stop under it, whereas dragging a single stop
    /// from "Day 1" to "Day 2" changes only that stop.
    func setTripSection(recommendationId: String, section: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(recommendationId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmed = section?.trimmingCharacters(in: .whitespaces)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "trip_section": (trimmed?.isEmpty ?? true) ? (NSNull() as Any) : trimmed!,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't move that stop."))
        }
    }

    /// Same as setTripSection, for an item's heading within its list.
    func setListSection(recommendationId: String, section: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(recommendationId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmed = section?.trimmingCharacters(in: .whitespaces)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "list_section": (trimmed?.isEmpty ?? true) ? (NSNull() as Any) : trimmed!,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't move that item."))
        }
    }

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
    // MARK: - Wants: likes and comments
    //
    // Sept 5 — "for 'want to's, we still need to be able to like and
    // comment". A want has no recommendation row, so it can't use the
    // functions below; these four are the same shapes against want_likes /
    // want_comments (migration 20260905140000). `wantId` throughout is the
    // real `wants.id` — FeedRecommendation.id carries a "want-" prefix for
    // its own Identifiable purposes, which callers strip first.

    func fetchWantLikeState(wantIds: [String]) async throws -> [String: (count: Int, likedByMe: Bool)] {
        guard !wantIds.isEmpty else { return [:] }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/want_likes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "want_id,user_id"),
            URLQueryItem(name: "want_id", value: "in.(\(wantIds.joined(separator: ",")))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [:] }
        struct Row: Codable { let want_id: String; let user_id: String }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        let me = currentUserId
        var result: [String: (count: Int, likedByMe: Bool)] = [:]
        for row in rows {
            var entry = result[row.want_id] ?? (0, false)
            entry.count += 1
            if row.user_id == me { entry.likedByMe = true }
            result[row.want_id] = entry
        }
        return result
    }

    func setWantLike(wantId: String, liked: Bool) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/want_likes"), resolvingAgainstBaseURL: false)!
        var request: URLRequest
        if liked {
            request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["want_id": wantId, "user_id": userId])
        } else {
            components.queryItems = [
                URLQueryItem(name: "want_id", value: "eq.\(wantId)"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            ]
            request = URLRequest(url: components.url!)
            request.httpMethod = "DELETE"
        }
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save that like."))
        }
    }

    func fetchWantCommentCounts(wantIds: [String]) async throws -> [String: Int] {
        guard !wantIds.isEmpty else { return [:] }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/want_comments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "want_id"),
            URLQueryItem(name: "want_id", value: "in.(\(wantIds.joined(separator: ",")))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [:] }
        struct Row: Codable { let want_id: String }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        return rows.reduce(into: [:]) { out, row in out[row.want_id, default: 0] += 1 }
    }

    /// Same client-side profile merge as fetchRequestComments — see its own
    /// note on why these don't embed profiles by FK name any more.
    func fetchWantComments(wantId: String) async throws -> [RexComment] {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/want_comments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,want_id,user_id,body,created_at"),
            URLQueryItem(name: "want_id", value: "eq.\(wantId)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load comments."))
        }
        struct Row: Codable {
            let id: String
            let user_id: String
            let body: String
            let created_at: String
        }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        guard !rows.isEmpty else { return [] }

        let profilesById: [String: RexProfile] = await {
            let ids = Array(Set(rows.map { $0.user_id }))
            guard let people = try? await fetchProfiles(ids: ids) else { return [:] }
            return people.reduce(into: [:]) { out, p in
                out[p.id] = RexProfile(username: p.username, display_name: p.display_name, avatar_url: p.avatar_url)
            }
        }()

        return rows.map { row in
            RexComment(
                id: row.id, body: row.body, created_at: row.created_at,
                user_id: row.user_id, profiles: profilesById[row.user_id]
            )
        }
    }

    func addWantComment(wantId: String, body text: String) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/want_comments"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "want_id": wantId, "user_id": userId, "body": text,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't post that comment."))
        }
    }

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
    /// Sept 8 — section/sortOrder arrived with the saved_posts migration of
    /// the same date. Both optional: saving a Rex into a collection from
    /// the feed still has no heading in mind and no position to claim, and
    /// a row with a null sort_order sorts to the end (see
    /// fetchCollectionItems), which is where a newly saved one belongs.
    func addToCollection(
        recommendationId: String, listId: String,
        section: String? = nil, sortOrder: Int? = nil
    ) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = [
            "user_id": userId, "recommendation_id": recommendationId, "list_id": listId,
        ]
        if let section, !section.isEmpty { body["section"] = section }
        if let sortOrder { body["sort_order"] = sortOrder }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
                show_in_feed: nil,
                recommendation_tags: nil
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

    /// #132 — every response to one blast, oldest first (a conversation
    /// reads top-to-bottom, unlike the feed itself).
    /// Sept 2 — "the blast request has broken somehow": every response on a
    /// blast came back as "Couldn't load responses." This embedded
    /// `profiles!request_comments_user_id_fkey(...)`, naming an FK
    /// constraint by hand — the third time that exact pattern has bitten
    /// this app (see fetchWantsFeed/fetchMapWants, where wants_user_id_fkey
    /// actually points at auth.users rather than public.profiles, and the
    /// PGRST201 ambiguity on recommendations). Rather than guess at the
    /// right constraint name again, this drops the embed entirely and
    /// batch-fetches the profiles in one flat query alongside, merging
    /// client-side — the same shape those two fixes settled on, and immune
    /// to whatever the underlying constraint happens to be called.
    func fetchRequestComments(requestId: String) async throws -> [RequestComment] {
        let token = try await validToken()
        let select = "id,request_id,user_id,body,created_at\(await blastReplyField())"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/request_comments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "request_id", value: "eq.\(requestId)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load responses."))
        }
        struct Row: Codable {
            let id: String
            let request_id: String
            let user_id: String
            let body: String
            let created_at: String
            let parent_id: String?
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        guard !rows.isEmpty else { return [] }

        // Best-effort: a response with no profile still shows, just without
        // a name attached — better than the whole screen erroring out.
        let profilesById: [String: RexProfile] = await {
            let ids = Array(Set(rows.map { $0.user_id }))
            guard let people = try? await fetchProfiles(ids: ids) else { return [:] }
            return people.reduce(into: [:]) { out, p in
                out[p.id] = RexProfile(username: p.username, display_name: p.display_name, avatar_url: p.avatar_url)
            }
        }()

        let likes = (try? await fetchRequestCommentLikes(commentIds: rows.map { $0.id })) ?? [:]
        return rows.map { row in
            let like = likes[row.id]
            return RequestComment(
                id: row.id, request_id: row.request_id, user_id: row.user_id,
                body: row.body, created_at: row.created_at,
                profiles: profilesById[row.user_id],
                parent_id: row.parent_id,
                likeCount: like?.count ?? 0,
                likedByMe: like?.likedByMe ?? false
            )
        }
    }

    /// parent_id doesn't exist until migration 20260907160000 has been run,
    /// and selecting a missing column fails the whole query — same probe
    /// pattern as anonymousField() above.
    private var blastReplyColumn: Bool?
    private func blastReplyField() async -> String {
        if let blastReplyColumn { return blastReplyColumn ? ",parent_id" : "" }
        guard let token = try? await validToken() else { return "" }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/request_comments"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "parent_id"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let ok = (try? await URLSession.shared.data(for: request))
            .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
            .map { $0 < 400 } ?? false
        blastReplyColumn = ok
        return ok ? ",parent_id" : ""
    }

    func fetchRequestCommentLikes(commentIds: [String]) async throws -> [String: (count: Int, likedByMe: Bool)] {
        guard !commentIds.isEmpty else { return [:] }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/request_comment_likes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "comment_id,user_id"),
            URLQueryItem(name: "comment_id", value: "in.(\(commentIds.joined(separator: ",")))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [:] }
        struct Row: Codable { let comment_id: String; let user_id: String }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        let me = currentUserId
        var out: [String: (count: Int, likedByMe: Bool)] = [:]
        for row in rows {
            var entry = out[row.comment_id] ?? (0, false)
            entry.count += 1
            if row.user_id == me { entry.likedByMe = true }
            out[row.comment_id] = entry
        }
        return out
    }

    func setRequestCommentLike(commentId: String, liked: Bool) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/request_comment_likes"), resolvingAgainstBaseURL: false)!
        var request: URLRequest
        if liked {
            request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["comment_id": commentId, "user_id": userId])
        } else {
            components.queryItems = [
                URLQueryItem(name: "comment_id", value: "eq.\(commentId)"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            ]
            request = URLRequest(url: components.url!)
            request.httpMethod = "DELETE"
        }
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save that like."))
        }
    }

    /// #132 — reply to a blast. suggested_item_id is left null; the compose
    /// UI is plain text only for now (see RequestComment's doc comment).
    func createRequestComment(requestId: String, body text: String, parentId: String? = nil) async throws {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/request_comments"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["request_id": requestId, "user_id": userId, "body": text]
        if let parentId { body["parent_id"] = parentId }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't post your reply."))
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

    /// #181 — saved_posts embeds recommendations embeds profiles, and
    /// PostgREST's nested embedding is resolved by an actual FK to the
    /// named table specifically (saved_posts.recommendation_id ->
    /// recommendations.id) — there's no way to point a *nested* embed at
    /// recommendations_display instead, the way fetchFeed's own top-level
    /// query can (a view has no FK for anything to embed *through*).
    /// Two-step fetch instead: pull the bare saved_posts rows, batch the
    /// real (masked) recommendations separately via recommendationsReadPath
    /// — same technique fetchWantsFeed already uses for its own profiles —
    /// and merge client-side.
    private func fetchRecommendationsByIds(_ ids: [String]) async -> [String: FeedRecommendation] {
        guard !ids.isEmpty else { return [:] }
        guard let token = try? await validToken() else { return [:] }
        let (resourcePath, profilesSelect) = await recommendationsReadPath()
        let select = "id,rating,note,created_at,photo_url,photo_urls,tags\(await anonymousField()),user_id,item_id," +
            "items(id,type,title,subtitle,image_url,genre,recipe_text)," +
            "\(profilesSelect)"
        var components = URLComponents(url: baseURL.appendingPathComponent(resourcePath), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let recs = try? JSONDecoder().decode([FeedRecommendation].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: recs.map { ($0.id, $0) })
    }

    /// Posts saved from other people — the Pinterest-style half of Collections.
    func fetchSavedPosts() async throws -> [SavedPost] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }
        let select = "id,created_at,list_id,recommendation_id"
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
        struct Row: Codable {
            let id: String; let created_at: String?; let list_id: String?
            let recommendation_id: String; let section: String?; let sort_order: Int?
        }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        let recsById = await fetchRecommendationsByIds(rows.map { $0.recommendation_id })
        return rows.map {
            SavedPost(id: $0.id, created_at: $0.created_at, list_id: $0.list_id,
                       recommendation_id: $0.recommendation_id, recommendations: recsById[$0.recommendation_id],
                       section: $0.section, sort_order: $0.sort_order)
        }
    }

    /// What's inside one collection. Unlike `fetchSavedPosts` this isn't scoped
    /// to you — it's how you browse a friend's collection too, so RLS on
    /// hitlist_lists is what decides whether you can see it.
    func fetchCollectionItems(listId: String) async throws -> [SavedPost] {
        let token = try await validToken()
        let select = "id,created_at,list_id,recommendation_id,section,sort_order"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "list_id", value: "eq.\(listId)"),
            // Sept 8 — an explicit position, with created_at.desc left as
            // the tiebreak so a row saved before the migration (or from
            // the feed's save button, which claims no position) still
            // lands where it always did: newest of the unplaced ones
            // first, all of them after anything deliberately ordered.
            URLQueryItem(name: "order", value: "sort_order.asc.nullslast,created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't load that collection."))
        }
        struct Row: Codable { let id: String; let created_at: String?; let list_id: String?; let recommendation_id: String }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        let recsById = await fetchRecommendationsByIds(rows.map { $0.recommendation_id })
        return rows.map {
            SavedPost(id: $0.id, created_at: $0.created_at, list_id: $0.list_id,
                       recommendation_id: $0.recommendation_id, recommendations: recsById[$0.recommendation_id])
        }
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
    /// #184 — "want to try not appearing on the feed", the actual bug: not
    /// the search/filter path (fixed first, real but secondary — see below),
    /// but that wants NEVER showed in the feed at all, for anyone, in any
    /// state. Root cause was the `profiles!wants_user_id_fkey(...)` embed
    /// on the old query. That constraint name is real (Postgres's default
    /// auto-name for wants.user_id's FK), but pointed at auth.users, not
    /// public.profiles — the identically-shaped `profiles!
    /// recommendations_user_id_fkey` embed used throughout the rest of this
    /// file works anyway (PostgREST bridges it through profiles' own FK to
    /// auth.users), but whatever made that work didn't hold for wants, so
    /// PostgREST couldn't resolve the relationship and every single request
    /// failed — silently, since the failure is swallowed by `try?` a few
    /// lines down, so it read as "no wants" rather than an error.
    /// Rather than keep relying on unverifiable embed-inference behaviour,
    /// this now fetches wants+items the same proven-safe way fetchWants()
    /// (Collections, which never broke) already does — plain items(...),
    /// no !inner, no profiles embed at all — and batches profiles
    /// separately via fetchProfiles(ids:), merged in client-side.
    ///
    /// category/searchText mirror fetchFeed's own parameters (added when
    /// the search/filter path was found to skip wants entirely) so
    /// FeedView can merge wants into a filtered/searched result the same
    /// way loadFeed() merges them into the unfiltered one. Searching by
    /// the poster's username/display name isn't supported here any more —
    /// that relied on the same broken embed — only title/note match.
    func fetchWantsFeed(category: String? = nil, searchText: String? = nil) async throws -> [FeedRecommendation] {
        let token = try await validToken()
        guard currentUserId != nil else { return [] }
        let noteField = await wantNoteField()
        let select = "id,created_at,item_id,user_id\(noteField)," +
            "items(id,type,title,subtitle,image_url,genre,address,link_url,recipe_text,lat,lng)"
        struct Row: Codable {
            let id: String
            let created_at: String
            let item_id: String
            let user_id: String
            let note: String?
            let items: RexItem?
        }

        let trimmedSearch = searchText?.trimmingCharacters(in: .whitespaces)
        let isFiltered = category != nil || !(trimmedSearch ?? "").isEmpty
        // Was 30, then 100 — a want to try has no rating and often no note
        // either, so it's easy for a page this small to end up entirely
        // stale ones from a quiet week rather than anything recent. Filtered
        // needs real range for the same reason fetchFeed's does: the match
        // could be anywhere in your history, not just the last page.
        let limit = isFiltered ? 300 : 100

        func fetchRows(extraFilters: [(String, String)]) async -> [Row] {
            var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
            var queryItems = [
                URLQueryItem(name: "select", value: select),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "\(limit)"),
            ]
            for filter in extraFilters { queryItems.append(URLQueryItem(name: filter.0, value: filter.1)) }
            components.queryItems = queryItems
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode < 400
            else { return [] }
            return (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        }

        // Sept 8 — "your own 'want to try's should not appear on feed". The
        // feed is what other people have Rex'd; your own wants are a
        // private shortlist you already have a screen for (the Wants tab),
        // and seeing them mixed in reads as though you'd posted them.
        // Someone else's want still shows — that's a genuine signal.
        var ownerFilter: [(String, String)] = []
        if let currentUserId { ownerFilter = [("user_id", "neq.\(currentUserId)")] }
        // Sept 9 — "when Gemma saves one of my Rex so it becomes a want to
        // try for her it shouldn't come up on the feed again". Bookmarking
        // someone's Rex is a private save of something the feed has
        // already shown once; re-posting it as her want is the same
        // recommendation twice, the second time under the wrong name. A
        // want added from scratch still posts — nobody has Rex'd that yet,
        // so it's the only way anyone hears about it.
        //
        // Sept 11 — "Phoebe just added a want to try TV and doesn't appear in
        // the feed". This was `source=neq.save`, which PostgREST turns into
        // SQL `source <> 'save'` — and that's never true for NULL. Every want
        // created by a build older than 33 (or anything else that doesn't
        // know about the column) has a NULL source, so all of them were
        // silently filtered out. Unknown now counts as shown: an old client's
        // want appears the way every want did before, which is the safe side
        // to be wrong on — a card too many, rather than a friend's new want
        // that nobody ever sees.
        if await wantSourceField() { ownerFilter.append(("or", "(source.is.null,source.neq.save)")) }
        let categoryFilter: [(String, String)] = ownerFilter + (category.map { [("items.type", "eq.\($0)")] } ?? [])
        let rows: [Row]
        let profilesById: [String: RexProfile]
        if let trimmedSearch, !trimmedSearch.isEmpty {
            // Poster username/display_name search used to go through the
            // same profiles!wants_user_id_fkey embed that turned out to be
            // broken (see this function's doc comment) — dropping it fixed
            // wants showing up at all, but lost name search as a casualty.
            // Restored here without the embed: pull everything in the
            // category (unfiltered by text — wants are low-volume enough
            // that this is cheap), batch-fetch profiles once, then match
            // title/subtitle/note/username/display_name together client-
            // side. Covers strictly more than the old embed-based search
            // did (that only ever matched title or note, one field per
            // request), in one pass instead of several.
            let candidates = await fetchRows(extraFilters: categoryFilter)
            let byId = Dictionary(
                uniqueKeysWithValues: ((try? await fetchProfiles(ids: Array(Set(candidates.map { $0.user_id })))) ?? [])
                    .map { ($0.id, RexProfile(username: $0.username, display_name: $0.display_name, avatar_url: $0.avatar_url)) }
            )
            let q = trimmedSearch.lowercased()
            rows = candidates.filter { row in
                let profile = byId[row.user_id]
                let haystack = [
                    row.items?.title, row.items?.subtitle, row.note,
                    profile?.username, profile?.display_name,
                ].compactMap { $0 }.joined(separator: " ").lowercased()
                return haystack.contains(q)
            }
            profilesById = byId
        } else {
            rows = await fetchRows(extraFilters: categoryFilter)
            profilesById = Dictionary(
                uniqueKeysWithValues: ((try? await fetchProfiles(ids: Array(Set(rows.map { $0.user_id })))) ?? [])
                    .map { ($0.id, RexProfile(username: $0.username, display_name: $0.display_name, avatar_url: $0.avatar_url)) }
            )
        }

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
                profiles: profilesById[row.user_id],
                creators: nil,
                trip_section: nil,
                is_anonymous: false,
                list_section: nil,
                show_in_feed: nil,
                recommendation_tags: nil
            )
        }
    }

    /// Same guard as wantNoteColumn, for wants.source (9 Sept migration).
    private var wantSourceColumn: Bool?

    private func wantSourceField() async -> Bool {
        if let wantSourceColumn { return wantSourceColumn }
        guard let token = try? await validToken() else { return false }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "source"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let ok = (try? await URLSession.shared.data(for: request))
            .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
            .map { $0 < 400 } ?? false
        wantSourceColumn = ok
        return ok
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
        // A blast has no real `items` row — FeedRecommendation gives it a
        // synthetic "blast-<uuid>" item_id purely so it has an Identifiable
        // id to key off of client-side. That string isn't a real uuid, so
        // whenever a blast rode along in this batch (any real feed page,
        // basically), PostgREST 400'd on the whole `in.(...)` list with
        // "invalid input syntax for type uuid" — and since the guard below
        // just swallows a non-2xx response as "no counts", the ENTIRE
        // page's rex-counts silently came back empty, not just the blast's.
        // Invisible before now because a zero count used to just hide the
        // "Also Rex'd by" row; the always-shown rex-icon count (see
        // RexCardActions) is what actually surfaced it as every card
        // reading 0. Filtering these out is the fix, not a workaround —
        // there was never a real count to fetch for a blast in the first
        // place.
        let realItemIds = itemIds.filter { !$0.hasPrefix("blast-") }
        guard !realItemIds.isEmpty else { return [:] }
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "item_id"),
            URLQueryItem(name: "item_id", value: "in.(\(realItemIds.joined(separator: ",")))"),
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

    /// Everyone who's Rex'd this item, newest first — the tap target behind
    /// the card's rex-icon count (see RexCardActions). Same masked-profiles
    /// path as every other recommendations read, so an anonymous poster
    /// shows up in the list (they still count) without naming them.
    func fetchRexers(itemId: String) async throws -> [RexerInfo] {
        let token = try await validToken()
        let (resourcePath, profilesSelect) = await recommendationsReadPath()
        let select = "id,user_id,rating,created_at\(await anonymousField()),\(profilesSelect)"
        var components = URLComponents(url: baseURL.appendingPathComponent(resourcePath), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "item_id", value: "eq.\(itemId)"),
            URLQueryItem(name: "trip_id", value: "is.null"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load who's Rex'd this.")
        }
        return try JSONDecoder().decode([RexerInfo].self, from: data)
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
        // "the map doesn't even load" (Aug 26/27) — the embedded profiles(...)
        // here used to be unqualified, which was fine until #162 added
        // recommendation_tags: that table's own FKs to both recommendations
        // and profiles gave PostgREST a second path between them, so a bare
        // `profiles(...)` embed became ambiguous. PostgREST answers an
        // ambiguous embed with HTTP 300 and an error object describing the
        // two candidate relationships instead of the row data — which slid
        // straight past this function's `statusCode < 400` success check
        // and into JSONDecoder, which then failed on a dictionary where it
        // expected an array. Naming the FK explicitly (as PostgREST's own
        // error hint suggested) resolves the ambiguity outright — same fix
        // applied to fetchMapPlaces(forTrip:) and fetchMapPlace(itemId:)
        // below, which embed the exact same way.
        let select = "id,title,subtitle,type,genre,address,lat,lng,image_url," +
            "recommendations!inner(id,rating,user_id,trip_id,profiles!recommendations_user_id_fkey(username,display_name,avatar_url))"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "type", value: "in.(place,event)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            // #164 — this used to cap at 200, which meant genuinely old
            // (pre-Lovable-migration) place/event Rex could be excluded from
            // the map's own dataset outright, before the self-heal geocode
            // repair even got a chance to run on them: created_at.desc
            // + limit only ever takes the newest 200, so an old row past
            // that cutoff was never fetched at all, geocoded or not. Raised
            // well past any real friend group's total place/event count
            // rather than removed outright, so a single pathological account
            // can't make this unbounded.
            URLQueryItem(name: "limit", value: "2000"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server("Couldn't load the map.")
        }
        // lat/lng are nullable in the schema even though we need them to
        // place a pin, mostly for Lovable-era Rex predating #135's
        // geocode-on-add. This used to self-heal right here — geocoding
        // every missing one via a TaskGroup and awaiting the whole batch
        // before returning — but with #164's limit raised to 2000, a
        // legacy backlog of un-geocoded rows turned "open the map" into a
        // multi-second wait on Google's Geocoding API, once per item, on
        // every single load (reported: "map takes ages to load"). Repair
        // now happens in the background via repairMissingMapCoords, kicked
        // off by MapView.load() *after* this returns rather than before —
        // this just returns what's already geocoded, immediately.
        return try JSONDecoder().decode([MapPlace].self, from: data)
    }

    /// Fire-and-forget geocode repair for whatever fetchMapPlaces()/
    /// fetchMapWants() came back with that's still missing lat/lng — see
    /// fetchMapPlaces' doc comment for why this moved out of the awaited
    /// load path. Each repaired place is reported back via `onRepaired` as
    /// it resolves (on the main actor, safe to fold straight into @State)
    /// rather than blocking the map's initial render on the whole backlog.
    /// repairPlaceCoordsIfNeeded's own dedup guard keeps this from re-firing
    /// for the same item within a session, and it persists successes to the
    /// item row, so the backlog only ever gets smaller across app launches.
    func repairMissingMapCoords(_ places: [MapPlace], onRepaired: @escaping (MapPlace) -> Void) {
        for place in places {
            guard place.lat == nil || place.lng == nil,
                  let address = place.address, !address.isEmpty else { continue }
            Task {
                guard let located = await self.repairPlaceCoordsIfNeeded(itemId: place.id, address: address) else { return }
                let repaired = MapPlace(
                    id: place.id, title: place.title, subtitle: place.subtitle, type: place.type,
                    genre: place.genre, address: place.address, lat: located.lat, lng: located.lng,
                    image_url: place.image_url, recommendations: place.recommendations
                )
                await MainActor.run { onRepaired(repaired) }
            }
        }
    }

    /// Sept 8 — re-geocodes every stop in a trip, using the trip's name as
    /// context. Deliberate and owner-triggered, unlike the passive
    /// self-heal in fetchMapPlaces(forTrip:), because it exists for the
    /// stops that self-heal can never fix: ones that *did* geocode, but to
    /// the wrong "The Ivy" in the wrong city. Nothing about a plausible
    /// wrong coordinate looks wrong to a computer, so this can only ever
    /// be a thing you ask for.
    ///
    /// Bypasses geocodeRepairedItemIds outright — that guard exists to
    /// stop passive repair hammering the geocoder on every map load, and
    /// asking for a re-run is exactly the case it shouldn't apply to.
    /// Skips a stop whose address someone typed by hand: that's a
    /// deliberate correction and worth more than a fresh guess.
    func regeocodeTripStops(
        tripRecommendationId: String, tripName: String
    ) async throws -> (fixed: Int, total: Int) {
        let stops = try await fetchTripStops(tripRecommendationId: tripRecommendationId)
        let token = try await validToken()
        var fixed = 0
        var total = 0
        for stop in stops {
            guard let item = stop.items,
                  item.type == "place" || item.type == "event" else { continue }
            total += 1
            // Sept 15 — the saved address first (Sora Lella's said Rome all
            // along; only its pin was in Jenin), then the name through
            // Places with the trip's name for context.
            guard let located = await RexSearch.locate(
                name: item.title, address: item.address, context: [item.subtitle, tripName]
            ) else { continue }

            var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/items"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "id", value: "eq.\(item.id)")]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "PATCH"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = ["lat": located.lat, "lng": located.lng]
            if (item.address ?? "").isEmpty, let resolved = located.address, !resolved.isEmpty {
                body["address"] = resolved
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode < 400 else { continue }
            // So the map picks the new point up this session rather than
            // treating the stop as already repaired and skipping it.
            _ = Self.repairLock.withLock { Self.geocodeRepairedItemIds.remove(item.id) }
            fixed += 1
        }
        return (fixed, total)
    }

    /// A specific trip's own stops, regardless of whether they're in
    /// fetchMapPlaces' most-recent-200 sample. "Following" a trip used to
    /// only work if its stops happened to already be loaded, which was fine
    /// when the only way to pick a trip was tapping a chip built from that
    /// same sample — TripSearchView breaks that assumption by letting you
    /// pick any trip, so following it needs its own fetch.
    func fetchMapPlaces(forTrip tripRecommendationId: String, tripName: String? = nil) async throws -> [MapPlace] {
        let token = try await validToken()
        let select = "id,title,subtitle,type,genre,address,lat,lng,image_url," +
            "recommendations!inner(id,rating,user_id,trip_id,profiles!recommendations_user_id_fkey(username,display_name,avatar_url))"
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
        // Same self-heal as fetchMapPlaces() — a trip stop with an address
        // but no coordinates (pre-#135 data, or a doc-import row whose query
        // didn't resolve first time) should still get a shot at geocoding
        // here rather than just quietly missing from the trip's map/tile.
        let repaired = await withTaskGroup(of: MapPlace.self) { group in
            for place in places {
                group.addTask {
                    guard place.lat == nil || place.lng == nil else { return place }
                    // Sept 8 — no longer gated on having an address. A stop
                    // imported before the importer geocoded anything has
                    // neither address nor coordinates, and was skipped here
                    // every time; the trip's own name is the context that
                    // makes its bare title resolvable.
                    let fallback = [place.title, place.subtitle, tripName]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                    guard let located = await self.repairPlaceCoordsIfNeeded(
                        itemId: place.id, address: place.address ?? "", fallbackQuery: fallback
                    ) else { return place }
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

    /// One specific place/event, regardless of whether it's in
    /// fetchMapPlaces' most-recent-200 sample — #133's "view on map" needs
    /// to guarantee the pin it's jumping to actually loads, the same reason
    /// fetchMapPlaces(forTrip:) exists rather than trusting the sample.
    func fetchMapPlace(itemId: String) async throws -> MapPlace? {
        let token = try await validToken()
        let select = "id,title,subtitle,type,genre,address,lat,lng,image_url," +
            "recommendations!inner(id,rating,user_id,trip_id,profiles!recommendations_user_id_fkey(username,display_name,avatar_url))"
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

    /// #153 — a want has no recommendations row at all (it lives in the
    /// separate `wants` table entirely), so fetchMapPlaces' inner join on
    /// recommendations excluded it completely: marking a place "want to
    /// try" never made it a pin. Same shape as fetchFeed's wants/blasts
    /// merge — a separate fetch, combined client-side in RexMapView.load(),
    /// rather than fighting PostgREST to OR across two unrelated child
    /// tables in one query.
    /// #184 — this had the same broken `profiles!wants_user_id_fkey` embed
    /// fetchWantsFeed did (see that function's doc comment for the full
    /// story), so it silently 400'd and returned zero want-pins on every
    /// call. Same fix: drop the embed, batch profiles separately.
    func fetchMapWants() async throws -> [MapPlace] {
        let token = try await validToken()
        let select = "id,user_id,item_id," +
            "items!inner(id,title,subtitle,type,genre,address,lat,lng,image_url)"
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/wants"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "items.type", value: "in.(place,event)"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        struct Row: Codable {
            let id: String
            let user_id: String
            let item_id: String
            let items: Item
            struct Item: Codable {
                let id: String, title: String, subtitle: String?, type: String
                let genre: String?, address: String?, lat: Double?, lng: Double?, image_url: String?
            }
        }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        let profilesById = Dictionary(
            uniqueKeysWithValues: ((try? await fetchProfiles(ids: Array(Set(rows.map { $0.user_id })))) ?? [])
                .map { ($0.id, RexProfile(username: $0.username, display_name: $0.display_name, avatar_url: $0.avatar_url)) }
        )
        // Geocode repair used to happen inline here too — one address at a
        // time, awaited, the worst offender behind "map takes ages to
        // load" since it wasn't even concurrent the way fetchMapPlaces' was.
        // Same fix: return what's already geocoded (or not) and let
        // MapView.load() hand the gaps to repairMissingMapCoords instead.
        return rows.map { row in
            MapPlace(
                id: row.items.id, title: row.items.title, subtitle: row.items.subtitle, type: row.items.type,
                genre: row.items.genre, address: row.items.address, lat: row.items.lat, lng: row.items.lng,
                image_url: row.items.image_url,
                // rating 0 / trip_id nil — a want has neither; the synthetic
                // "want-" id prefix keeps it distinct if this same item also
                // has a real recommendation (see the merge in load()).
                recommendations: [MapRecStub(id: "want-\(row.id)", rating: 0, user_id: row.user_id, trip_id: nil, profiles: profilesById[row.user_id])]
            )
        }
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
        let rows: [[String: Any]] = items.prefix(200).enumerated().map { index, item in
            var row: [String: Any] = [
                "user_id": userId,
                "source": source,
                "raw_title": String(item.title.prefix(300)),
                "status": "pending",
                // The document's own order, which nothing else preserves —
                // see fetchStagingRows.
                "sort_order": index,
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

        func post(_ body: [[String: Any]]) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: baseURL.appendingPathComponent("/rest/v1/import_staging"))
            request.httpMethod = "POST"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as? HTTPURLResponse ?? HTTPURLResponse())
        }

        var (data, http) = try await post(rows)
        // Same one-shot fallback as fetchStagingRows: sort_order doesn't
        // exist until migration 20260905090000 has been run, and an import
        // that refuses to save is much worse than one that saves without
        // its ordinal.
        if http.statusCode == 400 {
            let withoutOrder = rows.map { row -> [String: Any] in
                var copy = row
                copy.removeValue(forKey: "sort_order")
                return copy
            }
            (data, http) = try await post(withoutOrder)
        }
        guard http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save the extracted items."))
        }
        return rows.count
    }

    /// Sept 5 — every row of one import is POSTed in a single request, so
    /// they share an identical created_at (Postgres holds now() constant
    /// for a transaction) and ordering by it ordered by nothing at all,
    /// which is why the review screen read as reversed. sort_order (see
    /// migration 20260905090000) is the real ordinal. Tried first and
    /// falling back once on a 400, the same shape as show_in_feed above —
    /// the column doesn't exist until that migration is run, and an import
    /// that can't be reviewed at all would be far worse than one in the
    /// old arbitrary order.
    func fetchStagingRows(source: String) async throws -> [ImportStagingRow] {
        let token = try await validToken()
        guard let userId = currentUserId else { throw RexAPIError.notSignedIn }

        func fetch(orderBy: String) async throws -> (Data, HTTPURLResponse) {
            var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/import_staging"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "source", value: "eq.\(source)"),
                URLQueryItem(name: "status", value: "eq.pending"),
                URLQueryItem(name: "order", value: orderBy),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as? HTTPURLResponse ?? HTTPURLResponse())
        }

        var (data, http) = try await fetch(orderBy: "sort_order.asc.nullslast,created_at.asc")
        if http.statusCode == 400 {
            (data, http) = try await fetch(orderBy: "created_at.asc")
        }
        guard http.statusCode < 400 else {
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
    /// Sept 7 — retypes one staged row and nothing else, for the review
    /// screen's "these are all…" control. updateStagingRow below rewrites
    /// the title, creator and note too, which a bulk retype has no business
    /// touching — and it deliberately clears the resolved_* columns, which
    /// would throw away every thumbnail the background resolver had found.
    func updateStagingRowType(id: String, type: String) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/import_staging"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["suggested_type": type])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't change the type."))
        }
    }

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
        showInFeed: Bool? = nil,
        // Aug 30 — "all my trips have wildly-off geocoding": raw_creator is
        // only ever populated when the extraction happened to notice a
        // city/cuisine on that exact row, which for a casually-pasted
        // itinerary is inconsistent at best. A bare venue name with nothing
        // else to disambiguate it ("The Ivy", "The Anchor") reliably
        // geocodes to a same-named place absolutely anywhere in the world.
        // The trip/list/collection's own name is almost always itself a
        // destination (Kathryn's own: "St Mawes trip", "Loire - Les Sables
        // d'Olonne - Brittany") — a second, usually-present disambiguator
        // costs nothing to append and fixes the common case outright.
        locationHint: String? = nil,
        // Sept 8 — where this row lands inside the collection named by
        // `listId`. Only the collection importer sets these; every other
        // caller adds to a collection without a heading or a position.
        collectionSection: String? = nil,
        collectionSortOrder: Int? = nil
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
                if let located = await RexSearch.locate(
                    name: row.raw_title, address: nil, context: [row.raw_creator, locationHint]
                ) {
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
            try await addToCollection(
                recommendationId: recId, listId: listId,
                section: collectionSection, sortOrder: collectionSortOrder
            )
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
                try await approveOneStagingRow(
                    row, rating: nil, note: nil, tripId: tripRecId, tripSection: row.raw_section, listId: nil,
                    locationHint: tripName
                )
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
                    docListId: listRecId, docListSection: row.raw_section, showInFeed: showInFeedIds.contains(row.id),
                    locationHint: listName
                )
                added += 1
            } catch {
                failed.append(ImportFailure(title: row.raw_title, reason: error.localizedDescription))
            }
        }
        return (listRecId, added, failed)
    }

    /// Sept 8 — "make sure we can upload a doc straight to a collection".
    /// approveStagingAsCollections always *creates* collections; this adds
    /// to one that already exists, which is what you want standing inside
    /// it looking at the twelve places you've already saved by hand.
    ///
    /// Rows keep the document's own order and its headings. This used to
    /// insert back-to-front, because a collection had no order column and
    /// read newest-first, so going forwards showed the document upside
    /// down. saved_posts carries a real position now, so the reversal is
    /// gone — and the reversal was always a trick that broke the moment
    /// anything else was added to the collection afterwards.
    ///
    /// Numbering continues past whatever is already in the collection, so
    /// importing a second document appends rather than interleaving with
    /// the first. Worked out here rather than asked of the caller — the
    /// review screen has no business knowing how the collection it's
    /// filling is ordered.
    func approveStagingIntoCollection(
        rows: [ImportStagingRow], listId: String
    ) async throws -> (added: Int, failed: [ImportFailure]) {
        guard !rows.isEmpty else { throw RexAPIError.server("Nothing to import.") }
        let startingAt = ((try? await fetchCollectionItems(listId: listId)) ?? [])
            .compactMap { $0.sort_order }.max().map { $0 + 1 } ?? 0
        var added = 0
        var failed: [ImportFailure] = []
        for (index, row) in rows.enumerated() {
            do {
                let section = row.raw_section?.trimmingCharacters(in: .whitespaces)
                try await approveOneStagingRow(
                    row, rating: nil, note: nil, tripId: nil, tripSection: nil, listId: listId,
                    locationHint: row.raw_section,
                    collectionSection: (section?.isEmpty == false) ? section : nil,
                    collectionSortOrder: startingAt + index
                )
                added += 1
            } catch {
                failed.append(ImportFailure(title: row.raw_title, reason: error.localizedDescription))
            }
        }
        return (added, failed)
    }

    /// Persists a whole collection's order and headings in one request per
    /// row. Same approach TripDetailView's reorder takes: the client owns
    /// the arrangement and writes the result, rather than trying to
    /// express a move as a relative operation the server has to resolve.
    func setCollectionOrder(_ entries: [(savedPostId: String, section: String?, sortOrder: Int)]) async throws {
        let token = try await validToken()
        for entry in entries {
            var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "id", value: "eq.\(entry.savedPostId)")]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "PATCH"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "sort_order": entry.sortOrder,
                "section": (entry.section?.isEmpty ?? true) ? (NSNull() as Any) : entry.section!,
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
                throw RexAPIError.server(friendlyError(data, fallback: "Couldn't save the new order."))
            }
        }
    }

    /// A heading is a repeated string, not a row — renaming one means
    /// patching every saved post that carries it, exactly as
    /// renameTripSection does for a trip.
    func renameCollectionSection(listId: String, from: String?, to: String?) async throws {
        let token = try await validToken()
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/saved_posts"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "list_id", value: "eq.\(listId)"),
            URLQueryItem(name: "section", value: (from?.isEmpty ?? true) ? "is.null" : "eq.\(from!)"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "section": (to?.isEmpty ?? true) ? (NSNull() as Any) : to!,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw RexAPIError.server(friendlyError(data, fallback: "Couldn't rename that heading."))
        }
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
                    try await approveOneStagingRow(
                        row, rating: nil, note: nil, tripId: nil, tripSection: nil, listId: listId,
                        locationHint: key
                    )
                    added += 1
                } catch {
                    failed.append(ImportFailure(title: row.raw_title, reason: error.localizedDescription))
                }
            }
        }
        return (added, order.count, failed)
    }
}
