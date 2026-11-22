import SwiftUI

/// Swipeable photo carousel with page dots, mirroring the web PhotoCarousel.
/// Renders nothing when there are no photos.
///
/// Sept 1 — "I prefer the picture thing before where it was a square for
/// portrait photos and then maybe you see the full photo when you click
/// into": back to a square crop (was briefly .fit/letterboxed — see the old
/// comment this replaced, kept below for context) plus a tap now opens
/// PhotoFullScreenView so the complete, uncropped photo is still one tap
/// away rather than genuinely lost.
struct PhotoCarouselView: View {
    let urls: [String]
    var cornerRadius: CGFloat = RexRadius.card
    /// Nov 22 — "user uploaded photos being the first images, then the map
    /// being the last thing in the carousel."
    ///
    /// The map used to be an alternative to the photos: a card showed one or
    /// the other, and a place somebody had photographed never showed where it
    /// was. One carousel holds both now, the photographs first because they
    /// are what people stop to look at, and the map last as the answer to
    /// "but where is it".
    ///
    /// AnyView rather than a generic parameter on purpose — this view is
    /// constructed in a dozen places that have no trailing page, and making
    /// it generic would put a type parameter on every one of them.
    var trailingPage: AnyView? = nil

    @State private var index = 0
    @State private var showingFullScreen = false

    /// How many pages the carousel has, photos plus the map if there is one.
    private var pageCount: Int { urls.count + (trailingPage == nil ? 0 : 1) }

    var body: some View {
        if urls.isEmpty, let trailingPage {
            // Nothing to swipe through — just the map, at whatever height it
            // asks for. This is the old map-only card, unchanged.
            trailingPage
        } else if !urls.isEmpty {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    TabView(selection: $index) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { i, url in
                            AsyncImage(url: URL(string: url)) { phase in
                                if let image = phase.image {
                                    // Square crop, same as a grid tile —
                                    // .fill rather than .fit (which used to
                                    // letterbox/pillarbox a photo whose
                                    // aspect ratio didn't match the frame,
                                    // wasting space and reading as "why is
                                    // there a grey bar"). Tapping opens the
                                    // full, uncropped photo instead.
                                    RexColor.muted.overlay(
                                        image.resizable().aspectRatio(contentMode: .fill)
                                            .frame(width: geo.size.width, height: geo.size.width)
                                            .clipped()
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
                        if let trailingPage {
                            trailingPage
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .tag(urls.count)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // The map page is not a photograph, so a tap on it
                        // should not open the full-screen photo viewer with
                        // nothing in it. The map carries its own tap.
                        if index < urls.count { showingFullScreen = true }
                    }

                    // Only worth showing dots when there's more than one photo.
                    if pageCount > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<pageCount, id: \.self) { i in
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
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // "You can no longer swipe through the carousel photos on a
            // card because it takes you to delete when you swipe right" —
            // SwipeToRemove already has a full exclusion-zone mechanism
            // built specifically for this (#120/#111, see its own doc
            // comment), this view just never actually called it, so the
            // zone it reads was always nil and every carousel swipe still
            // went to the card's delete action instead of paging.
            .swipeToRemoveExclusionZone()
            .fullScreenCover(isPresented: $showingFullScreen) {
                PhotoFullScreenView(urls: urls, initialIndex: index)
            }
        }
    }
}
