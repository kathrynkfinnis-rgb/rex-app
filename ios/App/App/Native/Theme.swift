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
    // Brand — four tones, clear roles (REX Brand Guidelines).
    // Oxford Stone carries the surface, Chocolate carries text, Khaki Green
    // carries brand recognition and primary action, Oxblood is selective
    // emphasis only. Aim for large fields of stone with small, purposeful
    // areas of the rest.
    static let primary = Color(hex: "4B5320")          // Khaki Green
    static let primaryPressed = Color(hex: "3C421A")
    static let primaryForeground = Color(hex: "F5EFE6")
    static let moss = Color(hex: "6B7340")

    // Surfaces
    static let background = Color(hex: "F5EFE6")       // Oxford Stone
    static let card = Color(hex: "FFFFFF")
    static let border = Color(hex: "E3DACE")
    static let divider = Color(hex: "EDE5D9")

    // Text
    static let foreground = Color(hex: "3A2E22")       // Chocolate
    static let mutedForeground = Color(hex: "7A6A58")
    static let placeholder = Color(hex: "A89785")
    static let disabled = Color(hex: "C4B7A6")

    // Status
    static let success = Color(hex: "4B5320")
    /// Oxblood — accent and emphasis only, never the default action colour.
    static let accent = Color(hex: "6B2A2A")
    static let destructive = Color(hex: "6B2A2A")
    static let gold = Color(hex: "6B2A2A")

    // Badges
    static let badgeBackground = Color(hex: "EAE4D8")
    static let badgeForeground = Color(hex: "4B5320")

    // Kept for existing call sites.
    static let muted = Color(hex: "EDE5D9")
    static let secondary = Color(hex: "EAE4D8")
    static let secondaryForeground = Color(hex: "4B5320")
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
    /// Expressive serif — brand-led moments and short headlines only.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Neutral sans — navigation, buttons, forms, metadata, longer reading.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    // The guidelines' product scale, so screens stop picking sizes ad hoc.
    static let displayLarge = display(34, weight: .semibold)   // 32-40
    static let screenTitle  = text(26, weight: .bold)          // 24-28
    static let section      = text(19, weight: .bold)          // 18-20
    static let body         = text(16)                         // 15-17
    static let metadata     = text(12)                         // 12-13
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
