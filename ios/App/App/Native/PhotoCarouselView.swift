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

    @State private var index = 0
    @State private var showingFullScreen = false

    var body: some View {
        if !urls.isEmpty {
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
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .contentShape(Rectangle())
                    .onTapGesture { showingFullScreen = true }

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
