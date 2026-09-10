import SwiftUI

/// Sept 10 — "an expanded and contracted view for lists and trips — the
/// expanded view is what we currently have, and the contracted view should
/// look like the edit view", with "a toggle at the top of the page to switch
/// views".
///
/// Shared by TripDetailView and ListDetailView so the two stay the same
/// shape: one preference, one toggle, one pair of compact rows. The rows are
/// drawn after TripItineraryBuilderView's — the edit view Kathryn pointed
/// at — minus the drag handles and delete buttons, since here they're links
/// through to the Rex rather than handles for rearranging it.

/// Whichever way you read trips and lists is a habit, not a per-page
/// decision, so it's remembered — and shared between the two, since a
/// person who wants trips compact wants lists compact too.
enum ItineraryViewMode {
    static let storageKey = "itineraryCompact"
}

/// The toggle itself — a two-way segmented control at the top of the page,
/// where it's seen before the content it changes rather than tucked into
/// the toolbar.
struct ItineraryViewToggle: View {
    @Binding var compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment("Expanded", systemImage: "rectangle.grid.1x2", selected: !compact) { compact = false }
            segment("Compact", systemImage: "list.bullet", selected: compact) { compact = true }
        }
        .padding(3)
        .background(RexColor.muted)
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
    }

    private func segment(_ label: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                Text(label).font(RexFont.text(13, weight: .semibold))
            }
            .foregroundStyle(selected ? RexColor.primaryForeground : RexColor.mutedForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(selected ? RexColor.primary : .clear)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A heading in the compact view — the builder's heading row: tinted box,
/// gold edge, display face.
struct CompactHeadingRow: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? "No heading" : text)
            .font(RexFont.display(15, weight: .semibold))
            .foregroundStyle(text.isEmpty ? RexColor.mutedForeground : RexColor.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RexSpacing.md)
            .padding(.vertical, RexSpacing.sm + 2)
            .background(RexColor.secondary)
            .overlay(alignment: .leading) {
                Rectangle().fill(RexColor.gold).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
    }
}

/// One stop or item in the compact view — the builder's stop row: small
/// thumbnail, name, what it is or where it is, rating.
struct CompactItemRow: View {
    let rec: FeedRecommendation

    private var category: RexCategory { RexCategory(rawType: rec.items?.type) }

    var body: some View {
        HStack(spacing: RexSpacing.sm) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(rec.items?.title ?? "Untitled")
                    .font(RexFont.text(14, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                    .lineLimit(1)
                if let detail = detailLine, !detail.isEmpty {
                    Text(detail)
                        .font(RexFont.text(11.5))
                        .foregroundStyle(RexColor.mutedForeground)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: RexSpacing.sm)

            if rec.rating > 0 {
                RexRatingBadge(raw: rec.rating, compact: true)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RexColor.placeholder)
        }
        .padding(.horizontal, RexSpacing.md)
        .padding(.vertical, RexSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                .stroke(RexColor.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    /// The same second line the builder shows — the sub-category if there
    /// is one, else where it is — falling back to the subtitle (an author,
    /// a year) for things that aren't places.
    private var detailLine: String? {
        if let genre = rec.items?.genre?.split(separator: ",").first.map({ $0.trimmingCharacters(in: .whitespaces) }),
           !genre.isEmpty {
            if let place = shortLocality(rec.items?.address) { return "\(genre) \u{00B7} \(place)" }
            return genre
        }
        return shortLocality(rec.items?.address) ?? rec.items?.subtitle
    }

    private var thumbnail: some View {
        Group {
            if let urlString = rec.photo_urls?.first ?? rec.photo_url ?? rec.items?.image_url,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        Color.clear.overlay { image.resizable().aspectRatio(contentMode: .fill) }
                    } else {
                        RexColor.muted
                    }
                }
            } else {
                RexColor.muted.overlay(
                    Image(systemName: category.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(RexColor.mutedForeground)
                )
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
