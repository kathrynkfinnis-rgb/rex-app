import SwiftUI

/// The five-tier rating scale, replacing the old 1-10 crowns.
///
/// The `rating` column keeps storing 1-10 numbers exactly as it always
/// has — old rows never change, and nothing on the web app or the database
/// schema needs touching. A bucketing rule maps any stored value to one of
/// five tiers for display; picking a tier here saves a representative value
/// from within that same tier's band, so old and new data always bucket the
/// same way through the same rule.
enum RexRatingTier: Int, CaseIterable, Identifiable {
    case doNotRex = 1, meh, rex, loved, obsessed

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .doNotRex: return "\u{26D4}\u{FE0F}"       // ⛔️
        case .meh: return "\u{1F937}\u{200D}\u{2642}\u{FE0F}" // 🤷‍♂️
        case .rex: return "\u{1F44C}"                    // 👌
        case .loved: return "\u{2665}\u{FE0F}"           // ♥️
        case .obsessed: return "\u{1F4AF}"               // 💯
        }
    }

    var label: String {
        switch self {
        case .doNotRex: return "Do not Rex"
        case .meh: return "Meh"
        case .rex: return "Rex"
        case .loved: return "Loved"
        case .obsessed: return "Obsessed"
        }
    }

    /// What choosing this tier saves on the existing 1-10 column — picked to
    /// sit safely inside the band `tier(forRaw:)` would bucket back to this
    /// same tier, so a rating means the same thing whichever direction you
    /// read it.
    var representativeRawValue: Double {
        switch self {
        case .doNotRex: return 3
        case .meh: return 6
        case .rex: return 8
        case .loved: return 9
        case .obsessed: return 10
        }
    }

    /// Sub-6 -> Do not Rex, 6 -> Meh, 7-8 -> Rex, 9 -> Loved, 10 -> Obsessed.
    static func tier(forRaw raw: Double) -> RexRatingTier {
        switch raw {
        case ..<6: return .doNotRex
        case 6..<7: return .meh
        case 7..<9: return .rex
        case 9..<10: return .loved
        default: return .obsessed
        }
    }

    /// Averages tier numbers — not raw scores — across everyone who Rex'd
    /// the same thing, reported out of 5.
    static func averageTier(ratings: [Double]) -> Double? {
        let positive = ratings.filter { $0 > 0 }
        guard !positive.isEmpty else { return nil }
        let sum = positive.reduce(0.0) { $0 + Double(tier(forRaw: $1).rawValue) }
        return sum / Double(positive.count)
    }
}

/// Pick one of the five tiers. Replaces the old ten-crown row — same
/// `Double` binding contract, so every call site keeps working by only
/// swapping the view.
struct RexRatingPicker: View {
    @Binding var value: Double
    /// Allow clearing back to "not rated" by tapping the selected tier again.
    var clearable: Bool = false

    private var selectedTier: RexRatingTier? {
        value > 0 ? RexRatingTier.tier(forRaw: value) : nil
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RexRatingTier.allCases) { tier in
                let isSelected = selectedTier == tier
                Button {
                    value = (clearable && isSelected) ? 0 : tier.representativeRawValue
                } label: {
                    VStack(spacing: 4) {
                        Text(tier.emoji).font(.system(size: 22))
                        Text(tier.label)
                            .font(RexFont.text(10, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? RexColor.primaryForeground : RexColor.mutedForeground)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? RexColor.primary : RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                            .stroke(isSelected ? RexColor.primary : RexColor.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One person's rating, shown as their tier's emoji and name — the
/// discrete-tier display for a single Rex.
struct RexRatingBadge: View {
    let raw: Double
    var compact: Bool = false

    var body: some View {
        let tier = RexRatingTier.tier(forRaw: raw)
        HStack(spacing: 4) {
            Text(tier.emoji).font(.system(size: compact ? 12 : 14))
            if !compact {
                Text(tier.label)
                    .font(RexFont.text(13, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
            }
        }
    }
}

/// Several people's ratings on the same thing, averaged in tier-space and
/// shown out of 5 — "3.4/5" rather than picking a single winning tier.
struct RexRatingAverageBadge: View {
    let ratings: [Double]

    var body: some View {
        if let avg = RexRatingTier.averageTier(ratings: ratings) {
            let nearestRaw = min(5, max(1, Int(avg.rounded())))
            let nearest = RexRatingTier(rawValue: nearestRaw) ?? .rex
            HStack(spacing: 4) {
                Text(nearest.emoji).font(.system(size: 14))
                Text(String(format: "%.1f/5", avg))
                    .font(RexFont.text(14, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
            }
        }
    }
}

