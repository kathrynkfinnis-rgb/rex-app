import Foundation

/// Oct 17 — a hard ceiling on what one device can spend at Google in a day.
///
/// Written the morning after a £111 overnight spike. The money is only half
/// the lesson: the app had no limit of any kind on how many paid calls it
/// could make, so a loop over the whole catalogue — which is what the map's
/// coordinate self-heal is — could run up a bill with nothing in the way.
/// Ask Rex has had a per-person daily ceiling since September and the other
/// AI functions got one yesterday; Google never had one at all.
///
/// Deliberately a *device* ceiling in UserDefaults rather than a per-account
/// one in the database. A runaway guard has to work when the thing running
/// away is the app itself, before any network call, and it has to cost
/// nothing to check. It is not a security control — somebody determined
/// could clear it — it is a brake on our own code.
///
/// The numbers are far above normal use and far below a surprise: a heavy day
/// of adding places is twenty or thirty searches.
enum GoogleBudget {
    enum Kind: String {
        case places     // Text Search, Nearby, Place Details, Place Photos
        case geocoding
    }

    private static let ceiling: [Kind: Int] = [.places: 250, .geocoding: 250]
    private static let lock = NSLock()

    private static func key(_ kind: Kind) -> String {
        let day = DateFormatter.rexBudgetDay.string(from: Date())
        return "rex.googleBudget.\(kind.rawValue).\(day)"
    }

    /// Counts one call and says whether it may go ahead. Call it immediately
    /// before the request, never after: a call we refuse must not be counted
    /// against tomorrow, and a call we make must be counted even if it fails.
    static func allow(_ kind: Kind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let name = key(kind)
        let used = UserDefaults.standard.integer(forKey: name)
        guard used < (ceiling[kind] ?? 250) else {
            // Once per day per kind is enough to notice in a log.
            if used == ceiling[kind] { print("[GoogleBudget] \(kind.rawValue) ceiling reached for today.") }
            UserDefaults.standard.set(used + 1, forKey: name)
            // Our own ceiling and Google's quota look the same to the person
            // searching, so they get the same message.
            GoogleAvailability.noteRefusal()
            return false
        }
        UserDefaults.standard.set(used + 1, forKey: name)
        return true
    }

    /// What today has cost so far, for the admin screen.
    static func used(_ kind: Kind) -> Int {
        UserDefaults.standard.integer(forKey: key(kind))
    }
}

/// Oct 17 — so an empty search can explain itself.
///
/// A quota refusal and "there is genuinely nothing called that" looked
/// identical: the search swallowed the error and returned an empty list
/// either way. Nobody would report that as a bug — they would just decide REX
/// is bad at finding places, which is the worst possible outcome for the one
/// control we have that protects the bill.
///
/// Deliberately a recent-past flag rather than a thrown error. Changing what
/// search returns would mean touching ten call sites for a message only two
/// of them want to show, and the sheets already redraw when results arrive,
/// so reading this straight afterwards is enough. It clears itself, because a
/// stale "unavailable" is worse than none.
enum GoogleAvailability {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var refusedAt: Date?

    /// True if Google turned us away in the last few minutes.
    static var isRefusingUs: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let refusedAt else { return false }
        return Date().timeIntervalSince(refusedAt) < 180
    }

    static func noteRefusal() {
        lock.lock(); defer { lock.unlock() }
        refusedAt = Date()
    }

    /// Any call that comes back normally clears it — whatever was wrong isn't
    /// any more, and the message should go with it.
    static func noteSuccess() {
        lock.lock(); defer { lock.unlock() }
        refusedAt = nil
    }
}

private extension DateFormatter {
    static let rexBudgetDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

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
    /// Oct 5 — the place's own website, from Google. Only used to work out
    /// which chain it belongs to; see chainKey.
    let websiteURL: String?

    var id: String { "\(externalSource):\(externalId)" }

    init(
        externalId: String, externalSource: String, title: String,
        subtitle: String? = nil, imageURL: String? = nil, genre: String? = nil,
        address: String? = nil, lat: Double? = nil, lng: Double? = nil,
        googleRating: Double? = nil, googleRatingCount: Int? = nil,
        productURL: String? = nil, websiteURL: String? = nil
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
        self.websiteURL = websiteURL
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
    /// Oct 17 — a debug build cannot spend production money.
    ///
    /// Every guard added today is a brake on our own code, and brakes can be
    /// got around by the next piece of code somebody writes. This is the only
    /// change that makes last night structurally impossible rather than
    /// merely unlikely: a build running from Xcode uses a different key, with
    /// its own project and its own quota, so the worst a runaway can do while
    /// being developed is exhaust a budget nobody is relying on.
    ///
    /// When no development key is configured it returns nothing at all rather
    /// than falling back to the production one. Searching then quietly finds
    /// no places in debug builds, which looks like a bug and is meant to —
    /// a loud, free failure beats a silent, billable success.
    private static var googleKey: String {
        #if DEBUG
        let dev = Bundle.main.object(forInfoDictionaryKey: "GMSApiKeyDebug") as? String ?? ""
        return dev.hasPrefix("AIza") ? dev : ""
        #else
        return Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
        #endif
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

    /// Oct 14 — "coming up with silly irrelevant suggestions." She was adding
    /// a bar to a Cartagena trip and being offered a one-bedroom apartment in
    /// Germany, because the search had no idea where the trip was: every place
    /// lookup went out against the whole world with a Europe lean, whatever
    /// you happened to be building.
    ///
    /// `near` is where the thing being built already is — the first stop with
    /// coordinates on the trip you are adding to. It makes a search for "the
    /// bar by the square" mean the square you were just at.
    static func search(
        category: RexCategory,
        query: String,
        near: (lat: Double, lng: Double)? = nil
    ) async -> [RexSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        // Oct 21 — "can we make it more easy to just copy and paste the link
        // into the search bar or something and then prepopulate the card",
        // and: "shouldn't just be for amazon."
        //
        // Pasting the page is the one way of identifying a thing that does
        // not depend on anybody's catalogue — which matters now that Custom
        // Search is shutting down on 1 January 2027 and takes the only
        // general-goods source with it. A balance bike has no API anywhere;
        // its John Lewis page has a name, a photograph and a price on it, and
        // the person adding it is already looking at that page.
        //
        // Ahead of every catalogue rather than alongside them. Somebody who
        // pasted a URL has told us exactly what they mean, and searching the
        // web for the text of a URL finds nothing anyway.
        if let url = pastedURL(q) {
            return await linkHit(url, category: category)
        }
        do {
            switch category {
            case .book:            return try await books(q)
            case .movie:           return try await tmdb(q, kind: "movie")
            case .tv:              return try await tmdb(q, kind: "tv")
            case .podcast:         return try await podcasts(q)
            case .place, .event:   return try await placesPreferringCatalogue(q, category: category, near: near)
            case .other:           return try await productLookup(q)
            default:               return []
            }
        } catch {
            return []
        }
    }

    /// A pasted web address, or nil. Deliberately strict: a bare "amazon.co.uk"
    /// typed as a search term is a search, not a link, so a scheme is
    /// required. Anything that is a URL but not a web page — a mailto, a
    /// deep link into another app — is not something we can read a product
    /// out of.
    private static func pastedURL(_ q: String) -> URL? {
        guard q.contains("://"), let url = URL(string: q),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".")
        else { return nil }
        return url
    }

    /// One result, built from the page itself. The link is kept as the
    /// product URL so the card has somewhere to send people — the shop they
    /// came from, which for an Amazon link means our tag gets added on the
    /// way out, and for John Lewis means John Lewis.
    private static func linkHit(_ url: URL, category: RexCategory) async -> [RexSearchHit] {
        let preview = await linkPreview(for: url)
        // A page we cannot read a name out of gives us nothing to show. Say
        // nothing rather than offer a row titled after a URL.
        guard let title = preview.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return [] }
        return [RexSearchHit(
            externalId: url.absoluteString,
            externalSource: "link",
            title: title,
            subtitle: preview.siteName,
            imageURL: preview.imageURL,
            productURL: url.absoluteString
        )]
    }

    /// Oct 16 — ask ourselves before we ask Google.
    ///
    /// REX holds about three thousand places. Until now, typing the name of
    /// one of them still went to Google: the local lookup running alongside
    /// was only ever read for the "Already Rex'd" badge, never used as an
    /// answer. So the Google bill rose in a straight line with the number of
    /// people using the app, and the catalogue we were building paid for
    /// nothing.
    ///
    /// The rule for stopping at our own catalogue is deliberately strict,
    /// because the cost of being wrong is a worse search and that is the one
    /// thing we are not willing to trade. Typing "pizza" must still reach
    /// Google even though we hold a Pizza Pilgrims, because you are browsing.
    /// Typing "Lore of the Land" need not, because you have named a specific
    /// place and we already have it. The discriminator is how much of the
    /// title your query fills: nearly all of it means you knew what you were
    /// looking for.
    ///
    /// Everything else merges, ours first — somewhere three friends have been
    /// belongs above a listing.
    private static func placesPreferringCatalogue(
        _ q: String, category: RexCategory, near: (lat: Double, lng: Double)?
    ) async throws -> [RexSearchHit] {
        let ours = await RexAPI.shared.searchCatalogueItems(query: q, type: category.rawValue)
        if catalogueAnswersIt(q, ours) { return ours }

        let theirs = try await places(q, near: near)
        var seen = Set(ours.map(\.id))
        return ours + theirs.filter { seen.insert($0.id).inserted }
    }

    /// Whether what somebody typed names a place we already hold, rather than
    /// describing a kind of place they want to browse.
    static func catalogueAnswersIt(_ query: String, _ hits: [RexSearchHit]) -> Bool {
        func bare(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let typed = bare(query)
        guard typed.count >= 3 else { return false }
        return hits.contains { hit in
            let title = bare(hit.title)
            guard !title.isEmpty, title.contains(typed) else { return false }
            // Seven tenths: "loreoftheland" fills its own title entirely,
            // "pizza" fills a third of "pizzapilgrims".
            return Double(typed.count) / Double(title.count) >= 0.7
        }
    }

    /// #73/#103 — books/movies/TV/podcasts/places each have their own real
    /// catalogue; "Other"/Stuff never had one, so it never got a photo or a
    /// product link beyond whatever the user typed in by hand. Google
    /// Programmable Search stands in as a generic "look this up on the web"
    /// catalogue for everything else — same search-then-pick flow as any
    /// other category, just backed by web results instead of a dedicated API.
    /// Oct 14 — "I am trying to upload a list of board games — none of the
    /// items are coming up in the search."
    ///
    /// Because Programmable Search has answered every request with 403 "this
    /// project does not have the access to Custom Search JSON API" since the
    /// 11th, and Other is the only category with nothing else behind it. So
    /// Other had no catalogue at all, and a board game, a gadget, a brand —
    /// anything that isn't a book, film, show, podcast or place — returned
    /// nothing and looked broken.
    ///
    /// Wikipedia is the catalogue now: free, no key, no Google project, no
    /// billing to enable, and it knows what Wingspan and Azul and Catan are.
    /// Its page images are sparse, because box art is usually non-free, so
    /// most results arrive without a picture — a name and a line of
    /// description is still the difference between adding the thing and not.
    ///
    /// Programmable Search stays as the preferred source if it is ever given
    /// access, because a product link beats an encyclopaedia entry for the
    /// shopping half of Other. Its failure is remembered so the 403 is paid
    /// once a session rather than on every keystroke.
    private static var customSearchIsDead = false

    /// Oct 20 — "I think we need to improve the product search and buy", and
    /// then: "need a better API to identify products."
    ///
    /// Three sources, in order of how much like a product the answer is.
    ///
    /// Programmable Search first, because a page on a shop we chose is the
    /// best answer there is — but it is locked to nine sites, so anything
    /// outside them comes back empty and used to fall straight to an
    /// encyclopaedia. "Olive oil" returning the Wikipedia article on olive
    /// oil is a reasonable thing for a search engine to do and a useless
    /// thing for somebody trying to add a bottle they liked.
    ///
    /// Open Food Facts fills that gap for food and drink, which is most of
    /// what Other is used for here — the lists we have are olive oils, wine,
    /// dressings. It is free, needs no key, has no billing to enable and no
    /// quota to blow, which three days after a £111 Google bill is not a
    /// small part of why it was picked. Its products are real ones: a name, a
    /// brand, a photograph of the actual bottle.
    ///
    /// Wikipedia stays last. It knows what Wingspan and Azul are, which no
    /// shop and no food database does.
    ///
    /// The two are fetched together rather than in sequence. Food queries are
    /// not reliably distinguishable from the rest — "Barr's Irn Bru" and
    /// "Barr Hill Gin" give nothing away — so asking both and merging beats
    /// guessing which to ask.
    private static func productLookup(_ q: String) async throws -> [RexSearchHit] {
        // Oct 20 — "the product search now over defaults to food items. I just
        // tried to search balance bike... that is not coming up."
        //
        // Two mistakes in how this was wired, both mine from an hour ago.
        //
        // The first was merging the two sources instead of falling back. Open
        // Food Facts was appended to whatever Programmable Search returned, so
        // a query it had no business answering still filled the list with
        // groceries — and when the shops came back empty, groceries were the
        // whole list. Programmable Search is nine retailers we chose: if it
        // answers, that answer is better than anything a food database has, so
        // it is asked first and alone.
        //
        // Both are still started together, because the common case is that
        // the first one is empty and waiting for it before beginning the
        // second would double the wait on exactly the searches that already
        // feel slow.
        async let webResults = (try? await customSearch(q)) ?? []
        async let groceryResults = openFoodFacts(q)
        let web = await webResults
        if !web.isEmpty { return web }
        let grocery = await groceryResults
        if !grocery.isEmpty { return grocery }
        return await wikipedia(q)
    }

    /// Open Food Facts: an open database of groceries, contributed the way
    /// Wikipedia is. No key, no account, no billing to enable.
    ///
    /// Checked against the live API rather than written from the docs, which
    /// is how two things turned up. The endpoint everyone links to —
    /// cgi/search.pl — answers 503 with an HTML holding page; they have been
    /// moving off it and it is not something to depend on. And the country
    /// filter is only honoured inside the query string in its quoted form,
    /// `countries_tags:"en:united-kingdom"`; passed as its own parameter it is
    /// accepted and silently ignored, which took the result count from 10,000
    /// to 2,855 once it was actually applied. Unfiltered, a search for olive
    /// oil returns Californian and French bottles to a London phone.
    ///
    /// Filtered harder than the other sources, because it is crowd-contributed
    /// and the long tail is rough: entries with no name, no brand or no
    /// photograph, and several copies of one product under different barcodes.
    /// A result worth offering has all three. The barcode is the external id,
    /// so two people adding the same bottle land on one item.
    private static func openFoodFacts(_ q: String) async -> [RexSearchHit] {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }
        // Sold here first. If that finds nothing, ask again without the
        // filter — a jar somebody brought back from Italy is still the thing
        // they want to Rex.
        let local = await openFoodFactsHits(trimmed, country: localCountryTag)
        return local.isEmpty ? await openFoodFactsHits(trimmed, country: nil) : local
    }

    /// Whether every meaningful word of the query appears in the text. Words
    /// of one or two letters are ignored — "of", "a", "no" carry no weight and
    /// requiring them would reject good matches.
    private static func matchesEveryWord(of query: String, in text: String) -> Bool {
        let haystack = text.lowercased()
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        guard !words.isEmpty else { return true }
        return words.allSatisfy { haystack.contains($0) }
    }

    /// The phone's own country as Open Food Facts spells it.
    private static var localCountryTag: String? {
        switch (Locale.current.region?.identifier ?? "GB").uppercased() {
        case "GB": return "en:united-kingdom"
        case "IE": return "en:ireland"
        case "US": return "en:united-states"
        case "FR": return "en:france"
        case "DE": return "en:germany"
        case "ES": return "en:spain"
        case "IT": return "en:italy"
        default: return nil
        }
    }

    private static func openFoodFactsHits(_ terms: String, country: String?) async -> [RexSearchHit] {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        let query = country.map { "\(terms) countries_tags:\"\($0)\"" } ?? terms
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: "12"),
            // Without this their reply carries every nutrient and ingredient
            // for every hit — tens of kilobytes per keystroke.
            URLQueryItem(name: "fields", value: "code,product_name,brands,image_front_small_url"),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        // They ask that apps identify themselves, and are within their rights
        // to block anything that doesn't.
        request.setValue("REX/1.0 (iOS; hello@find-rex.com)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              // "hits", not "products" — that is the old endpoint's shape.
              let hits = json["hits"] as? [[String: Any]]
        else { return [] }

        var seen = Set<String>()
        var out: [RexSearchHit] = []
        for hit in hits {
            guard let code = hit["code"] as? String, !code.isEmpty,
                  let name = (hit["product_name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  // brands is an array here, not the comma-joined string the
                  // old endpoint returned.
                  let brand = (hit["brands"] as? [String])?.first?
                    .trimmingCharacters(in: .whitespaces), !brand.isEmpty,
                  let image = hit["image_front_small_url"] as? String, !image.isEmpty
            else { continue }
            // The second mistake: no relevance check at all. Their search is
            // an OR across tokens, so "balance bike" matched Butter Bike
            // peanut butter and a protein brand called Balance — 49 results,
            // not one of them a bike. Every word of three letters or more has
            // to appear somewhere in the name or the brand, which keeps
            // "olive oil" matching Tesco Extra Virgin Olive Oil and stops a
            // single shared word dragging in a shelf of groceries.
            guard matchesEveryWord(of: terms, in: "\(name) \(brand)") else { continue }
            let key = "\(name.lowercased())|\(brand.lowercased())"
            guard seen.insert(key).inserted else { continue }
            out.append(RexSearchHit(
                externalId: code,
                externalSource: "open_food_facts",
                title: name,
                subtitle: brand,
                imageURL: image
                // No productURL on purpose. Their page is a nutrition record,
                // not a shop, and putting it behind "View product" would make
                // the same wrong promise the Wikipedia fallback was making.
                // Buying is the Amazon pill's job.
            ))
            if out.count == 6 { break }
        }
        return out
    }

    /// Everything Wikipedia knows, which for Other is most of what anybody
    /// would want to add. Titles and descriptions always; a thumbnail when the
    /// page happens to have a freely-licensed one.
    private static func wikipedia(_ q: String) async -> [RexSearchHit] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: q),
            URLQueryItem(name: "gsrlimit", value: "6"),
            URLQueryItem(name: "prop", value: "pageimages|extracts"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exlimit", value: "max"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            // Oct 14 — "I would really like the thumbnails etc to make it more
            // interesting." pageimages defaults to freely-licensed pictures
            // only, and a board game's box art almost never is — which is why
            // the first cut came back with names and no pictures at all.
            // `any` includes the fair-use image the article itself displays:
            // Wingspan, Azul, Catan, Carcassonne all have their box now, where
            // before none of them did. We show it exactly where Wikipedia
            // shows it, at the size it serves.
            URLQueryItem(name: "pilicense", value: "any"),
            // Without this only the first page gets an image, which is a
            // silent way to lose five of six thumbnails.
            URLQueryItem(name: "pilimit", value: "max"),
            URLQueryItem(name: "pithumbsize", value: "400"),
        ]
        var request = URLRequest(url: components.url!)
        // Wikipedia asks that clients identify themselves and rate-limits
        // those that don't.
        request.setValue("REX/1.0 (https://find-rex.com)", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let pages = query["pages"] as? [String: [String: Any]]
        else { return [] }

        // `index` is Wikipedia's own relevance order; a dictionary has none.
        return pages.values
            .sorted { ($0["index"] as? Int ?? 99) < ($1["index"] as? Int ?? 99) }
            .compactMap { page -> RexSearchHit? in
                guard let title = page["title"] as? String,
                      let pageId = page["pageid"] as? Int else { return nil }
                // Disambiguation pages are a menu, not a thing you can Rex.
                let extract = (page["extract"] as? String) ?? ""
                guard !extract.contains("may refer to:") else { return nil }
                let firstSentence = extract
                    .split(separator: "\n").first
                    .map(String.init)?
                    .prefix(180)
                let slug = title.replacingOccurrences(of: " ", with: "_")
                    .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
                return RexSearchHit(
                    externalId: "wikipedia-\(pageId)",
                    externalSource: "wikipedia",
                    title: title,
                    subtitle: firstSentence.map(String.init),
                    imageURL: ((page["thumbnail"] as? [String: Any])?["source"] as? String),
                    productURL: "https://en.wikipedia.org/wiki/\(slug)"
                )
            }
    }

    private static func customSearch(_ q: String) async throws -> [RexSearchHit] {
        guard !customSearchIsDead, !cseApiKey.isEmpty, !cseEngineId.isEmpty else { return [] }
        var components = URLComponents(string: "https://www.googleapis.com/customsearch/v1")!
        components.queryItems = [
            URLQueryItem(name: "key", value: cseApiKey),
            URLQueryItem(name: "cx", value: cseEngineId),
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "num", value: "5"),
        ]
        // Same bundle header as articles() — see the note there.
        var request = URLRequest(url: components.url!)
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            // 403 here means the Google project has no access to the API, which
            // no amount of retrying fixes. Stop asking for this session.
            if (response as? HTTPURLResponse)?.statusCode == 403 { customSearchIsDead = true }
            return []
        }
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

    /// Oct 3 — "when someone Rexes something which has multiple branches eg
    /// Bancone or relais d'entrecôte or mr bao (but less than 20 instances),
    /// give the option to automatically Rex the others."
    ///
    /// Other locations trading under the same name. The name has to match
    /// almost exactly, because the failure here is embarrassing in a specific
    /// way: offering to Rex "The Crown" in Doncaster because somebody liked a
    /// different pub called The Crown in Bristol. A chain is a shared brand,
    /// not a shared word, so a loose match is worse than no feature.
    ///
    /// The twenty cap is hers and it's the right instinct — Pret has hundreds
    /// of branches and nobody means to recommend all of them.
    /// Oct 12 — "the 'find other members of the chain' function is not working
    /// for places that have a common business name. This is Catalyst."
    ///
    /// The name matching was doing its job: those businesses really are all
    /// called Catalyst. An office suite in Wickwar, a trading estate in High
    /// Wycombe and a climbing centre share a word and nothing else, and a
    /// shared word was the only thing being asked for.
    ///
    /// So `like` is the kind of place the original is, and a candidate has to
    /// be the same kind of thing before its name is even considered. It comes
    /// from the same Google field on both sides, so the two are directly
    /// comparable. A chain whose branches are typed slightly differently —
    /// "Italian restaurant" beside "Restaurant" — still matches, because what
    /// is compared is the noun at the end rather than the whole phrase.
    ///
    /// Kathryn also asked about reading the chain's own website for its branch
    /// list. Not doing that: it means fetching and parsing a different page
    /// shape per chain, and a store-finder is usually a script rather than a
    /// list, so it would work for some brands and quietly fail for the rest.
    /// A wrong branch list that looks authoritative is worse than this.
    // Oct 14 — branches(of:like:excludingPlaceId:) lived here: the older
    // finder that matched on the name and the kind of place. It is gone, with
    // isSameKindOfPlace, isSameChain and normalizeForChainMatch, because it
    // could not be made right. A name cannot tell a chain from a coincidence,
    // and its type guard let everything through whenever the origin's type was
    // unknown — which is how a Brooklyn restaurant came to offer three London
    // churches. chainBranches below, keyed on the brand's own domain, is the
    // only test in this file that holds up.

    // MARK: - Chains

    /// Oct 5 — what makes two places branches of one thing.
    ///
    /// The brand's own web domain, never the name. A name cannot distinguish
    /// Bancone Covent Garden and Bancone City from the Crown in Blackheath and
    /// the Crown in Doncaster, and no amount of cleverness will make it: one
    /// pair is a business with five sites, the other is thirty pubs with
    /// thirty landlords. A domain can tell them apart, because the business
    /// has one website.
    ///
    /// Checked against what Google returns today: Bancone's five branches all
    /// give bancone.co.uk, while eight results for "The Crown" give seven
    /// different domains.
    ///
    /// The second guard is here: the domain has to look like this place's own
    /// brand. Several Crowns point at greeneking.co.uk or vintageinn.co.uk —
    /// a pub group's site, not a chain's — and without this they would bind
    /// into one. "bancone.co.uk" belongs to Bancone; "greeneking.co.uk" does
    /// not belong to the Crown.
    static func chainKey(name: String, websiteURL: String?) -> String? {
        guard let websiteURL, let host = URL(string: websiteURL)?.host?.lowercased() else { return nil }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard looksLikeOwnBrand(name: name, domain: domain) else { return nil }
        return domain
    }

    private static func looksLikeOwnBrand(name: String, domain: String) -> Bool {
        // The name up to its first separator is the brand; what follows is
        // usually the branch ("Mr Bao - Taiwanese Restaurant Peckham").
        let brand = lettersOnly(name.split(whereSeparator: { "-–—,|·".contains($0) }).first.map(String.init) ?? name)
        let label = lettersOnly(domain.split(separator: ".").first.map(String.init) ?? domain)
        guard brand.count >= 4, label.count >= 4 else { return false }
        return brand.hasPrefix(label) || label.hasPrefix(brand) || brand.contains(label)
    }

    private static func lettersOnly(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    /// The other branches of whatever this place belongs to.
    ///
    /// Returns nothing unless at least two places share the brand's domain —
    /// a single pub with its own website is not a chain of one — and nothing
    /// for anything with twenty or more, which is a big chain nobody means to
    /// recommend wholesale.
    static func chainBranches(name: String, key: String, excludingPlaceId: String?) async -> [RexSearchHit] {
        guard !googleKey.isEmpty else { return [] }
        // Oct 17 — the ceiling, checked before the request goes out.
        guard GoogleBudget.allow(.places) else { return [] }
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(googleKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue(
            "places.id,places.displayName,places.formattedAddress,places.location," +
            "places.primaryTypeDisplayName,places.photos,places.rating,places.userRatingCount," +
            "places.websiteUri",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "textQuery": name.trimmingCharacters(in: .whitespaces),
            "pageSize": 20,
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["places"] as? [[String: Any]]
        else { return [] }

        var seenAddresses = Set<String>()
        var branches: [RexSearchHit] = []
        var matchesIncludingThisOne = 0

        for place in results {
            guard let placeName = (place["displayName"] as? [String: Any])?["text"] as? String,
                  chainKey(name: placeName, websiteURL: place["websiteUri"] as? String) == key
            else { continue }
            matchesIncludingThisOne += 1

            guard let id = place["id"] as? String, id != excludingPlaceId,
                  let address = place["formattedAddress"] as? String,
                  seenAddresses.insert(address).inserted
            else { continue }
            let location = place["location"] as? [String: Any]
            let photoName = (place["photos"] as? [[String: Any]])?.first?["name"] as? String
            branches.append(RexSearchHit(
                externalId: id,
                externalSource: "google_places",
                title: placeName,
                subtitle: nil,
                imageURL: photoName.map { "https://places.googleapis.com/v1/\($0)/media?maxWidthPx=800&key=\(googleKey)" },
                genre: (place["primaryTypeDisplayName"] as? [String: Any])?["text"] as? String,
                address: address,
                lat: location?["latitude"] as? Double,
                lng: location?["longitude"] as? Double,
                googleRating: place["rating"] as? Double,
                googleRatingCount: place["userRatingCount"] as? Int
            ))
        }

        // One place sharing its own domain is not a chain; twenty is one
        // nobody means to recommend wholesale.
        guard matchesIncludingThisOne >= 2, matchesIncludingThisOne < 20 else { return [] }
        return branches
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
        guard let url = components.url else { return [] }
        // The bundle id goes on every Programmable Search request for the same
        // reason it goes on a Places one: it lets the key be restricted to this
        // app rather than usable by anyone who extracts it from the binary.
        // Google ignores the header on an unrestricted key, so sending it
        // always is free.
        var request = URLRequest(url: url)
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
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

    /// Oct 7 — "this book isn't coming up despite it being a NY Times best
    /// seller."
    ///
    /// The search was the full title as printed on the cover: "The Cauldron:
    /// the making of the modern Middle East". OpenLibrary files it as "The
    /// Cauldron" and nothing else, so every pass below looked for a subtitle
    /// that is not in the record and found nothing — while "the cauldron
    /// montefiore" finds it first time. A title and its subtitle are divided
    /// by a colon by convention, so the half in front of one is worth asking
    /// for on its own.
    private static func mainTitle(_ q: String) -> String? {
        guard let colon = q.firstIndex(of: ":") else { return nil }
        let head = String(q[..<colon]).trimmingCharacters(in: .whitespaces)
        // Two characters isn't a title, it's a false start.
        guard head.count >= 3, head != q else { return nil }
        return head
    }

    private static func books(_ q: String) async throws -> [RexSearchHit] {
        let words = q.split(separator: " ").count
        // OpenLibrary files plenty of books without their leading article —
        // Paul Murray's novel is "Bee Sting", not "The Bee Sting" — so a
        // title search for exactly what someone typed misses it entirely.
        let unarticled = dropLeadingArticle(q)
        // Oct 12 — "Trespasses by Louise Kennedy: had to type the whole name
        // and the author to get there."
        //
        // Because wildcardLastWord turned it into "trespasses*", and
        // OpenLibrary returns nothing at all for that — while plain
        // "trespasses" returns 869. The wildcard is there so a half-typed word
        // still matches, and it does for some words ("piranes*" finds
        // Piranesi) but not others: appending it bypasses the index's
        // stemming, so a complete word that stems to something else matches
        // nothing. Which means the wildcard helped while you typed and then
        // deleted every result the moment you finished.
        //
        // Both forms now, merged. The wildcard keeps its job mid-word and the
        // plain query covers the word being finished, which is the state the
        // search is in when somebody actually stops to read the results.
        async let titleHits = openLibrary("title=\(esc(wildcardLastWord(q)))")
        async let plainTitleHits: [RexSearchHit] = wildcardLastWord(q) == q
            ? [] : openLibrary("title=\(esc(q))")
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

        // The title without its subtitle — see mainTitle. Appended last so it
        // only ever adds candidates; the ranking below still decides, and an
        // exact match on what was actually typed keeps beating this.
        let head = mainTitle(q) ?? ""
        async let headHits: [RexSearchHit] = head.isEmpty
            ? [] : openLibrary("title=\(esc(head))")
        async let headGoogleHits: [RexSearchHit] = head.isEmpty
            ? [] : googleBooks(head)

        let all = (try await titleHits) + (try await plainTitleHits) + (try await bareTitleHits)
            + (try await authorHits) + (try await generalHits)
            + (await googleHits)
            + (try await headHits) + (await headGoogleHits)

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
    /// OpenLibrary hasn't catalogued. A failure returns nothing rather than
    /// throwing, because it's a supplement and book search must not start
    /// failing if Google rate-limits us.
    ///
    /// Oct 7 — it was rate-limiting us, and had been for a while: every
    /// request was coming back 429, "Quota exceeded for Queries per day". The
    /// call carried no key, so it was drawing on the anonymous per-IP pool
    /// rather than the project's own quota — which meant this second source
    /// had quietly stopped being a second source at all, and book search was
    /// running on OpenLibrary alone. The same key the Places calls use; it is
    /// iOS-bundle-restricted, hence the header.
    private static func googleBooks(_ q: String) async -> [RexSearchHit] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        components?.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "printType", value: "books"),
        ]
        if !googleKey.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "key", value: googleKey))
        }
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue(
            Bundle.main.bundleIdentifier ?? "",
            forHTTPHeaderField: "X-Ios-Bundle-Identifier"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
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
                // Oct 5 — "on the books filter, now only Fiction appears —
                // can we go one level below (thriller, biography etc)."
                //
                // This used to take the first subject under 22 characters,
                // which is how "mujeres en china" became a book's genre:
                // OpenLibrary's subjects are an unordered pile of library
                // headings, and the first short one is arbitrary. Handing the
                // whole pile over instead lets rexNormalisedGenres find the
                // ones that are actually genres — a book filed under
                // "Fiction, thrillers, suspense, English fiction" comes back
                // as Fiction and Thriller rather than whichever heading
                // happened to be shortest.
                genre: subjects.prefix(30).joined(separator: ", ")
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
    private static func places(_ q: String, near: (lat: Double, lng: Double)? = nil) async throws -> [RexSearchHit] {
        guard !googleKey.isEmpty else {
            // No key is "search is unavailable" too, and saying so is the
            // difference between a debug build that looks broken and one that
            // tells you the dev key isn't set yet.
            GoogleAvailability.noteRefusal()
            return []
        }
        // Oct 17 — the ceiling, checked before the request goes out.
        guard GoogleBudget.allow(.places) else { return [] }
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(googleKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        // Oct 16 — 4,651 of these in a month, £91.54, two thirds of the bill.
        //
        // Google prices a place search by the most expensive field in the
        // mask. rating, userRatingCount and websiteUri are Enterprise
        // fields; everything else here is Pro. Asking for those three moved
        // every search REX makes onto a tier with a thousand free calls a
        // month instead of five thousand, and £25 per thousand after that.
        //
        // Nothing on screen used them. No search row draws a rating — the
        // badge on a place page comes from Place Details, which fetches it
        // separately and saves it, once per place per ninety days. The
        // website is only ever read by chain detection, which runs its own
        // search and keeps the field there.
        //
        // So: same query, same ranking, same places, same order. Only the
        // tier changes, and at this volume the whole line goes free.
        request.setValue(
            "places.id,places.displayName,places.formattedAddress,places.location," +
            "places.primaryTypeDisplayName,places.photos",
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
        // Oct 14 — where you already are beats a continent you might not be
        // on. A trip's own coordinates make a 60km box around it; with nothing
        // to go on it falls back to the Europe rectangle, which is a guess
        // about this app's users rather than about this search.
        let bias: [String: Any]
        if let near {
            let degrees = 0.55   // roughly 60km of latitude
            let lngDegrees = degrees / max(0.2, cos(near.lat * .pi / 180))
            bias = ["rectangle": [
                "low": ["latitude": near.lat - degrees, "longitude": near.lng - lngDegrees],
                "high": ["latitude": near.lat + degrees, "longitude": near.lng + lngDegrees],
            ]]
        } else {
            bias = ["rectangle": [
                "low": ["latitude": 34.0, "longitude": -12.0],
                "high": ["latitude": 71.0, "longitude": 40.0],
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "textQuery": q,
            "pageSize": 10,
            "locationBias": bias,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            // 429 is the daily quota gone — the control that protects the
            // bill, doing its job. Worth telling the person searching, because
            // otherwise it is indistinguishable from "no such place".
            if (response as? HTTPURLResponse)?.statusCode == 429 {
                GoogleAvailability.noteRefusal()
            }
            return []
        }
        GoogleAvailability.noteSuccess()
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
                googleRatingCount: p["userRatingCount"] as? Int,
                productURL: nil,
                websiteURL: p["websiteUri"] as? String
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
        // Oct 17 — the ceiling, checked before the request goes out.
        guard GoogleBudget.allow(.places) else { return nil }
        guard let url = URL(string: "https://places.googleapis.com/v1/places/\(placeId)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(googleKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleId, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue(
            "photos,primaryTypeDisplayName,editorialSummary," +
            "regularOpeningHours.weekdayDescriptions,rating,userRatingCount,websiteUri," +
            // Oct 12 — "include the website for restaurants and booking links
            // as well, as per Google." Google holds both: the place's own site
            // and, separately, whatever reservation service it uses — OpenTable,
            // SevenRooms, Resy. A restaurant page with a Book button is the
            // difference between reading about somewhere and going.
            "reservable,websiteUri,googleMapsLinks.placeUri",
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

        // Google's Places API exposes that a place takes reservations, but not
        // the booking URL itself — that lives behind its own "Place Actions"
        // product, which this key has no access to. So the honest version is
        // to say it takes bookings and send you to the Google listing, where
        // the Reserve button is. Inventing an OpenTable search URL from the
        // name would land people on the wrong restaurant often enough to be
        // worse than not offering it.
        let reservable = (json["reservable"] as? Bool) ?? false
        let mapsLink = (json["googleMapsLinks"] as? [String: Any])?["placeUri"] as? String

        return RexPlaceDetails(
            summary: summary,
            openingHours: hours,
            photoURLs: Array(photoURLs),
            rating: json["rating"] as? Double,
            ratingCount: json["userRatingCount"] as? Int,
            websiteURL: json["websiteUri"] as? String,
            takesBookings: reservable,
            googleMapsURL: mapsLink
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
        // Oct 17 — the ceiling, checked before the request goes out.
        guard GoogleBudget.allow(.places) else { return nil }
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
        // Oct 17 — the ceiling, checked before the request goes out.
        guard GoogleBudget.allow(.geocoding) else { return nil }
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
    /// Oct 16 — 16,224 Geocoding calls in a month, £19.55, from twenty users.
    ///
    /// This cache was correct and useless. It stores the *answer*, so a
    /// second caller only benefits once the first has come back — and the
    /// callers here do not arrive one at a time. repairMissingMapCoords
    /// spawns one Task per place on every map load, so fifteen hundred
    /// checks start at the same instant, every one of them asks for the
    /// centre of the United Kingdom, and not one finds a cached value
    /// because none of them has finished yet. A thundering herd: hundreds of
    /// identical billable requests for one fact that does not change.
    ///
    /// Storing the Task instead of its result is the fix. The first caller
    /// to ask for a country puts its in-flight lookup in the dictionary and
    /// everyone behind it awaits that same lookup — one request per country
    /// per launch, however many places are being checked at once.
    private static var cityCentres: [String: Task<(lat: Double, lng: Double)?, Never>] = [:]
    private static let cityLock = NSLock()

    private static func centre(of city: String) async -> (lat: Double, lng: Double)? {
        let key = city.lowercased()
        // A country's centre is a fact, not a lookup — the common ones never
        // need asking at all. This table alone removes nearly every call
        // this function used to make, since the addresses being checked are
        // overwhelmingly in a handful of countries.
        if let known = Self.knownCountryCentres[key] { return known }

        let task: Task<(lat: Double, lng: Double)?, Never> = cityLock.withLock {
            if let existing = cityCentres[key] { return existing }
            let fresh = Task { await geocode(city) }
            cityCentres[key] = fresh
            return fresh
        }
        return await task.value
    }

    /// Where the addresses in this app actually are. Centroids, to the
    /// nearest degree or so, which is all a 2,500km sanity check can use.
    private static let knownCountryCentres: [String: (lat: Double, lng: Double)] = [
        "uk": (54.0, -2.0), "united kingdom": (54.0, -2.0), "gb": (54.0, -2.0),
        "england": (52.5, -1.5), "scotland": (56.8, -4.2),
        "wales": (52.3, -3.7), "northern ireland": (54.6, -6.7),
        "ireland": (53.4, -8.0), "france": (46.6, 2.3), "spain": (40.2, -3.6),
        "portugal": (39.5, -8.0), "italy": (42.8, 12.6), "germany": (51.2, 10.4),
        "netherlands": (52.2, 5.3), "belgium": (50.6, 4.6), "switzerland": (46.8, 8.2),
        "austria": (47.6, 14.1), "greece": (39.0, 22.0), "croatia": (45.1, 16.4),
        "denmark": (56.0, 10.0), "sweden": (62.0, 15.0), "norway": (64.0, 11.0),
        "iceland": (64.9, -19.0), "poland": (52.0, 19.4), "czechia": (49.8, 15.5),
        "czech republic": (49.8, 15.5), "hungary": (47.2, 19.5), "turkey": (39.0, 35.2),
        "morocco": (31.8, -7.1), "usa": (39.8, -98.6), "united states": (39.8, -98.6),
        "us": (39.8, -98.6), "canada": (56.1, -106.3), "mexico": (23.6, -102.5),
        "australia": (-25.3, 133.8), "new zealand": (-41.0, 174.0),
        "japan": (36.2, 138.3), "thailand": (15.9, 101.0), "india": (20.6, 79.0),
        "south africa": (-30.6, 22.9), "brazil": (-14.2, -51.9),
        "argentina": (-38.4, -63.6), "uae": (23.4, 53.8),
        "united arab emirates": (23.4, 53.8), "antigua and barbuda": (17.1, -61.8),
    ]

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
    /// Oct 8 — "for the golf trip Harry uploaded there is no additional
    /// detail on the golf courses. Why is that? Can we make the pages more
    /// like the restaurant."
    ///
    /// Because an imported place arrived as a bare name with a pin. This
    /// function asks Google for the place and gets back everything a place
    /// page is built from — the place id, photos, the rating, the website,
    /// the cuisine — and then returns two numbers out of it. Without the
    /// place id, ItemDetailView.loadPlaceDetails refuses to fetch anything
    /// at all, so the page has nothing to show.
    ///
    /// Same shape as `locate` below, including the same plausibility check,
    /// but it hands back the whole result. A geocode-only fallback can't
    /// produce one, so nil here means "use locate and keep the pin".
    static func locateDetailed(name: String?, address: String?, context: [String?] = []) async -> RexSearchHit? {
        let cleanContext = context.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let query = ([name].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                     + cleanContext).joined(separator: ", ")
        guard !query.isEmpty,
              let hit = (try? await places(query))?.first,
              let lat = hit.lat, let lng = hit.lng
        else { return nil }

        // The same refusal as locate: no detail beats detail about somewhere
        // in the wrong country. See the note on plausibleRadiusMeters.
        guard let expected = cleanContext.first, let centre = await centre(of: expected) else { return hit }
        return metres((lat, lng), centre) <= plausibleRadiusMeters ? hit : nil
    }

    static func locate(name: String?, address: String?, context: [String?] = []) async -> (lat: Double, lng: Double, address: String?)? {
        if let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), address.count > 8,
           address.contains(where: \.isNumber) || address.contains(",") {
            // A real street address is specific enough to trust on its own —
            // but only once it has been checked against the country it names.
            // Oct 13: this early return skipped the plausibility test below,
            // so a geocode that landed in the wrong continent was saved
            // without anything ever asking whether it made sense.
            if let located = await geocodeDetailed(address),
               await isPlausible(located.lat, located.lng, for: address) {
                return located
            }
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

    /// Whether a point sits anywhere near the place an address names.
    ///
    /// Checked against the last comma-separated part, which in an address
    /// written out in full is the country. No part to check, or nowhere we can
    /// place it, means no opinion — this refuses wrong answers, it does not
    /// demand proof of right ones.
    static func isPlausible(_ lat: Double, _ lng: Double, for address: String) async -> Bool {
        let tail = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let country = tail.last, country.count > 2,
              // Oct 17 — only ask about something that could be a country.
              //
              // The last comma-separated piece of an address is usually one,
              // but plenty of our rows end in a postcode or a street instead,
              // and each distinct one of those was a cache key of its own and
              // therefore a billable lookup. A country name has no digits in
              // it and is not a sentence; anything else we decline to judge,
              // which means the pin is left alone rather than re-found.
              !country.contains(where: \.isNumber),
              country.count <= 40,
              let centre = await centre(of: country) else { return true }
        // A country is a big thing: this is a continent-scale sanity check,
        // not a precision one. Colombia's centre to anywhere in Europe is
        // thousands of kilometres; Cartagena to Bogotá is 650.
        return metres((lat, lng), centre) <= 2_500_000
    }

    /// Oct 13 — "fix location button isn't working", and "these pins are also
    /// wrong still — Sofitel and Blue Apple".
    ///
    /// Re-check used to geocode the address text and nothing else. Two things
    /// were wrong with that. It went through the Geocoding API, which carried
    /// the Europe rectangle, so pressing the button asked the same question
    /// that produced the wrong pin and got the same answer — working exactly
    /// as built, and indistinguishable from broken. And the Geocoding API is
    /// built for street addresses: "Sofitel Legend Santa Clara" and "Blue
    /// Apple Beach House, Isla Tierra Bomba" are venues, and it answers those
    /// by matching fragments of the words to whatever nearby thing it can,
    /// which is how you end up beside the airport instead of on the island.
    ///
    /// Places Text Search is built for named venues, so it asks first, with
    /// the name and the address together. Geocoding stays as the fallback for
    /// a genuine street address Places has never heard of.
    static func pinpoint(name: String?, address: String) async -> (lat: Double, lng: Double, address: String?)? {
        let cleanName = name?.trimmingCharacters(in: .whitespaces) ?? ""
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAddress.isEmpty else { return nil }

        let query = cleanName.isEmpty || cleanAddress.localizedCaseInsensitiveContains(cleanName)
            ? cleanAddress
            : "\(cleanName), \(cleanAddress)"

        if let hit = (try? await places(query))?.first, let lat = hit.lat, let lng = hit.lng,
           await isPlausible(lat, lng, for: cleanAddress) {
            return (lat, lng, hit.address ?? cleanAddress)
        }
        if let located = await geocodeDetailed(cleanAddress),
           await isPlausible(located.lat, located.lng, for: cleanAddress) {
            return located
        }
        return nil
    }

    static func geocode(_ query: String) async -> (lat: Double, lng: Double)? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !googleKey.isEmpty else { return nil }
        // Oct 17 — the ceiling, checked before the request goes out.
        guard GoogleBudget.allow(.geocoding) else { return nil }
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
        /// Oct 4 — "can we do the same thing we did for places with films and
        /// TV? Ie cast and length." Length was already in `facts`; the cast
        /// is what was missing, and it's the part people actually scan for.
        var cast: [CastMember] = []
        /// "15", "PG", "TV-MA" — the certificate for the viewer's own country
        /// where TMDB has it.
        var certificate: String?
        /// Oct 4 — the landscape still TMDB holds alongside the portrait
        /// poster. A film page opens with a picture across the width, the way
        /// a place page does, and this is the only landscape image a film has.
        var backdropURL: String?
        /// Oct 12 — subscription services the viewer's own country can watch
        /// this on. Empty where TMDB has nothing for that region, which is
        /// commoner than you would think outside the US and UK.
        var watchOn: [WatchProvider] = []
        /// TMDB's own page listing every way to watch, which is what its data
        /// licence asks you to link to rather than deep-linking each service.
        var watchLink: String?
        var isEmpty: Bool {
            synopsis == nil && ratings.isEmpty && facts == nil && cast.isEmpty
        }
    }

    struct WatchProvider: Identifiable, Hashable {
        let name: String
        let logoURL: String?
        var id: String { name }
    }

    struct CastMember: Identifiable, Hashable {
        let name: String
        let role: String?
        let imageURL: String?
        /// Oct 15 — "like authors, can we make the cast clickable? So you can
        /// see what else they've been in?" TMDB's person id, which is what
        /// their credits hang off. Optional because it has only been read
        /// since this was asked for; a cast member fetched by an older build
        /// and cached has a name and no id, and a name alone is not something
        /// to go looking up a person by.
        let personId: Int?
        var id: String { name + (role ?? "") }
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
        // credits and the certificate ride along on the same request rather
        // than costing two more — TMDB charges nothing either way, but a
        // detail page that fires three calls feels like one that fires three.
        // Oct 12 — "include on a card for film and TV where you can watch said
        // show (e.g. Amazon Prime, Netflix). Make it prominent at the top."
        //
        // watch/providers rides along on the same request for the same reason
        // credits does: TMDB charges nothing extra and a page that fires four
        // calls feels like one that fires four.
        let fields = (kind == "movie" ? "credits,release_dates" : "credits,content_ratings")
            + ",watch/providers"
        guard !tmdbKey.isEmpty,
              let json = try? await getJSON("https://api.themoviedb.org/3/\(kind)/\(id)?api_key=\(tmdbKey)&append_to_response=\(fields)") else { return out }

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

        // Where you can actually watch it, for the viewer's own country.
        //
        // TMDB returns this per region keyed by ISO code, and the regions
        // disagree — a show on Netflix here can be on Hulu in the States, and
        // saying the wrong one is worse than saying nothing. The phone's own
        // region is the only honest guess available, and anything we have no
        // entry for simply gets no row.
        //
        // "flatrate" only: that is included-with-subscription. TMDB also
        // returns rent and buy, which answer a different question — "where can
        // I watch this" means tonight, on something you already pay for, not
        // "which shop sells it".
        let region = Locale.current.region?.identifier ?? "GB"
        if let providers = json["watch/providers"] as? [String: Any],
           let results = providers["results"] as? [String: Any],
           let here = results[region] as? [String: Any] {
            let flatrate = (here["flatrate"] as? [[String: Any]]) ?? []
            out.watchOn = flatrate.compactMap { entry in
                guard let name = entry["provider_name"] as? String else { return nil }
                let logo = (entry["logo_path"] as? String)
                    .map { "https://image.tmdb.org/t/p/w92\($0)" }
                return WatchProvider(name: name, logoURL: logo)
            }
            // TMDB's own page for this title, which is where its "JustWatch"
            // attribution asks you to send people.
            out.watchLink = here["link"] as? String
        }

        // Billing order is TMDB's own, which is the order the credits run in —
        // so the first few are the people someone would recognise.
        if let credits = json["credits"] as? [String: Any],
           let cast = credits["cast"] as? [[String: Any]] {
            out.cast = cast.prefix(12).compactMap { member in
                guard let name = member["name"] as? String, !name.isEmpty else { return nil }
                let role = (member["character"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let path = member["profile_path"] as? String
                return CastMember(
                    name: name,
                    role: role,
                    imageURL: path.map { "https://image.tmdb.org/t/p/w185\($0)" },
                    personId: member["id"] as? Int
                )
            }
        }

        out.certificate = certificate(from: json, kind: kind)
        if let path = json["backdrop_path"] as? String, !path.isEmpty {
            out.backdropURL = "https://image.tmdb.org/t/p/w780\(path)"
        }

        // The imdb_id here is what lets OMDb find the same title.
        let imdbId = json["imdb_id"] as? String ?? json["external_ids"] as? String
        if let extra = await omdbRatings(imdbId: imdbId, title: title) {
            out.ratings.append(contentsOf: extra)
        }
        return out
    }

    /// TMDB files certificates per country under two different shapes
    /// depending on whether it's a film or a programme. GB first because
    /// that's where REX is being used, then US as the usual fallback.
    private static func certificate(from json: [String: Any], kind: String) -> String? {
        let preferred = ["GB", "US"]
        if kind == "movie" {
            let results = (json["release_dates"] as? [String: Any])?["results"] as? [[String: Any]] ?? []
            for country in preferred {
                guard let entry = results.first(where: { $0["iso_3166_1"] as? String == country }),
                      let dates = entry["release_dates"] as? [[String: Any]] else { continue }
                if let rating = dates.compactMap({ $0["certification"] as? String })
                    .first(where: { !$0.isEmpty }) { return rating }
            }
            return nil
        }
        let results = (json["content_ratings"] as? [String: Any])?["results"] as? [[String: Any]] ?? []
        for country in preferred {
            if let entry = results.first(where: { $0["iso_3166_1"] as? String == country }),
               let rating = entry["rating"] as? String, !rating.isEmpty { return rating }
        }
        return nil
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
    static func linkPreview(for url: URL) async -> (title: String?, imageURL: String?, siteName: String?) {
        var request = URLRequest(url: url, timeoutInterval: 8)
        // Some shops serve an empty shell to anything that doesn't look like
        // a browser; Safari's own agent gets the real page.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400 else { return (nil, nil, nil) }
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
        // Oct 21 — the shop's own name, for the subtitle of a pasted link.
        // Falls back to the host with the www. and the TLD taken off, which
        // for johnlewis.com reads "johnlewis" — not beautiful, and better
        // than a product with no idea where it came from.
        let site = meta(["og:site_name", "twitter:site", "application-name"])
            ?? url.host?
                .replacingOccurrences(of: "www.", with: "")
                .components(separatedBy: ".").first
        return (title, image, site)
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

extension RexSearch {
    /// Oct 15 — what else this person has been in.
    ///
    /// TMDB's combined credits, which covers film and television in one call,
    /// ordered by how well known the title is rather than by date: the point
    /// of the screen is recognition — "oh, *that* one" — and a chronological
    /// list buries that under everything they did before anyone noticed.
    ///
    /// Their own appearance in the thing you came from is dropped by the
    /// caller, which knows what that is.
    static func personCredits(personId: Int) async -> [RexSearchHit] {
        guard !tmdbKey.isEmpty else { return [] }
        guard let json = try? await getJSON(
            "https://api.themoviedb.org/3/person/\(personId)/combined_credits?api_key=\(tmdbKey)"
        ), let cast = json["cast"] as? [[String: Any]] else { return [] }

        // Checked against the live endpoint: sorting ninety-eight credits by
        // popularity put The Tonight Show, Colbert, The Daily Show and Kelly
        // Clarkson in the first five — because a chat show is more popular
        // than almost any film, and every actor has been on all of them.
        //
        // "What else have they been in" does not mean "where have they sat on
        // a sofa", so appearances as themselves go, and so do the formats
        // that are nothing but: talk (10767), news (10763) and reality
        // (10764).
        let chatShow: Set<Int> = [10767, 10763, 10764]
        let acting = cast.filter { credit in
            let character = (credit["character"] as? String ?? "").lowercased()
            if character == "self" || character.hasPrefix("self ") || character.hasPrefix("self-") {
                return false
            }
            let genres = Set(credit["genre_ids"] as? [Int] ?? [])
            return genres.isDisjoint(with: chatShow)
        }
        let sorted = acting.sorted {
            ($0["popularity"] as? Double ?? 0) > ($1["popularity"] as? Double ?? 0)
        }
        var seen = Set<String>()
        return sorted.compactMap { credit -> RexSearchHit? in
            // A person credited on both halves of a franchise, or on a show
            // once per season, should appear once.
            guard let mediaType = credit["media_type"] as? String,
                  mediaType == "movie" || mediaType == "tv",
                  let id = credit["id"] as? Int,
                  let title = (credit["title"] as? String) ?? (credit["name"] as? String),
                  !title.isEmpty,
                  seen.insert("\(mediaType):\(id)").inserted
            else { return nil }
            let date = (credit["release_date"] as? String) ?? (credit["first_air_date"] as? String)
            let year = date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
            let path = credit["poster_path"] as? String
            return RexSearchHit(
                externalId: String(id),
                externalSource: mediaType == "movie" ? "tmdb_movie" : "tmdb_tv",
                title: title,
                subtitle: [credit["character"] as? String, year]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} "),
                imageURL: path.map { "https://image.tmdb.org/t/p/w342\($0)" },
                genre: mediaType == "movie" ? "Movie" : "TV"
            )
        }
    }
}

extension RexSearch {
    /// Oct 15 — a picture for something whose only identity is a link.
    ///
    /// The Custom Search JSON API was meant to find these and never will: it
    /// is closed to new customers, which is what the 403 has been saying all
    /// along underneath a message that sounded like a permission we could be
    /// granted. Wikipedia covers the things that have articles — board games,
    /// books, films — and covers a kettle not at all.
    ///
    /// But a product someone links to already has a photograph, on the page
    /// they linked: og:image is the picture the shop itself chose for sharing,
    /// which is the product shot. No API, no key, no quota, and more accurate
    /// than an image search would have been — the page is the right answer by
    /// construction, where a search is a guess.
    static func openGraphImage(for pageURL: URL) async -> String? {
        guard let scheme = pageURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        var request = URLRequest(url: pageURL)
        // Shops serve a different, thinner page to anything that looks like a
        // crawler, and some serve nothing at all. Asking as a browser gets the
        // page a person would see, which is the one with the metadata on it.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode < 400
        else { return nil }
        // The head is where the metadata lives; a megabyte of product page
        // below it is nothing to do with us.
        let head = String(decoding: data.prefix(200_000), as: UTF8.self)

        for property in ["og:image:secure_url", "og:image", "twitter:image", "twitter:image:src"] {
            if let found = metaContent(in: head, property: property),
               let absolute = URL(string: found, relativeTo: pageURL)?.absoluteURL,
               absolute.scheme?.hasPrefix("http") == true {
                return absolute.absoluteString
            }
        }
        return nil
    }

    /// `content` of the first meta tag with this property or name. Written
    /// against the two orders real pages use — property first or content
    /// first — rather than assuming one.
    private static func metaContent(in html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            "<meta[^>]+(?:property|name)\\s*=\\s*[\"']\(escaped)[\"'][^>]*?content\\s*=\\s*[\"']([^\"']+)[\"']",
            "<meta[^>]+content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*?(?:property|name)\\s*=\\s*[\"']\(escaped)[\"']",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: html)
            else { continue }
            let value = String(html[captured])
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }
}
