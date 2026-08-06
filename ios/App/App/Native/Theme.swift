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

/// Ported from src/styles.css :root (oklch -> sRGB), same palette the web app uses.
enum RexColor {
    static let background = Color(hex: "F8F3F0")
    static let foreground = Color(hex: "122413")
    static let card = Color(hex: "FFFFFF")
    static let primary = Color(hex: "58994A")
    static let primaryForeground = Color(hex: "FAFBF2")
    static let secondary = Color(hex: "E2EDD0")
    static let secondaryForeground = Color(hex: "1D341E")
    static let muted = Color(hex: "E8EFD8")
    static let mutedForeground = Color(hex: "556252")
    static let accent = Color(hex: "C99B5A")
    static let destructive = Color(hex: "DF2225")
    static let border = Color(hex: "D1DDC0")
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
