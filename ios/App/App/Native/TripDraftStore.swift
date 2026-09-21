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
///
/// Sept 21 — "I just lost a whole trip by accident" ... "the draft prompt
/// didn't work as something else was in my drafts." This kept exactly ONE
/// draft, in one file, so starting anything new silently destroyed whatever
/// was already there. It keeps a list now, each with its own id, and the
/// form claims one for the session rather than writing over the slot.
struct TripDraft: Codable, Identifiable {
    /// Assigned when a compose session starts, so a draft is updated in place
    /// as you type rather than piling up a copy per keystroke.
    var id: UUID = UUID()
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
            .appendingPathComponent("rex-trip-drafts.json")
    }

    /// The one-per-device file this replaced. Read once, folded in, deleted —
    /// nobody should lose the draft they had open when they updated.
    private static var legacyURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("rex-trip-draft.json")
    }

    /// A fortnight-old draft is almost certainly forgotten rather than in
    /// progress, and offering it back is more startling than helpful.
    private static let keepFor: TimeInterval = 14 * 24 * 60 * 60

    static func all() -> [TripDraft] {
        var drafts: [TripDraft] = []
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TripDraft].self, from: data) {
            drafts = decoded
        }
        if let legacyURL, let data = try? Data(contentsOf: legacyURL),
           let old = try? JSONDecoder().decode(TripDraft.self, from: data) {
            drafts.append(old)
            try? FileManager.default.removeItem(at: legacyURL)
            write(drafts)
        }
        let cutoff = Date().addingTimeInterval(-keepFor)
        return drafts
            .filter { !$0.isEmpty && $0.savedAt > cutoff }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// The most recent unfinished thing — what the form offers back.
    static func load() -> TripDraft? { all().first }

    static func save(_ draft: TripDraft) {
        guard !draft.isEmpty else { return }
        var drafts = all().filter { $0.id != draft.id }
        drafts.append(draft)
        // A cap, so a pathological loop can't fill the disk. Oldest goes.
        write(Array(drafts.sorted { $0.savedAt > $1.savedAt }.prefix(20)))
    }

    /// Removes one draft — the one just posted or discarded — and leaves
    /// everything else alone. This is the whole point of the rewrite.
    static func clear(id: UUID) {
        write(all().filter { $0.id != id })
    }

    /// Everything, for a sign-out or a deliberate clear-out.
    static func clearAll() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func write(_ drafts: [TripDraft]) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(drafts).write(to: url, options: .atomic)
        } catch {
            // A draft that can't be saved shouldn't interrupt what you're
            // doing — you simply get the old behaviour for this one trip.
        }
    }
}
