import SwiftUI

/// Swipeable photo carousel with page dots, mirroring the web PhotoCarousel.
/// Renders nothing when there are no photos.
struct PhotoCarouselView: View {
    let urls: [String]
    var height: CGFloat = 220
    var cornerRadius: CGFloat = RexRadius.card

    @State private var index = 0

    var body: some View {
        if !urls.isEmpty {
            ZStack(alignment: .bottom) {
                TabView(selection: $index) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { i, url in
                        AsyncImage(url: URL(string: url)) { phase in
                            if let image = phase.image {
                                // Was .fill — a portrait photo in this wide,
                                // fixed-height strip meant scaling up to
                                // cover the full width, which pushed a
                                // sizeable chunk (often what read as "the
                                // bottom third") outside the frame and
                                // straight into .clipped()'s crop. .fit
                                // shows the whole photo, letterboxed on
                                // RexColor.muted rather than cropped.
                                RexColor.muted.overlay(
                                    image.resizable().aspectRatio(contentMode: .fit)
                                )
                            } else if phase.error != nil {
                                RexColor.muted.overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(RexColor.mutedForeground)
                                )
                            } else {
                                RexColor.muted.overlay(ProgressView().controlSize(.small))
                            }
                        }
                        .clipped()
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Only worth showing dots when there's more than one photo.
                if urls.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<urls.count, id: \.self) { i in
                            Circle()
                                .fill(i == index ? Color.white : Color.white.opacity(0.45))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, RexSpacing.md)
                    .padding(.vertical, RexSpacing.sm)
                    .background(.black.opacity(0.25), in: Capsule())
                    .padding(.bottom, RexSpacing.md)
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // "You can no longer swipe through the carousel photos on a
            // card because it takes you to delete when you swipe right" —
            // SwipeToRemove already has a full exclusion-zone mechanism
            // built specifically for this (#120/#111, see its own doc
            // comment), this view just never actually called it, so the
            // zone it reads was always nil and every carousel swipe still
            // went to the card's delete action instead of paging.
            .swipeToRemoveExclusionZone()
        }
    }
}
