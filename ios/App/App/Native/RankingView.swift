import SwiftUI

/// Oct 13 — Joe's idea, via Kathryn: "I would love to have my library of books
/// in a ranking order… you rank it against your other books. So you finish a
/// book and think ok that was better than The Harry Quebert Affair but not as
/// good as A Little Life, so it sits between them."
///
/// Placing one thing in an ordering is a binary search, and that is what makes
/// this feasible rather than exhausting. Each answer halves what is left, so a
/// two-hundred-book library places a new book in about eight questions — and a
/// twenty-book one in five. Asking against every book would be two hundred.
///
/// The questions deliberately compare against the middle of the remaining
/// range rather than against neighbours. Comparing against a book you half
/// remember from the middle of your library is a real judgement; comparing
/// against the two either side of where it already is tells you almost nothing
/// and takes just as long.
struct RankingSession {
    /// Everything already placed, best first. Never mutated during a session —
    /// the answers narrow a window into it instead.
    private let placed: [RankedItem]
    private var low: Int
    private var high: Int

    init(placed: [RankedItem]) {
        self.placed = placed
        self.low = 0
        self.high = placed.count
    }

    /// The thing to compare against next, or nil when the position is known.
    var opponent: RankedItem? {
        guard low < high else { return nil }
        return placed[(low + high) / 2]
    }

    /// How many questions are left at most, for the "about four more" line.
    var remainingQuestions: Int {
        max(0, Int(ceil(log2(Double(max(1, high - low + 1))))))
    }

    /// `better` is true when the new thing beat the one on screen.
    mutating func answer(better: Bool) {
        guard low < high else { return }
        let mid = (low + high) / 2
        if better { high = mid } else { low = mid + 1 }
    }

    var isFinished: Bool { low >= high }

    /// Where in the ordering the answers put it: 0 is above everything.
    ///
    /// The index, not the position, is what the questions actually determined.
    /// Renumbering changes every position and no index, which is what lets a
    /// renumber happen mid-placement without losing the answers.
    var resolvedIndex: Int { low }

    /// The position to store: halfway between the neighbours it landed
    /// between. Ends of the list get a whole step clear, so "best book I've
    /// read" isn't crammed against the second.
    var resolvedPosition: Double {
        RankingSession.position(at: low, in: placed)
    }

    static func position(at index: Int, in placed: [RankedItem]) -> Double {
        let above = index > 0 ? placed[index - 1].position : nil
        let below = index < placed.count ? placed[index].position : nil
        switch (above, below) {
        case let (nil, below?): return below - 1
        case let (above?, nil): return above + 1
        case let (above?, below?): return (above + below) / 2
        case (nil, nil): return 1
        }
    }

    /// True when the neighbours have been halved so many times there is no room
    /// left between them, and the ordering needs renumbering before this can be
    /// stored. Doubles run out at around fifty insertions into the same gap.
    var needsRenumbering: Bool {
        let index = low
        guard index > 0, index < placed.count else { return false }
        return abs(placed[index].position - placed[index - 1].position) < 0.000001
    }
}

/// The screen that asks the questions.
struct RankingCompareView: View {
    let newItem: RexItem
    let category: RexCategory
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var session: RankingSession?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let session, let opponent = session.opponent, let other = opponent.items {
                    question(against: other, remaining: session.remainingQuestions)
                } else {
                    // Nothing placed yet: the first thing in a category needs
                    // no comparison, it just goes in.
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Where does it sit?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }
                }
            }
            .task { await start() }
        }
        .tint(RexColor.primary)
    }

    private func question(against other: RexItem, remaining: Int) -> some View {
        VStack(spacing: RexSpacing.lg) {
            Text("Which did you like more?")
                .font(RexFont.display(26))
                .foregroundStyle(RexColor.foreground)
                .padding(.top, RexSpacing.lg)

            VStack(spacing: RexSpacing.md) {
                contender(newItem, label: "The new one", highlight: true) {
                    Task { await answer(better: true) }
                }
                Text("or")
                    .font(RexFont.editorial(21))
                    .foregroundStyle(RexColor.mutedForeground)
                contender(other, label: "Already in your order", highlight: false) {
                    Task { await answer(better: false) }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.destructive)
            }

            // Says how much is left, because an open-ended run of questions is
            // what makes people quit halfway.
            Text(remaining <= 1 ? "Last one." : "About \(remaining) more.")
                .font(RexFont.text(12))
                .foregroundStyle(RexColor.mutedForeground)

            Spacer()
        }
        .padding(RexSpacing.page)
        .frame(maxWidth: .infinity)
        .opacity(isSaving ? 0.5 : 1)
        .allowsHitTesting(!isSaving)
    }

    private func contender(_ item: RexItem, label: String, highlight: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: RexSpacing.md) {
                Group {
                    if let urlString = item.image_url, let url = URL(string: urlString) {
                        GoogleSafeAsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RexColor.muted
                        }
                    } else {
                        ZStack {
                            RexColor.badgeBackground
                            Image(systemName: category.symbol)
                                .font(.system(size: 22))
                                .foregroundStyle(RexColor.primary)
                        }
                    }
                }
                .frame(width: 60, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(label.uppercased())
                        .font(RexFont.text(10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(RexColor.mutedForeground)
                    Text(item.title)
                        .font(RexFont.display(19))
                        .foregroundStyle(RexColor.foreground)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(RexFont.editorial(17))
                            .foregroundStyle(RexColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(RexSpacing.md)
            .background(highlight ? RexColor.badgeBackground : RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                    .stroke(highlight ? RexColor.primary : RexColor.border, lineWidth: highlight ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func start() async {
        isLoading = true
        var placed = await RexAPI.shared.fetchRanking(category: category.rawValue)
        // Comparing something against itself is not a question. Happens when
        // you re-rank a book that is already placed.
        placed.removeAll { $0.item_id == newItem.id }

        if placed.isEmpty {
            // First in its category: straight in, nothing to weigh it against.
            try? await RexAPI.shared.placeInRanking(
                itemId: newItem.id, category: category.rawValue, position: 1
            )
            isLoading = false
            onFinished()
            dismiss()
            return
        }

        session = RankingSession(placed: placed)
        isLoading = false
    }

    private func answer(better: Bool) async {
        guard var current = session else { return }
        current.answer(better: better)
        session = current
        guard current.isFinished else { return }

        isSaving = true
        defer { isSaving = false }
        do {
            // Halving the same gap enough times exhausts a double. Renumber
            // first, then work the position out again from the tidied list.
            //
            // The answers survive this because what the questions determined
            // is an *index* — "it goes seventh" — and renumbering changes
            // every position while preserving the order. So the same index
            // still means the same place, and nothing has to be asked twice.
            var position = current.resolvedPosition
            if current.needsRenumbering {
                try await RexAPI.shared.renumberRanking(category: category.rawValue)
                var placed = await RexAPI.shared.fetchRanking(category: category.rawValue)
                placed.removeAll { $0.item_id == newItem.id }
                position = RankingSession.position(at: current.resolvedIndex, in: placed)
            }
            try await RexAPI.shared.placeInRanking(
                itemId: newItem.id, category: category.rawValue, position: position
            )
            onFinished()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
