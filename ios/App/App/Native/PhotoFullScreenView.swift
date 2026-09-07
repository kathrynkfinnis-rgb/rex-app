import SwiftUI

/// "I prefer the picture thing before where it was a square for portrait
/// photos and then maybe you see the full photo when you click into" —
/// PhotoCarouselView went back to a square crop (see its own doc comment)
/// specifically so this exists: tapping a cropped tile opens the complete,
/// uncropped photo here instead of nothing at all.
struct PhotoFullScreenView: View {
    let urls: [String]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(urls: [String], initialIndex: Int) {
        self.urls = urls
        self.initialIndex = initialIndex
        _index = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, url in
                    ZoomableImage(url: url)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .always : .never))

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .padding(.trailing, RexSpacing.page)
                    .padding(.top, RexSpacing.sm)
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }
}

/// Pinch to zoom, drag to pan while zoomed, double-tap to toggle — the same
/// basic gesture set every photo viewer offers. Resets on a new image
/// (SwiftUI reuses gesture state per identity via .tag, so a fresh id each
/// time isn't needed here — TabView already recreates this per page).
private struct ZoomableImage: View {
    let url: String

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: URL(string: url)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1, min(lastScale * value, 5))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale == 1 { withAnimation(.snappy) { offset = .zero; lastOffset = .zero } }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.snappy) {
                                if scale > 1 {
                                    scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                                } else {
                                    scale = 2.5; lastScale = 2.5
                                }
                            }
                        }
                } else if phase.error != nil {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ProgressView().tint(.white)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
    }
}
