import Foundation

/// A search suggestion from an external catalogue, mirroring the web SearchHit.
struct RexSearchHit: Identifiable, Hashable {
    let externalId: String
    let externalSource: String
    let title: String
    let subtitle: String?
    let imageURL: String?
    let genre: String?
    // Places only.
    let address: String?
    let lat: Double?
    let lng: Double?

    var id: String { "\(externalSource):\(externalId)" }

    init(
        externalId: String, externalSource: String, title: String,
        subtitle: String? = nil, imageURL: String? = nil, genre: String? = nil,
        address: String? = nil, lat: Double? = nil, lng: Double? = nil
    ) {
        self.externalId = externalId
        self.externalSource = externalSource
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.genre = genre
        self.address = address
        self.lat = lat
        self.lng = lng
    }
}

/// Search-as-you-type against the same catalogues the web app uses. Native
/// calls them directly rather than via our Worker — no CORS to worry about,
/// one less hop, and it sidesteps the Cloudflare egress-IP blocks that break
/// iTunes server-side.
enum RexSearch {
    private static var tmdbKey: String {
        Bundle.main.object(forInfoDictionaryKey: "TMDBApiKey") as? String ?? ""
    }
    private static var googleKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    }
    private static var bundleId: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    static func search(category: RexCategory, query: String) async -> [RexSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        do {
            switch category {
            case .book:            return try await books(q)
            case .movie:           return try await tmdb(q, kind: "movie")
            case .tv:              return try await tmdb(q, kind: "tv")
            case .podcast:         return try await podcasts(q)
            case .place, .event:   return try await places(q)
            default:               return []
            }
        } catch {
            return []
        }
    }

    // MARK: - Providers

    /// OpenLibrary — no key, generous quota.
    private static func books(_ q: String) async throws -> [RexSearchHit] {
        let url = "https://openlibrary.org/search.json?q=\(esc(q))&limit=15&fields=key,title,author_name,first_publish_year,cover_i,subject"
        let json = try await getJSON(url)
        let docs = json["docs"] as? [[String: Any]] ?? []
        return docs.compactMap { d in
            guard let key = d["key"] as? String else { return nil }
            let authors = (d["author_name"] as? [String]) ?? []
            let year = d["first_publish_year"] as? Int
            var subtitle = authors.joined(separator: ", ")
            if let year { subtitle += subtitle.isEmpty ? "\(year)" : " · \(year)" }
            let cover = (d["cover_i"] as? Int).map { "https://covers.openlibrary.org/b/id/\($0)-M.jpg" }
            let subjects = (d["subject"] as? [String]) ?? []
            return RexSearchHit(
                externalId: key.hasPrefix("/") ? String(key.dropFirst()) : key,
                externalSource: "google_books",   // same enum value the web uses
                title: d["title"] as? String ?? "Untitled",
                subtitle: subtitle.isEmpty ? nil : subtitle,
                imageURL: cover,
                genre: subjects.first(where: { $0.count <= 22 }) ?? subjects.first
            )
        }
    }

    private static func tmdb(_ q: String, kind: String) async throws -> [RexSearchHit] {
        guard !tmdbKey.isEmpty else { return [] }
        let url = "https://api.themoviedb.org/3/search/\(kind)?api_key=\(tmdbKey)&query=\(esc(q))&include_adult=false"
        let json = try await getJSON(url)
        let results = json["results"] as? [[String: Any]] ?? []
        return results.prefix(15).compactMap { r in
            guard let id = r["id"] as? Int else { return nil }
            let title = (r["title"] ?? r["name"]) as? String ?? "Untitled"
            let date = (r["release_date"] ?? r["first_air_date"]) as? String
            let poster = (r["poster_path"] as? String).map { "https://image.tmdb.org/t/p/w200\($0)" }
            return RexSearchHit(
                externalId: String(id),
                externalSource: kind == "movie" ? "tmdb_movie" : "tmdb_tv",
                title: title,
                subtitle: date?.prefix(4).description,
                imageURL: poster
            )
        }
    }

    /// iTunes. Works fine from the device — the Cloudflare IP block that
    /// affects our Worker doesn't apply here.
    private static func podcasts(_ q: String) async throws -> [RexSearchHit] {
        let url = "https://itunes.apple.com/search?media=podcast&entity=podcast&limit=15&term=\(esc(q))"
        let json = try await getJSON(url)
        let results = json["results"] as? [[String: Any]] ?? []
        return results.compactMap { r in
            let id = (r["collectionId"] ?? r["trackId"]).map { "\($0)" } ?? ""
            guard !id.isEmpty else { return nil }
            let genres = r["genres"] as? [String] ?? []
            return RexSearchHit(
                externalId: id,
                externalSource: "itunes_podcast",
                title: r["collectionName"] as? String ?? r["trackName"] as? String ?? "Untitled",
                subtitle: r["artistName"] as? String,
                imageURL: r["artworkUrl600"] as? String ?? r["artworkUrl100"] as? String,
                genre: genres.first(where: { $0 != "Podcasts" }) ?? r["primaryGenreName"] as? String
            )
        }
    }

    /// Places API (New), called directly with the iOS key. Google accepts an
    /// iOS-restricted key for REST when the bundle id is sent as a header,
    /// which keeps this off our Worker entirely.
    private static func places(_ q: String) async throws -> [RexSearchHit] {
        guard !googleKey.isEmpty else { return [] }
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(googleKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue(
            "places.id,places.displayName,places.formattedAddress,places.location,places.primaryTypeDisplayName",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: ["textQuery": q, "pageSize": 10])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let results = json["places"] as? [[String: Any]] ?? []
        return results.compactMap { p in
            guard let id = p["id"] as? String else { return nil }
            let name = (p["displayName"] as? [String: Any])?["text"] as? String ?? "Untitled"
            let loc = p["location"] as? [String: Any]
            return RexSearchHit(
                externalId: id,
                externalSource: "google_places",
                title: name,
                subtitle: nil,
                imageURL: nil,
                genre: (p["primaryTypeDisplayName"] as? [String: Any])?["text"] as? String,
                address: p["formattedAddress"] as? String,
                lat: loc?["latitude"] as? Double,
                lng: loc?["longitude"] as? Double
            )
        }
    }

    // MARK: - Helpers

    private static func esc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static func getJSON(_ url: String) async throws -> [String: Any] {
        guard let parsed = URL(string: url) else { return [:] }
        let (data, response) = try await URLSession.shared.data(from: parsed)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
