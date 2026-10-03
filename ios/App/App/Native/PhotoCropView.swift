import SwiftUI

/// Oct 3 — "on the cover photo: allow zoom/crop."
///
/// A cover is shown in a fixed frame, so a photo that isn't that shape gets
/// centre-cropped by the layout and the subject is as likely as not to be cut
/// out of it. This decides which part survives, rather than leaving it to
/// `scaledToFill`.
///
/// Deliberately not a general-purpose editor. Pan and zoom, one aspect ratio,
/// and the result is what you see inside the frame — no filters, no rotation,
/// nothing that needs explaining.
struct PhotoCropView: View {
    let image: UIImage
    /// 4:3 matches the cover frames on the card and the list page. Square
    /// would crop more away for no gain, since nothing displays it square.
    var aspect: CGFloat = 4.0 / 3.0
    var onCropped: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let frameWidth = geometry.size.width
                let frameHeight = frameWidth / aspect

                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: frameWidth, height: frameHeight)
                        .scaleEffect(scale)
                        .offset(offset)
                        .clipped()
                        .frame(width: frameWidth, height: frameHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        // Clamped: zooming below 1 would show
                                        // bars where the photo has run out.
                                        scale = min(max(lastScale * value, 1), 5)
                                    }
                                    .onEnded { _ in lastScale = scale },
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        offset = clamped(offset, frame: CGSize(width: frameWidth, height: frameHeight))
                                        lastOffset = offset
                                    }
                            )
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use") {
                        onCropped(cropped())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(RexColor.primary)
    }

    /// Stops the photo being dragged off its own frame, which otherwise leaves
    /// a black wedge in the saved crop.
    private func clamped(_ proposed: CGSize, frame: CGSize) -> CGSize {
        let slackX = max(0, (frame.width * scale - frame.width) / 2)
        let slackY = max(0, (frame.height * scale - frame.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -slackX), slackX),
            height: min(max(proposed.height, -slackY), slackY)
        )
    }

    /// Reproduces on the full-resolution image what the frame is showing.
    /// Everything is expressed as a fraction of the displayed frame, so the
    /// result doesn't depend on the screen it was cropped on.
    private func cropped() -> UIImage {
        let source = image.size
        guard source.width > 0, source.height > 0 else { return image }

        // scaledToFill inside a 4:3 frame: the photo is already cropped to the
        // frame's aspect before any of the gestures apply.
        let sourceAspect = source.width / source.height
        var visible = source
        if sourceAspect > aspect {
            visible.width = source.height * aspect
        } else {
            visible.height = source.width / aspect
        }

        // Zoom shrinks the visible window; drag moves it.
        let windowWidth = visible.width / scale
        let windowHeight = visible.height / scale
        let centreX = source.width / 2 - (offset.width / (visible.width * scale)) * visible.width
        let centreY = source.height / 2 - (offset.height / (visible.height * scale)) * visible.height

        var rect = CGRect(
            x: centreX - windowWidth / 2,
            y: centreY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )
        // Keep the rectangle inside the image whatever the gestures did.
        rect.origin.x = min(max(rect.origin.x, 0), source.width - rect.width)
        rect.origin.y = min(max(rect.origin.y, 0), source.height - rect.height)

        guard let cgImage = image.cgImage else { return image }
        let scaleFactor = CGFloat(cgImage.width) / source.width
        let pixelRect = CGRect(
            x: rect.origin.x * scaleFactor,
            y: rect.origin.y * scaleFactor,
            width: rect.width * scaleFactor,
            height: rect.height * scaleFactor
        ).integral

        guard let cropped = cgImage.cropping(to: pixelRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
