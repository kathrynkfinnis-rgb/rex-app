import SwiftUI

/// Sept 29 — "Talk to Rex": the shapes the server speaks, and the one piece of
/// work the phone does that the server can't.
///
/// The division of labour matters. The server never describes an item — it
/// returns the id of a real recommendation, or, when your friends had nothing,
/// a search hint. Resolving that hint is done here, through the same catalogue
/// search the Add screen uses, so a web card is a real, findable thing rather
/// than a sentence a model wrote. Anything that doesn't resolve is dropped
/// silently: a suggestion nobody can look up is worse than one fewer.

struct AskRexTurn {
    let role: String   // "them" or "rex"
    let text: String
}

/// What the edge function returns.
struct AskRexReply: Decodable {
    let answer: String
    let picks: [Pick]
    let web: [WebHint]
    /// True when there wasn't much in your friends' Rex to work with, so the
    /// screen can say so plainly instead of the absence being a mystery.
    let friends_were_thin: Bool

    struct Pick: Decodable {
        let recommendation_id: String
        let item_id: String
        let why: String?
    }

    struct WebHint: Decodable {
        let title: String
        let search_hint: String
        let type: String
        let why: String?
    }
}

struct RexFact: Decodable, Identifiable {
    let id: String
    let fact: String
    /// "stated" if they said it outright, "inferred" if Rex worked it out.
    let source: String
    let updated_at: String
}

/// A web suggestion once it has been found in a real catalogue. Carries the
/// hit so tapping it can open the normal add-a-Rex flow — the whole point of
/// the web tier is that it feeds the thing that replaces it.
struct AskRexWebResult: Identifiable {
    let id: String
    let hit: RexSearchHit
    let category: RexCategory
    let why: String?
}

/// One answer, with everything needed to draw it.
///
/// `web` fills in after the rest. Resolving three search hints means three
/// round trips to Google Places on top of the model call, which took the
/// Edinburgh answer to about 25 seconds while the friends' half had been ready
/// at 8 — so the answer is published as soon as the friends' cards exist, and
/// the web results append themselves when they arrive. A class rather than a
/// struct precisely so that later arrival can reach a value already on screen.
@MainActor
final class AskRexAnswer: Identifiable, ObservableObject {
    let id = UUID()
    let question: String
    let prose: String
    let friends: [FeedRecommendation]
    /// Why each pick, keyed by recommendation id — Rex's line, kept separate
    /// from the friend's own note so the two are never confused on screen.
    let reasons: [String: String]
    let friendsWereThin: Bool

    /// Empty until the lookups finish; `isResolvingWeb` is what lets the view
    /// say "still looking" rather than "nothing found".
    @Published var web: [AskRexWebResult] = []
    @Published var isResolvingWeb: Bool

    init(
        question: String,
        prose: String,
        friends: [FeedRecommendation],
        reasons: [String: String],
        friendsWereThin: Bool,
        expectsWeb: Bool
    ) {
        self.question = question
        self.prose = prose
        self.friends = friends
        self.reasons = reasons
        self.friendsWereThin = friendsWereThin
        self.isResolvingWeb = expectsWeb
    }
}

enum AskRex {
    /// Ask, and return as soon as there is something worth showing.
    ///
    /// The friends' cards are one database read and come back immediately. The
    /// web hints are a Places lookup each and are left to finish on their own,
    /// writing themselves into the answer when they do — so the screen fills in
    /// rather than sitting on a spinner for the slowest part of the job.
    static func ask(_ question: String, history: [AskRexTurn]) async throws -> AskRexAnswer {
        let reply = try await RexAPI.shared.askRex(question: question, history: history)

        let friends = (try? await RexAPI.shared.fetchRecommendations(
            ids: reply.picks.map(\.recommendation_id)
        )) ?? []

        var reasons: [String: String] = [:]
        for pick in reply.picks {
            if let why = pick.why, !why.isEmpty { reasons[pick.recommendation_id] = why }
        }

        let answer = await AskRexAnswer(
            question: question,
            prose: reply.answer,
            friends: friends,
            reasons: reasons,
            friendsWereThin: reply.friends_were_thin,
            expectsWeb: !reply.web.isEmpty
        )

        if !reply.web.isEmpty {
            Task {
                let resolved = await resolve(reply.web)
                await MainActor.run {
                    answer.web = resolved
                    answer.isResolvingWeb = false
                }
            }
        }

        return answer
    }

    /// Look each hint up in the real catalogue. A suggestion that can't be
    /// found is dropped rather than shown — the model naming a restaurant is
    /// not evidence the restaurant exists, and this is the step that makes
    /// that distinction real rather than promised.
    private static func resolve(_ hints: [AskRexReply.WebHint]) async -> [AskRexWebResult] {
        guard !hints.isEmpty else { return [] }

        return await withTaskGroup(of: (Int, AskRexWebResult?).self) { group in
            for (index, hint) in hints.enumerated() {
                group.addTask {
                    let category = RexCategory(rawValue: hint.type) ?? .place
                    let hits = await RexSearch.search(category: category, query: hint.search_hint)
                    guard let best = hits.first else { return (index, nil) }
                    return (index, AskRexWebResult(
                        id: "\(best.externalSource):\(best.externalId)",
                        hit: best,
                        category: category,
                        why: hint.why
                    ))
                }
            }

            // Order is the model's ranking, and a task group finishes in
            // whatever order it likes — so they're put back in place.
            var found: [(Int, AskRexWebResult)] = []
            for await (index, result) in group {
                if let result { found.append((index, result)) }
            }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
