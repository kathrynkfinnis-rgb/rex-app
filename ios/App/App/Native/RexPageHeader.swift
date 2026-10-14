import SwiftUI

/// Oct 13 — the rebrand's page header, shared by item pages, trips and
/// collections.
///
/// One shape everywhere: a painted band for the category, a wavy edge where
/// the page's own ground cuts into it, and the thing's own artwork resting on
/// that edge — a book's jacket, a film's poster, a place's photo.
///
/// The artwork sits ON the band rather than beside the title, which is the one
/// decision here worth writing down. Beside it, the title gets whatever width
/// the card leaves: 212pt on a 390pt screen, and "The Correspondent" is 340pt
/// of Archivo Black at the size this design is built around. No type size
/// resolves that — one of the two has to have the width, and on a page whose
/// whole point is a heavy display face, it is the title.
///
/// Every number below is shared on purpose. The thumbnail crosses the wave on
/// every page and stops short of the title's first line on every page, so the
/// four screens line up when you flick between them.
/// Oct 14 — two bands, chosen by what the thing actually has.
///
/// "The picture should be no more than 20% of the screen. Currently looks to be
/// about 40%." It was 330pt, which on a phone is two fifths of everything
/// before you reach a word. A texture needs no more than a fifth.
///
/// "If there are uploaded photos for trips / places, please can you use those
/// in a concertina type effect… might need more space if we are doing that
/// though, perhaps 30%?" Photos earn the room; a flat pattern does not.
enum RexHeaderMetrics {
    /// A texture: one tinted pattern per category, behind the thing's own cover.
    static let bandHeight: CGFloat = 170
    static let waveHeight: CGFloat = 40
    static let sheetTop: CGFloat = 165
    /// Photographs, folded. Taller because there is something to look at.
    static let photoBandHeight: CGFloat = 250
    static let photoWaveHeight: CGFloat = 52
    static let photoSheetTop: CGFloat = 245
    /// Four panels at 390pt wide is about 95pt each. Five is too narrow to
    /// read as a photograph; the rest belong in the carousel further down.
    static let concertinaPanels = 4

    static let thumbTop: CGFloat = 52
    static let thumbWidth: CGFloat = 84
    static let thumbHeight: CGFloat = 126
    static let thumbTrailing: CGFloat = 20
}

/// The curve that separates the painting from the page.
///
/// Drawn rather than an image so it takes the page's ground colour in both
/// light and dark, and so it stretches to any width without resampling.
struct RexWaveEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: 0, y: h * 0.54))
        path.addCurve(
            to: CGPoint(x: w * 0.46, y: h * 0.32),
            control1: CGPoint(x: w * 0.15, y: h * 0.04),
            control2: CGPoint(x: w * 0.31, y: h * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.18),
            control1: CGPoint(x: w * 0.64, y: h * 0.64),
            control2: CGPoint(x: w * 0.82, y: h * 0.64)
        )
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

/// Oct 14 — "if there are uploaded photos for trips / places, please can you
/// use those in a concertina type effect."
///
/// A folded screen. Each panel turns about the edge it shares with the one
/// before it, alternating, so what sits between two panels is a hinge rather
/// than a gap — and the faces turned away from the light carry a little
/// shadow, which is the thing that makes it read as folded rather than as four
/// photographs with spaces between them.
///
/// A rotation does not change what a view claims in layout, so each panel
/// draws narrower than its slot and the dark behind shows through at the
/// seams. That is the fold, and it is why the ground is dark rather than the
/// page's own cream.
struct RexConcertinaBand: View {
    let urls: [String]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.055, green: 0.118, blue: 0.086)

            HStack(spacing: 0) {
                ForEach(Array(urls.prefix(RexHeaderMetrics.concertinaPanels).enumerated()), id: \.offset) { index, url in
                    let turnedAway = index.isMultiple(of: 2)
                    GoogleSafeAsyncImage(url: URL(string: url)!) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RexColor.muted
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: RexHeaderMetrics.photoBandHeight)
                    .clipped()
                    .overlay(Color.black.opacity(turnedAway ? 0.22 : 0))
                    .rotation3DEffect(
                        .degrees(turnedAway ? -26 : 26),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: turnedAway ? .trailing : .leading,
                        perspective: 0.42
                    )
                }
            }

            RexWaveEdge()
                .fill(RexColor.background)
                .frame(height: RexHeaderMetrics.photoWaveHeight)
        }
        .frame(height: RexHeaderMetrics.photoBandHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityLabel("Photographs of this place")
    }
}

/// The painted band plus its wavy edge. Callers overlay their own thumbnail
/// and back button, because what sits on the band differs per page.
struct RexBannerBand: View {
    let category: RexCategory

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(category.bannerImageName)
                .resizable()
                // The paintings are 3:2 and the band is taller than it is
                // wide for its width, so filling crops the sides evenly and
                // keeps the middle of the scene — which is where the dinosaur
                // is hidden in every one of them.
                .aspectRatio(contentMode: .fill)
                .frame(width: UIScreen.main.bounds.width, height: RexHeaderMetrics.bandHeight)
                .clipped()

            RexWaveEdge()
                .fill(RexColor.background)
                .frame(height: RexHeaderMetrics.waveHeight)
        }
        .frame(height: RexHeaderMetrics.bandHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The artwork resting on the band's edge: a jacket, a poster, a photo.
///
/// Falls back to the category's own symbol on a tinted ground rather than an
/// empty rectangle — plenty of things people Rex have no picture, and a hole
/// where the artwork goes reads as broken rather than as absent.
struct RexHeaderThumbnail: View {
    let url: String?
    let category: RexCategory

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: RexHeaderMetrics.thumbWidth, height: RexHeaderMetrics.thumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.28), radius: 13, x: 0, y: 8)
    }

    private var placeholder: some View {
        ZStack {
            RexColor.badgeBackground
            Image(systemName: category.symbol)
                .font(.system(size: 30))
                .foregroundStyle(RexColor.primary)
        }
    }
}

/// The small capitalised label that says what kind of thing this is.
struct RexCategoryPill: View {
    let category: RexCategory

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: category.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(category.label.uppercased())
                .font(RexFont.text(11, weight: .bold))
                .tracking(1.1)
        }
        .foregroundStyle(RexColor.primary)
        .padding(.leading, 11)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .background(RexColor.badgeBackground, in: Capsule())
    }
}
