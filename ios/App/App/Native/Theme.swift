import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// Premium editorial palette — FT / Linear / Notion in feel: calm, spacious,
/// mostly neutral. Roughly 85% white and warm neutrals, 10% forest green,
/// 5% accent. Colour is used sparingly and deliberately.
enum RexColor {
    // Brand
    static let primary = Color(hex: "173626")          // Forest green
    static let primaryPressed = Color(hex: "10271C")
    static let primaryForeground = Color(hex: "FFFFFF")
    static let moss = Color(hex: "4D6B56")             // Secondary green

    // Surfaces
    static let background = Color(hex: "F8F8F5")       // Warm white canvas
    static let card = Color(hex: "FFFFFF")
    static let border = Color(hex: "E2E5DE")
    static let divider = Color(hex: "ECEEE8")

    // Text
    static let foreground = Color(hex: "1D1D1D")       // Charcoal
    static let mutedForeground = Color(hex: "666A66")  // Soft grey
    static let placeholder = Color(hex: "9A9C98")
    static let disabled = Color(hex: "BCBEB8")

    // Status
    static let success = Color(hex: "2E7D32")
    static let gold = Color(hex: "C79A3B")             // Premium/featured ONLY
    static let destructive = Color(hex: "B44A3A")

    // Badges
    static let badgeBackground = Color(hex: "EEF1EC")
    static let badgeForeground = Color(hex: "4D6B56")

    // Kept for existing call sites; maps onto the neutral badge surface.
    static let muted = Color(hex: "ECEEE8")
    static let secondary = Color(hex: "EEF1EC")
    static let secondaryForeground = Color(hex: "4D6B56")
    static let accent = Color(hex: "C79A3B")
}

/// Corner radii from the spec.
enum RexRadius {
    static let button: CGFloat = 14
    static let input: CGFloat = 14
    static let card: CGFloat = 18
    static let tag: CGFloat = 999
}

/// 4 / 8 / 12 / 16 / 24 / 32 / 48, with 20pt default page padding.
enum RexSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
    static let page: CGFloat = 20
    static let betweenCards: CGFloat = 16
    static let cardPadding: CGFloat = 16
}

/// Deliberately barely-there. The spec calls for subtle borders, not floating
/// cards — so the border does the work and the shadow only lifts it a little.
struct RexCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                    .stroke(RexColor.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

extension View {
    func rexCard() -> some View { modifier(RexCardStyle()) }
}

/// Primary action: forest green, white text, 14pt radius.
struct RexPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(RexColor.primaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(configuration.isPressed ? RexColor.primaryPressed : RexColor.primary)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.button, style: .continuous))
    }
}

/// Secondary action: white with a forest-green border and label.
struct RexSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(RexColor.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(configuration.isPressed ? RexColor.badgeBackground : RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.button, style: .continuous)
                    .stroke(RexColor.primary, lineWidth: 1)
            )
    }
}

/// Editorial serif for headlines, system sans for everything else. Falls back
/// gracefully when the licensed display face isn't bundled.
enum RexFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

enum RexCategory: String {
    case place, trip, book, movie, tv, podcast, recipe, event, other

    var label: String {
        switch self {
        case .place: return "Place"
        case .trip: return "Trip"
        case .book: return "Book"
        case .movie: return "Movie"
        case .tv: return "TV"
        case .podcast: return "Podcast"
        case .recipe: return "Recipe"
        case .event: return "Event"
        case .other: return "Stuff"
        }
    }

    var symbol: String {
        switch self {
        case .place: return "mappin.circle"
        case .trip: return "bag"
        case .book: return "book"
        case .movie: return "film"
        case .tv: return "tv"
        case .podcast: return "mic"
        case .recipe: return "fork.knife"
        case .event: return "ticket"
        case .other: return "sparkles"
        }
    }

    init(rawType: String?) {
        self = RexCategory(rawValue: rawType ?? "other") ?? .other
    }
}

/// All categories in the order the web app shows them.
let rexAllCategories: [RexCategory] = [
    .place, .trip, .book, .movie, .tv, .podcast, .recipe, .event, .other,
]
