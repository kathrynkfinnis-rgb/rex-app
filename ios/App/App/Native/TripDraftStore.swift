import Foundation

/// Sept 7 — "on trips, when I'm adding a stop and I go onto another window
/// on my phone and go back to it, it deletes."
///
/// A half-built trip lived only in AddRexView's `@State`. That survives a
/// quick app switch, but iOS reclaims memory from backgrounded apps freely,
/// and when it terminates one there is nothing to come back to — twenty
/// minutes of itinerary, gone, with no warning and no way to recover it.
///
/// So the draft is written to disk as it's built, and offered back the next
/// time the form opens. Deliberately a plain file rather than a row in the
/// database: it's incomplete by definition, it's nobody else's business, and
/// it must survive with no network. Cleared the moment the trip is posted or
/// the draft is explicitly discarded.
struct TripDraft: Codable {
    var isList: Bool
    var title: String
    var note: String
    var rating: Double
    var listKind: String
    var tripMonth: Int?
    var tripYear: Int?
    var photoURLs: [String]
    var entries: [ItineraryEntry]
    var savedAt: Date
    /// Sept 10 — a list's free-text Notes. Optional so a draft saved by an
    /// older build still decodes.
    var longNote: String? = nil

    /// Nothing worth restoring — an empty form shouldn't prompt anyone.
    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty && entries.isEmpty
            && (longNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum TripDraftStore {
    private static var url: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("rex-trip-draft.json")
    }

    static func save(_ draft: TripDraft) {
        guard let url, !draft.isEmpty else { return }
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(draft).write(to: url, options: .atomic)
        } catch {
            // A draft that can't be saved shouldn't interrupt what you're
            // doing — you simply get the old behaviour for this one trip.
        }
    }

    static func load() -> TripDraft? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        guard let draft = try? JSONDecoder().decode(TripDraft.self, from: data), !draft.isEmpty else {
            return nil
        }
        // A fortnight-old draft is almost certainly forgotten rather than
        // in progress, and offering it back is more startling than helpful.
        guard draft.savedAt > Date().addingTimeInterval(-14 * 24 * 60 * 60) else {
            clear()
            return nil
        }
        return draft
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
