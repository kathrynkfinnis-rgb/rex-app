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
    /// Google's public star rating, shown beneath friends' ratings.
    let googleRating: Double?
    let googleRatingCount: Int?
    /// #73/#103 — the web page a "Other"/Stuff search result came from.
    /// Nil for every other category; only productLookup() sets this.
    let productURL: String?

    var id: String { "\(externalSource):\(externalId)" }

    init(
        externalId: String, externalSource: String, title: String,
        subtitle: String? = nil, imageURL: String? = nil, genre: String? = nil,
        address: String? = nil, lat: Double? = nil, lng: Double? = nil,
        googleRating: Double? = nil, googleRatingCount: Int? = nil,
        productURL: String? = nil
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
        self.googleRating = googleRating
        self.googleRatingCount = googleRatingCount
        self.productURL = productURL
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
    private static var cseApiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "GoogleCSEApiKey") as? String ?? ""
    }
    private static var cseEngineId: String {
        Bundle.main.object(forInfoDictionaryKey: "GoogleCSEEngineId") as? String ?? ""
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
            case .other:           return try await productLookup(q)
            default:               return []
            }
        } catch {
            return []
        }
    }

    /// #73/#103 — books/movies/TV/podcasts/places each have their own real
    /// catalogue; "Other"/Stuff never had one, so it never got a photo or a
    /// product link beyond whatever the user typed in by hand. Google
    /// Programmable Search stands in as a generic "look this up on the web"
    /// catalogue for everything else — same search-then-pick flow as any
    /// other category, just backed by web results instead of a dedicated API.
    private static func productLookup(_ q: String) async throws -> [RexSearchHit] {
        guard !cseApiKey.isEmpty, !cseEngineId.isEmpty else { return [] }
        var components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
        components.queryItems = [
            URLQueryItem(name: "key", value: cseApiKey),
            URLQueryItem(name: "cx", value: cseEngineId),
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "num", value: "5"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return [] }
        return items.compactMap { item -> RexSearchHit? in
            guard let title = item["title"] as? String, let link = item["link"] as? String else { return nil }
            let snippet = item["snippet"] as? String
            var thumbnail: String?
            if let pagemap = item["pagemap"] as? [String: Any] {
                if let images = pagemap["cse_image"] as? [[String: Any]], let src = images.first?["src"] as? String {
                    thumbnail = src
                } else if let thumbs = pagemap["cse_thumbnail"] as? [[String: Any]], let src = thumbs.first?["src"] as? String {
                    thumbnail = src
                }
            }
            return RexSearchHit(
                externalId: link, externalSource: "google_cse", title: title,
                subtitle: snippet, imageURL: thumbnail, productURL: link
            )
        }
    }

    /// Oct 3 — "When you click on a Rex and it says 'on Google' with a link to
    /// the maps pin, can the same be done with other articles from popular
    /// news sources if they feature?"
    ///
    /// Same Programmable Search the product lookup uses, restricted to
    /// publications worth surfacing. The restriction is the whole point: an
    /// unfiltered web search for a restaurant returns its own site, three
    /// aggregators and a delivery app, none of which is "it was written
    /// about". A named list is blunt but honest — a result either is from
    /// somewhere recognisable or it doesn't appear.
    static func articles(about title: String, near locality: String?) async -> [RexArticle] {
        guard !cseApiKey.isEmpty, !cseEngineId.isEmpty else { return [] }

        let query = [title, locality, "review"].compactMap { $0 }.joined(separator: " ")
        var components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
        components.queryItems = [
            URLQueryItem(name: "key", value: cseApiKey),
            URLQueryItem(name: "cx", value: cseEngineId),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "num", value: "10"),
        ]
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return [] }

        var seen = Set<String>()
        return items.compactMap { item -> RexArticle? in
            guard let headline = item["title"] as? String,
                  let link = item["link"] as? String,
                  let host = URL(string: link)?.host?.lowercased()
            else { return nil }
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            guard let publication = Self.publications[bare] else { return nil }
            // One piece per publication — five Guardian results about the same
            // restaurant is a worse answer than five different papers.
            guard seen.insert(publication).inserted else { return nil }
            return RexArticle(
                publication: publication,
                headline: headline,
                snippet: item["snippet"] as? String,
                url: link
            )
        }
    }

    /// Hand-kept, deliberately. Anything automatic ("does the domain look like
    /// a newspaper?") puts SEO filler next to the Guardian and quietly makes
    /// the feature untrustworthy — which for a section headed "written about"
    /// is the only thing that matters.
    private static let publications: [String: String] = [
        "theguardian.com": "The Guardian",
        "thetimes.co.uk": "The Times",
        "telegraph.co.uk": "The Telegraph",
        "ft.com": "Financial Times",
        "standard.co.uk": "Evening Standard",
        "independent.co.uk": "The Independent",
        "bbc.co.uk": "BBC",
        "bbc.com": "BBC",
        "timeout.com": "Time Out",
        "theinfatuation.com": "The Infatuation",
        "squaremeal.co.uk": "SquareMeal",
        "hardens.com": "Harden's",
        "michelin.com": "Michelin Guide",
        "guide.michelin.com": "Michelin Guide",
        "nytimes.com": "The New York Times",
        "newyorker.com": "The New Yorker",
        "condenasttraveller.com": "Condé Nast Traveller",
        "cntraveller.com": "Condé Nast Traveller",
        "nationalgeographic.com": "National Geographic",
        "lonelyplanet.com": "Lonely Planet",
        "eater.com": "Eater",
        "bonappetit.com": "Bon Appétit",
        "observer.co.uk": "The Observer",
        "esquire.com": "Esquire",
        "gq-magazine.co.uk": "GQ",
        "vogue.co.uk": "Vogue",
        "harpersbazaar.com": "Harper's Bazaar",
        "delicious.com.au": "delicious.",
        "greatbritishchefs.com": "Great British Chefs",
    ]

    // MARK: - Providers

    /// OpenLibrary — no key, generous quota.
    ///
    /// Two searches, merged. OpenLibrary's plain `q` needs nearly the whole
    /// title before the right book surfaces — "long isl" returns Long Isle Iced
    /// Tea, not Colm Tóibín — so the main pass is a field-scoped title search
    /// with a trailing wildcard on the last word, which does match as you type.
    /// The plain search still earns its place for "title author" queries.
    /// Sept 28 — "streamline book search so you can search by author or
    /// title, and ensure only one version of each book comes up".
    ///
    /// Three passes rather than two, because the old pair could only really
    /// find a book by its title: typing an author's name fell through to the
    /// loose general search, which ranks by relevance across everything and
    /// buried the actual books. Author is now its own pass.
    ///
    /// And the dedupe is by the book rather than by the record. OpenLibrary
    /// hands back one entry per *work*, but the same novel routinely appears
    /// as several works — reissues, a translation, a film tie-in — each with
    /// its own key, so deduping on the key alone let all of them through.
    /// Matching on title-and-author collapses those into one, and the copy
    /// that survives is the one most likely to be the edition someone means:
    /// it has a cover, and it's the earliest printing.
    private static var editionCounts: [String: Int] = [:]
    private static let editionCountLock = NSLock()

    private static func books(_ q: String) async throws -> [RexSearchHit] {
        let words = q.split(separator: " ").count
        // OpenLibrary files plenty of books without their leading article —
        // Paul Murray's novel is "Bee Sting", not "The Bee Sting" — so a
        // title search for exactly what someone typed misses it entirely.
        let unarticled = dropLeadingArticle(q)
        async let titleHits = openLibrary("title=\(esc(wildcardLastWord(q)))")
        async let bareTitleHits: [RexSearchHit] = unarticled == q
            ? [] : openLibrary("title=\(esc(wildcardLastWord(unarticled)))")
        async let authorHits: [RexSearchHit] = words >= 2 ? openLibrary("author=\(esc(q))") : []
        async let generalHits: [RexSearchHit] = words >= 2 ? openLibrary("q=\(esc(q))") : []

        // Sept 27 — "A new popular book couldn't be found." OpenLibrary is
        // thin on very recent titles: a novel out this season often isn't
        // filed yet under any of the four passes above, and no amount of
        // re-ranking finds a record that isn't there. Google Books has them,
        // and is already trusted here for synopses and ratings — this is the
        // same source doing the same job one step earlier. Appended rather
        // than merged in front, so OpenLibrary still wins the dedupe for
        // anything both know about, and its edition data keeps deciding
        // which printing to show.
        async let googleHits = googleBooks(q)

        let all = (try await titleHits) + (try await bareTitleHits)
            + (try await authorHits) + (try await generalHits)
            + (await googleHits)

        var best: [String: RexSearchHit] = [:]
        var order: [String] = []
        for hit in all {
            let key = bookIdentity(hit)
            guard let existing = best[key] else {
                best[key] = hit
                order.append(key)
                continue
            }
            if preferredEdition(hit, over: existing) { best[key] = hit }
        }
        // Rank rather than trust the order the passes came back in: a title
        // that matches exactly, or an author who does, beats OpenLibrary's own
        // relevance — which happily puts a study guide above the novel it's
        // about. Edition count breaks the remaining ties.
        let target = normalizedBookPart(q)
        let ranked = order.compactMap { best[$0] }.sorted { left, right in
            score(left, target: target) > score(right, target: target)
        }
        return Array(ranked.prefix(15))
    }

    /// Google Books as a second book source, for the recent titles
    /// OpenLibrary hasn't catalogued. Unkeyed, same as the details lookup
    /// further down this file; a failure returns nothing rather than throwing,
    /// because it's a supplement and book search must not start failing if
    /// Google rate-limits us.
    private static func googleBooks(_ q: String) async -> [RexSearchHit] {
        guard let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=\(esc(q))&maxResults=10&printType=books"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return [] }

        return items.compactMap { volume -> RexSearchHit? in
            guard let id = volume["id"] as? String,
                  let info = volume["volumeInfo"] as? [String: Any],
                  let title = info["title"] as? String
            else { return nil }
            let authors = (info["authors"] as? [String])?.joined(separator: ", ")
            // Google's thumbnails come back as http and with a curl page the
            // cover is half-hidden behind; both are fixable in the URL.
            let cover = ((info["imageLinks"] as? [String: Any])?["thumbnail"] as? String)?
                .replacingOccurrences(of: "http://", with: "https://")
                .replacingOccurrences(of: "&edge=curl", with: "")
            return RexSearchHit(
                externalId: id,
                externalSource: "google_books",
                title: title,
                subtitle: authors,
                imageURL: cover,
                genre: (info["categories"] as? [String])?.first
            )
        }
    }

    /// Ranking, because OpenLibrary's own relevance is not good enough to
    /// trust: searching an author's name returns study guides about them
    /// above their novels, and a title search can bury a 2023 prizewinner
    /// under Victorian railway pamphlets that happen to share its name.
    ///
    /// The author match is weighted above an exact title match on purpose —
    /// someone typing "Colm Toibin" wants his books, not the biography of
    /// him that is literally called "Colm Toibin". Recency is worth real
    /// points too: people recommend books published in their lifetime, and
    /// an exact title match still beats it, so the classics survive.
    private static func score(_ hit: RexSearchHit, target: String) -> Int {
        var points = 0
        let title = normalizedBookPart(hit.title.split(separator: ":").first.map(String.init) ?? hit.title)
        let author = normalizedBookPart((hit.subtitle ?? "").split(separator: "·").first.map(String.init) ?? "")

        if author == target { points += 1_200 }
        else if author.contains(target) { points += 500 }

        if title == target { points += 1_000 }
        else if title.hasPrefix(target) { points += 400 }

        if hit.imageURL != nil { points += 60 }

        let published = year(of: hit)
        if published != .max, published >= 2000 { points += 250 }
        else if published != .max, published >= 1970 { points += 100 }

        let editions = editionCountLock.withLock { editionCounts["/" + hit.externalId] ?? 0 }
        return points + min(editions, 300)
    }

    private static func dropLeadingArticle(_ q: String) -> String {
        var words = q.split(separator: " ").map(String.init)
        if let first = words.first?.lowercased(), ["the", "a", "an"].contains(first), words.count > 1 {
            words.removeFirst()
            return words.joined(separator: " ")
        }
        return q
    }

    /// The same novel however it was catalogued: title and first author,
    /// stripped of the things that differ between editions — a subtitle after
    /// a colon, articles, punctuation, case.
    private static func bookIdentity(_ hit: RexSearchHit) -> String {
        let title = hit.title
            .split(separator: ":").first.map(String.init) ?? hit.title
        let author = (hit.subtitle ?? "")
            .split(separator: "·").first.map(String.init) ?? ""
        return normalizedBookPart(title) + "|" + normalizedBookPart(author)
    }

    private static func normalizedBookPart(_ text: String) -> String {
        let lowered = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        let stripped = lowered.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        var words = String(String.UnicodeScalarView(stripped))
            .split(separator: " ").map(String.init)
        if let first = words.first, ["the", "a", "an"].contains(first) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// Which of two records for the same book to keep. A cover matters most —
    /// a coverless row looks broken in the results — then the earliest year,
    /// which is the original rather than a reissue.
    private static func preferredEdition(_ candidate: RexSearchHit, over existing: RexSearchHit) -> Bool {
        let candidateHasCover = candidate.imageURL != nil
        let existingHasCover = existing.imageURL != nil
        if candidateHasCover != existingHasCover { return candidateHasCover }
        return year(of: candidate) < year(of: existing)
    }

    private static func year(of hit: RexSearchHit) -> Int {
        guard let tail = hit.subtitle?.split(separator: "·").last else { return .max }
        return Int(tail.trimmingCharacters(in: .whitespaces)) ?? .max
    }

    /// Everything OpenLibrary has by a given author — the real bibliography,
    /// not just what's been Rex'd on the app. AuthorBooksView cross-references
    /// this against our own items table to know which entries are tappable.
    static func byAuthor(_ author: String) async throws -> [RexSearchHit] {
        let hits = try await openLibrary("author=\(esc(author))")
        // OpenLibrary's author search does substring/loose matching and can
        // surface anthologies crediting dozens of people — keep only entries
        // that actually list this author, sorted by year so the catalogue
        // reads chronologically rather than by search-relevance noise.
        return hits
            .filter { hit in
                guard let subtitle = hit.subtitle else { return false }
                return subtitle.range(of: author, options: [.caseInsensitive]) != nil
            }
    }

    /// "long isl" → "long isl*", so a half-typed word still matches. Left alone
    /// if the last word is a single character, where the wildcard matches
    /// everything and ranking falls apart.
    private static func wildcardLastWord(_ q: String) -> String {
        var words = q.split(separator: " ").map(String.init)
        guard let last = words.last, last.count >= 2, !last.hasSuffix("*") else { return q }
        words[words.count - 1] = last + "*"
        return words.joined(separator: " ")
    }

    private static func openLibrary(_ queryPart: String) async throws -> [RexSearchHit] {
        let url = "https://openlibrary.org/search.json?\(queryPart)&limit=15&fields=key,title,author_name,first_publish_year,cover_i,subject,edition_count"
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
            // How many editions exist is the closest thing OpenLibrary gives
            // us to "is this the well-known one" — a novel everyone has read
            // has dozens; a self-published namesake has one.
            if let editions = d["edition_count"] as? Int, let key = d["key"] as? String {
                editionCountLock.withLock { editionCounts[key] = editions }
            }
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
            "places.id,places.displayName,places.formattedAddress,places.location," +
            "places.primaryTypeDisplayName,places.photos,places.rating,places.userRatingCount",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        // Text Search (New) defaults to biasing toward wherever Google
        // thinks the request originated, which in practice skewed heavily
        // American for ambiguous names ("that pub called The Crown" etc).
        // locationBias is soft — it still returns results outside the box,
        // just ranks matches inside it higher — so this doesn't hide a
        // genuine non-European place, it just stops Europe from losing
        // ties it should win. Rough bounding rectangle for mainland Europe
        // + UK/Ireland + Scandinavia.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "textQuery": q,
            "pageSize": 10,
            "locationBias": [
                "rectangle": [
                    "low": ["latitude": 34.0, "longitude": -12.0],
                    "high": ["latitude": 71.0, "longitude": 40.0],
                ]
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let results = json["places"] as? [[String: Any]] ?? []
        return results.compactMap { p in
            guard let id = p["id"] as? String else { return nil }
            let name = (p["displayName"] as? [String: Any])?["text"] as? String ?? "Untitled"
            let loc = p["location"] as? [String: Any]
            // Places photos come back as resource names; the media endpoint
            // serves the actual image and accepts the same iOS-restricted key.
            let photoName = (p["photos"] as? [[String: Any]])?.first?["name"] as? String
            let photoURL = photoName.map {
                "https://places.googleapis.com/v1/\($0)/media?maxWidthPx=800&key=\(googleKey)"
            }
            return RexSearchHit(
                externalId: id,
                externalSource: "google_places",
                title: name,
                subtitle: nil,
                imageURL: photoURL,
                genre: (p["primaryTypeDisplayName"] as? [String: Any])?["text"] as? String,
                address: p["formattedAddress"] as? String,
                lat: loc?["latitude"] as? Double,
                lng: loc?["longitude"] as? Double,
                googleRating: p["rating"] as? Double,
                googleRatingCount: p["userRatingCount"] as? Int
            )
        }
    }

    /// Oct 3 — "The Place page: please can we pull photos from Google? ... a
    /// summary of what it is ie smash burgers, tacos, coffee; opening times."
    ///
    /// All three live behind one Place Details call. The field mask below
    /// deliberately spans three billing tiers — photos (Essentials), the type
    /// name (Pro), opening hours and the editorial summary (Enterprise) — so
    /// this is the most expensive single request in the app, and the caller
    /// must only make it when `items.details_fetched_at` says we've never
    /// asked about this place before. Once per place, not once per view.
    static func placeDetails(placeId: String) async -> RexPlaceDetails? {
        guard !googleKey.isEmpty, !placeId.isEmpty else { return nil }
        guard let url = URL(string: "https://places.googleapis.com/v1/places/\(placeId)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(googleKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue(
            "photos,primaryTypeDisplayName,editorialSummary," +
            "regularOpeningHours.weekdayDescriptions,rating,userRatingCount,websiteUri",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Up to six: enough to swipe through, few enough that the page isn't
        // mostly stock photography of a menu.
        let photoURLs = ((json["photos"] as? [[String: Any]]) ?? [])
            .prefix(6)
            .compactMap { $0["name"] as? String }
            .map { "https://places.googleapis.com/v1/\($0)/media?maxWidthPx=1200&key=\(googleKey)" }

        // "smash burgers" if Google has written one, otherwise the primary
        // type ("Hamburger restaurant"), which is duller but always true.
        let editorial = (json["editorialSummary"] as? [String: Any])?["text"] as? String
        let typeName = (json["primaryTypeDisplayName"] as? [String: Any])?["text"] as? String
        let summary = [editorial, typeName]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }

        let hours = ((json["regularOpeningHours"] as? [String: Any])?["weekdayDescriptions"] as? [String]) ?? []

        return RexPlaceDetails(
            summary: summary,
            openingHours: hours,
            photoURLs: Array(photoURLs),
            rating: json["rating"] as? Double,
            ratingCount: json["userRatingCount"] as? Int,
            websiteURL: json["websiteUri"] as? String
        )
    }

    /// #167's long-press-to-add on the map used CLGeocoder's reverse
    /// geocode for "what's at this point", which only ever resolves to a
    /// street address — never the business occupying it, so tapping
    /// directly on a restaurant/cafe icon added "14 Market Street" instead
    /// of the restaurant. This asks Google Places (New) — the same
    /// catalogue search() above already uses — what's actually there
    /// instead: Nearby Search ranked by distance, with a tight ~40m radius
    /// so it picks up whatever's directly under the pin rather than
    /// something down the block. MapView falls back to the old address-only
    /// CLGeocoder path when this comes back empty (a genuinely
    /// venue-less spot — the middle of a park, a random field).
    static func nearby(lat: Double, lng: Double) async -> RexSearchHit? {
        guard !googleKey.isEmpty else { return nil }
        guard let url = URL(string: "https://places.googleapis.com/v1/places:searchNearby") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(googleKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue(
            "places.id,places.displayName,places.formattedAddress,places.location," +
            "places.primaryTypeDisplayName,places.photos,places.rating,places.userRatingCount",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "maxResultCount": 1,
            "rankPreference": "DISTANCE",
            "locationRestriction": [
                "circle": ["center": ["latitude": lat, "longitude": lng], "radius": 40.0]
            ],
        ])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = (json["places"] as? [[String: Any]])?.first,
              let id = p["id"] as? String
        else { return nil }
        let name = (p["displayName"] as? [String: Any])?["text"] as? String ?? "Untitled"
        let loc = p["location"] as? [String: Any]
        let photoName = (p["photos"] as? [[String: Any]])?.first?["name"] as? String
        let photoURL = photoName.map {
            "https://places.googleapis.com/v1/\($0)/media?maxWidthPx=800&key=\(googleKey)"
        }
        return RexSearchHit(
            externalId: id,
            externalSource: "google_places",
            title: name,
            subtitle: nil,
            imageURL: photoURL,
            genre: (p["primaryTypeDisplayName"] as? [String: Any])?["text"] as? String,
            address: p["formattedAddress"] as? String,
            lat: loc?["latitude"] as? Double,
            lng: loc?["longitude"] as? Double,
            googleRating: p["rating"] as? Double,
            googleRatingCount: p["userRatingCount"] as? Int
        )
    }

    /// #135 — a stop only ever got a map pin if it was picked from a live
    /// places() search result above; anything typed by hand, or brought in
    /// by the document importer (which never geocodes at all), had no
    /// lat/lng and so never rendered a pin. This is the fallback for both
    /// of those paths: turn a plain address or name into coordinates via
    /// the legacy Geocoding API, which — like places() above — accepts the
    /// same iOS-bundle-restricted key over REST rather than needing a
    /// separate unrestricted server key. Best-effort: a place that doesn't
    /// resolve (typo, too vague, key missing the Geocoding API product)
    /// just stays pinless the way it already did, rather than blocking
    /// whatever's creating the stop.
    /// #168 — this had no regional bias at all, unlike places() (#22, same
    /// underlying problem: an ambiguous name resolves to whichever match
    /// Google ranks first worldwide, which in practice skewed American for
    /// a British pub/hotel name like "The Crown"). `bounds` is the legacy
    /// Geocoding API's equivalent of places()'s locationBias — also soft,
    /// so a genuine non-European address still resolves correctly, this
    /// just stops Europe losing ties it should win. Same rough Europe +
    /// UK/Ireland + Scandinavia rectangle as places().
    /// Sept 8 — the address as Google resolved it, alongside the point.
    /// A trip stop imported from a document has no address at all (the
    /// importer only ever wrote coordinates), which is why the existing
    /// geocode self-heal could never repair one: it keys off the address
    /// field, and there was nothing there to key off. Writing the resolved
    /// address back fixes that for good, and gives the card a location
    /// line it never had.
    static func geocodeDetailed(_ query: String) async -> (lat: Double, lng: Double, address: String?)? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !googleKey.isEmpty else { return nil }
        guard let url = URL(string: "https://maps.googleapis.com/maps/api/geocode/json?address=\(esc(q))&bounds=34.0,-12.0|71.0,40.0&key=\(googleKey)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "OK",
              let results = json["results"] as? [[String: Any]], let first = results.first,
              let geometry = first["geometry"] as? [String: Any],
              let location = geometry["location"] as? [String: Any],
              let lat = location["lat"] as? Double, let lng = location["lng"] as? Double
        else { return nil }
        return (lat, lng, first["formatted_address"] as? String)
    }

    /// Sept 15 — where a *named* place is. "Quinn's" (a pub in Dingle)
    /// landed in Canada and "Sora Lella" (a restaurant in Rome) in Jenin:
    /// both were looked up with the Geocoding API, which is built for
    /// street addresses and does a poor job of business names — it matches
    /// fragments of the words to whatever town it can. Places Text Search is
    /// built for exactly this ("Quinn's, Dingle"), so it goes first; the
    /// Geocoding API stays as the fallback for anything Places can't find.
    ///
    /// When there's a real street address, use that instead — see
    /// `locate(name:address:context:)`.
    static func locatePlace(_ query: String) async -> (lat: Double, lng: Double, address: String?)? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        if let hit = (try? await places(q))?.first, let lat = hit.lat, let lng = hit.lng {
            return (lat, lng, hit.address)
        }
        return await geocodeDetailed(q)
    }

    /// Sept 28 — "Calma Lisbon is appearing in South Korea", and before that
    /// four Rome restaurants pinned in Lebanon. Both are the same fault: a
    /// name searched without enough context matches confidently somewhere
    /// else entirely, and nothing about a plausible wrong coordinate looks
    /// wrong afterwards. You can't tell a right pin from a wrong one once
    /// it's saved, which is why these keep having to be found by a human
    /// noticing their dinner is in the wrong hemisphere.
    ///
    /// So: when we know roughly where a place ought to be — the trip's city,
    /// usually — the answer has to land near it. Anything further than this
    /// is refused outright and the place keeps no coordinates at all. A
    /// missing pin is visibly missing; a wrong one is a lie the map tells
    /// confidently.
    private static let plausibleRadiusMeters: Double = 250_000

    /// City centres, looked up once each. Cheap, and it stops a trip with
    /// twenty stops geocoding "Lisbon" twenty times.
    private static var cityCentres: [String: (lat: Double, lng: Double)?] = [:]
    private static let cityLock = NSLock()

    private static func centre(of city: String) async -> (lat: Double, lng: Double)? {
        let key = city.lowercased()
        if let cached = cityLock.withLock({ cityCentres[key] }) { return cached }
        let found = await geocode(city)
        cityLock.withLock { cityCentres[key] = found }
        return found
    }

    private static func metres(_ a: (lat: Double, lng: Double), _ b: (lat: Double, lng: Double)) -> Double {
        let earth = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return earth * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    /// The one entry point for "where is this?". A saved street address is
    /// the most trustworthy thing we have, so it wins and goes to the
    /// address geocoder; otherwise it's the name (plus whatever context —
    /// city, trip name — is going) through Places, and then the sanity check
    /// above before we believe the answer.
    static func locate(name: String?, address: String?, context: [String?] = []) async -> (lat: Double, lng: Double, address: String?)? {
        if let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), address.count > 8,
           address.contains(where: \.isNumber) || address.contains(",") {
            // A real street address is specific enough to trust on its own.
            if let located = await geocodeDetailed(address) { return located }
        }
        let cleanContext = context.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let query = ([name].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } + cleanContext)
            .joined(separator: ", ")
        guard let found = await locatePlace(query) else { return nil }

        // Nothing to check it against — take it, as before.
        guard let expected = cleanContext.first, let centre = await centre(of: expected) else { return found }

        let away = metres((found.lat, found.lng), centre)
        guard away <= plausibleRadiusMeters else {
            // Refuse rather than save. See the note above: no pin beats a
            // pin in the wrong country.
            return nil
        }
        return found
    }

    static func geocode(_ query: String) async -> (lat: Double, lng: Double)? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !googleKey.isEmpty else { return nil }
        guard let url = URL(string: "https://maps.googleapis.com/maps/api/geocode/json?address=\(esc(q))&bounds=34.0,-12.0|71.0,40.0&key=\(googleKey)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["status"] as? String == "OK",
              let results = json["results"] as? [[String: Any]], let first = results.first,
              let geometry = first["geometry"] as? [String: Any],
              let location = geometry["location"] as? [String: Any],
              let lat = location["lat"] as? Double, let lng = location["lng"] as? Double
        else { return nil }
        return (lat, lng)
    }

    // MARK: - Item details (17 Sept)

    /// Sept 17 — "make the item pages for films, tv and books more
    /// interesting by importing a synopsis and also their ratings".
    ///
    /// Fetched when the page opens rather than stored: every film and TV
    /// Rex already carries its TMDB id and every book its Open Library key
    /// (see the search functions above), so there's nothing to migrate and
    /// nothing to go stale. URLSession's cache means a second visit is free.
    ///
    /// On ratings: Rotten Tomatoes has no public API — scores are licensed
    /// through Fandango — so it can't be read directly. TMDB's own audience
    /// score always shows; if an OMDb key is in Info.plist as OMDbApiKey,
    /// Rotten Tomatoes, IMDb and Metacritic come through that (OMDb
    /// republishes them, free up to 1,000 lookups a day). Books use Open
    /// Library's own ratings — Goodreads closed its API to new keys in 2020.
    struct ItemDetails {
        var synopsis: String?
        /// "TMDB", "Rotten Tomatoes", "IMDb", "Open Library"…
        var ratings: [(source: String, value: String, detail: String?)] = []
        /// "1h 58m · Drama, Romance" / "3 seasons" / "384 pages"
        var facts: String?
        var isEmpty: Bool { synopsis == nil && ratings.isEmpty && facts == nil }
    }

    static func details(type: RexCategory, externalId: String?, externalSource: String?,
                        title: String, subtitle: String?) async -> ItemDetails {
        switch type {
        case .movie, .tv:
            let kind = type == .movie ? "movie" : "tv"
            var id = (externalSource?.hasPrefix("tmdb") == true) ? externalId : nil
            if id == nil { id = await tmdbId(forTitle: title, kind: kind) }
            guard let id else { return ItemDetails() }
            return await tmdbDetails(id: id, kind: kind, title: title)
        case .book:
            return await bookDetails(externalId: externalId, title: title, author: subtitle)
        default:
            return ItemDetails()
        }
    }

    private static func tmdbId(forTitle title: String, kind: String) async -> String? {
        guard !tmdbKey.isEmpty,
              let json = try? await getJSON("https://api.themoviedb.org/3/search/\(kind)?api_key=\(tmdbKey)&query=\(esc(title))&include_adult=false"),
              let first = (json["results"] as? [[String: Any]])?.first,
              let id = first["id"] as? Int else { return nil }
        return String(id)
    }

    private static func tmdbDetails(id: String, kind: String, title: String) async -> ItemDetails {
        var out = ItemDetails()
        guard !tmdbKey.isEmpty,
              let json = try? await getJSON("https://api.themoviedb.org/3/\(kind)/\(id)?api_key=\(tmdbKey)") else { return out }

        if let overview = json["overview"] as? String, !overview.isEmpty { out.synopsis = overview }

        if let score = json["vote_average"] as? Double, score > 0 {
            let votes = json["vote_count"] as? Int ?? 0
            out.ratings.append((
                source: "TMDB",
                value: String(format: "%.1f/10", score),
                detail: votes > 0 ? "\(formattedCount(votes)) votes" : nil
            ))
        }

        var facts: [String] = []
        if let minutes = json["runtime"] as? Int, minutes > 0 {
            facts.append(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m")
        }
        if let seasons = json["number_of_seasons"] as? Int, seasons > 0 {
            facts.append("\(seasons) season\(seasons == 1 ? "" : "s")")
        }
        let genres = (json["genres"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        if !genres.isEmpty { facts.append(genres.prefix(3).joined(separator: ", ")) }
        if !facts.isEmpty { out.facts = facts.joined(separator: " \u{00B7} ") }

        // The imdb_id here is what lets OMDb find the same title.
        let imdbId = json["imdb_id"] as? String ?? json["external_ids"] as? String
        if let extra = await omdbRatings(imdbId: imdbId, title: title) {
            out.ratings.append(contentsOf: extra)
        }
        return out
    }

    /// Only if a key is configured — otherwise silently nothing, and the
    /// page just shows TMDB's score.
    private static func omdbRatings(imdbId: String?, title: String) async -> [(source: String, value: String, detail: String?)]? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OMDbApiKey") as? String, !key.isEmpty else { return nil }
        let query = imdbId.map { "i=\($0)" } ?? "t=\(esc(title))"
        guard let json = try? await getJSON("https://www.omdbapi.com/?apikey=\(key)&\(query)"),
              let ratings = json["Ratings"] as? [[String: String]] else { return nil }
        return ratings.compactMap { entry in
            guard let source = entry["Source"], let value = entry["Value"] else { return nil }
            switch source {
            case "Rotten Tomatoes": return ("Rotten Tomatoes", value, nil)
            case "Internet Movie Database": return ("IMDb", value.replacingOccurrences(of: "/10", with: "/10"), nil)
            case "Metacritic": return ("Metacritic", value.replacingOccurrences(of: "/100", with: ""), nil)
            default: return nil
            }
        }
    }

    private static func bookDetails(externalId: String?, title: String, author: String?) async -> ItemDetails {
        var out = ItemDetails()
        // Book search stores Open Library's work key ("works/OL123W").
        var workKey = externalId.flatMap { $0.hasPrefix("works/") ? $0 : nil }
        if workKey == nil {
            let query = [title, author?.components(separatedBy: " \u{00B7} ").first]
                .compactMap { $0 }.joined(separator: " ")
            if let json = try? await getJSON("https://openlibrary.org/search.json?q=\(esc(query))&limit=1&fields=key,number_of_pages_median"),
               let first = (json["docs"] as? [[String: Any]])?.first,
               let key = first["key"] as? String {
                workKey = key.hasPrefix("/") ? String(key.dropFirst()) : key
            }
        }

        if let workKey {
            if let json = try? await getJSON("https://openlibrary.org/\(workKey).json") {
                // description is either a plain string or { "value": "…" }.
                if let text = json["description"] as? String {
                    out.synopsis = text
                } else if let wrapped = json["description"] as? [String: Any], let text = wrapped["value"] as? String {
                    out.synopsis = text
                }
            }
            if let json = try? await getJSON("https://openlibrary.org/\(workKey)/ratings.json"),
               let summary = json["summary"] as? [String: Any],
               let average = summary["average"] as? Double, average > 0 {
                let count = (summary["count"] as? Int) ?? 0
                out.ratings.append((
                    source: "Open Library",
                    value: String(format: "%.1f/5", average),
                    detail: count > 0 ? "\(formattedCount(count)) ratings" : nil
                ))
            }
        }

        // Google Books fills in whichever of the two is still missing —
        // it has a description for most books, and a rating for some.
        if out.synopsis == nil || out.ratings.isEmpty {
            let query = [title, author?.components(separatedBy: " \u{00B7} ").first]
                .compactMap { $0 }.joined(separator: " ")
            if let json = try? await getJSON("https://www.googleapis.com/books/v1/volumes?q=\(esc(query))&maxResults=1"),
               let info = (json["items"] as? [[String: Any]])?.first?["volumeInfo"] as? [String: Any] {
                if out.synopsis == nil, let text = info["description"] as? String, !text.isEmpty {
                    out.synopsis = text
                }
                if out.ratings.isEmpty, let average = info["averageRating"] as? Double, average > 0 {
                    let count = info["ratingsCount"] as? Int ?? 0
                    out.ratings.append((
                        source: "Google Books",
                        value: String(format: "%.1f/5", average),
                        detail: count > 0 ? "\(formattedCount(count)) ratings" : nil
                    ))
                }
                if out.facts == nil, let pages = info["pageCount"] as? Int, pages > 0 {
                    out.facts = "\(pages) pages"
                }
            }
        }

        // Open Library descriptions often end with a source credit line.
        if let synopsis = out.synopsis {
            out.synopsis = synopsis
                .components(separatedBy: "----------")[0]
                .components(separatedBy: "([source]")[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    private static func formattedCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000).replacingOccurrences(of: ".0k", with: "k") : "\(n)"
    }

    // MARK: - Link previews (15 Sept)

    /// Sept 15 — "If you upload a product link can it auto populate the
    /// thumbnail with the product image" (Phoebe). Almost every shop page
    /// declares its own share image and title for WhatsApp/iMessage
    /// previews (og:image / og:title, or the twitter: equivalents); this
    /// reads those, the same way a messaging app builds a link preview.
    /// Best-effort — a site that blocks it, or has none, just leaves the
    /// thumbnail for you to add.
    static func linkPreview(for url: URL) async -> (title: String?, imageURL: String?) {
        var request = URLRequest(url: url, timeoutInterval: 8)
        // Some shops serve an empty shell to anything that doesn't look like
        // a browser; Safari's own agent gets the real page.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400 else { return (nil, nil) }
        // The meta tags live in <head>; no need to decode a whole product page.
        let head = String(decoding: data.prefix(600_000), as: UTF8.self)

        func meta(_ names: [String]) -> String? {
            for name in names {
                // Attribute order varies between sites, so both orders.
                let patterns = [
                    "<meta[^>]+(?:property|name)=[\"']\(name)[\"'][^>]*content=[\"']([^\"']+)[\"']",
                    "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"']\(name)[\"']",
                ]
                for pattern in patterns {
                    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                    let range = NSRange(head.startIndex..., in: head)
                    if let match = regex.firstMatch(in: head, range: range),
                       let r = Range(match.range(at: 1), in: head) {
                        let value = String(head[r])
                            .replacingOccurrences(of: "&amp;", with: "&")
                            .replacingOccurrences(of: "&quot;", with: "\"")
                            .replacingOccurrences(of: "&#39;", with: "'")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty { return value }
                    }
                }
            }
            return nil
        }

        var image = meta(["og:image:secure_url", "og:image", "twitter:image", "twitter:image:src"])
        // A relative image path ("/images/bag.jpg") means relative to the page.
        if let raw = image, !raw.hasPrefix("http"), let resolved = URL(string: raw, relativeTo: url) {
            image = resolved.absoluteString
        }
        if image?.hasPrefix("http://") == true { image = image?.replacingOccurrences(of: "http://", with: "https://") }
        let title = meta(["og:title", "twitter:title"])
        return (title, image)
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
