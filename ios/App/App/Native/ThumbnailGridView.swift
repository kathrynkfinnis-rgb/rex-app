import SwiftUI

/// A 2x2 collage of up to 4 photo URLs, used anywhere a collection needs a
/// preview of what's inside it without opening it — originally CollectionsView's
/// own-collections/friends'-collections shelf tiles, now also Explore's
/// "Missed from your friends" cards (#131) — same visual language wherever a
/// list of Rex needs a preview rather than its own single cover image.
struct ThumbnailGridView: View {
    let urls: [String]

    var body: some View {
        let cells = Array(urls.prefix(4))
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                cell(cells.count > 0 ? cells[0] : nil)
                cell(cells.count > 1 ? cells[1] : nil)
            }
            GridRow {
                cell(cells.count > 2 ? cells[2] : nil)
                cell(cells.count > 3 ? cells[3] : nil)
            }
        }
        .background(RexColor.muted)
    }

    @ViewBuilder
    private func cell(_ url: String?) -> some View {
        Group {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else { RexColor.muted }
                }
            } else {
                RexColor.muted
            }
        }
        // Fills whatever size the caller constrains the whole grid to
        // (.frame on ThumbnailGridView itself) rather than a fixed cell
        // size, so this works for both CollectionsView's square 128x128
        // tiles and Explore's non-square 132x96 cards.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
