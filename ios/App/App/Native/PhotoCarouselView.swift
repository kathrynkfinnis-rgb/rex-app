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
                                image.resizable().aspectRatio(contentMode: .fill)
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
        }
    }
}
