import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Oct 3 — drag a photo onto another to reorder. Same shape as the itinerary
/// builder's ReorderDropDelegate, kept separate rather than generalised
/// because that one moves ItineraryEntry rows and this one moves strings.
private struct PhotoReorderDropDelegate: DropDelegate {
    let target: String
    @Binding var photoURLs: [String]
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = photoURLs.firstIndex(of: dragging),
              let to = photoURLs.firstIndex(of: target)
        else { return }
        withAnimation(.snappy) {
            photoURLs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Pick photos from the library and upload them to Supabase storage.
/// Binds to the signed URLs so the parent form can post them with the Rex.
struct PhotoPickerView: View {
    @Binding var photoURLs: [String]
    var maxPhotos: Int = 6

    @State private var selection: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var errorMessage: String?
    /// Which photo is being dragged, for the reorder.
    @State private var dragging: String?
    /// Oct 3 — the photo currently open in the cropper.
    @State private var cropping: CroppingPhoto?

    /// The cropper needs both the full-resolution image and the URL it came
    /// from, so the result can be swapped into the same slot.
    private struct CroppingPhoto: Identifiable {
        let url: String
        let image: UIImage
        var id: String { url }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: RexSpacing.sm) {
                    ForEach(photoURLs, id: \.self) { url in
                        ZStack(alignment: .topTrailing) {
                            AsyncImage(url: URL(string: url)) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    RexColor.muted
                                }
                            }
                            .frame(width: 78, height: 78)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))

                            Button {
                                photoURLs.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .padding(4)

                            // Oct 3 — "on the cover photo: allow zoom/crop."
                            // A cover is shown in a fixed frame, so a photo
                            // that isn't that shape gets centre-cropped by the
                            // layout and the subject is as likely as not cut
                            // out of it. This decides which part survives.
                            Button {
                                Task { await beginCrop(url) }
                            } label: {
                                Image(systemName: "crop")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(5)
                                    .background(.black.opacity(0.55), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                            .frame(width: 78, height: 78, alignment: .bottomTrailing)

                            // Oct 3 — "Photos can't be reordered after
                            // upload." The first photo is the one the card
                            // leads with, so the order is a real decision and
                            // the only way to change it was to delete
                            // everything and upload again in the right order.
                            if photoURLs.first == url, photoURLs.count > 1 {
                                Text("Cover")
                                    .font(RexFont.text(9, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(.black.opacity(0.55))
                                    .clipShape(Capsule())
                                    .padding(4)
                                    .frame(width: 78, height: 78, alignment: .bottomLeading)
                            }
                        }
                        .opacity(dragging == url ? 0.4 : 1)
                        .onDrag {
                            dragging = url
                            return NSItemProvider(object: url as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: PhotoReorderDropDelegate(
                                target: url,
                                photoURLs: $photoURLs,
                                dragging: $dragging
                            )
                        )
                    }

                    if photoURLs.count < maxPhotos {
                        PhotosPicker(
                            selection: $selection,
                            maxSelectionCount: maxPhotos - photoURLs.count,
                            matching: .images
                        ) {
                            VStack(spacing: RexSpacing.xs) {
                                if isUploading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "camera")
                                        .font(.system(size: 18))
                                        .foregroundStyle(RexColor.mutedForeground)
                                    Text("Add photo")
                                        .font(RexFont.text(11))
                                        .foregroundStyle(RexColor.mutedForeground)
                                }
                            }
                            .frame(width: 78, height: 78)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                    .strokeBorder(RexColor.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                        }
                        .disabled(isUploading)
                    }
                }
                .padding(.horizontal, 1)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.destructive)
            } else {
                Text(
                    maxPhotos == 1
                        ? "One photo"
                        : photoURLs.count > 1
                            ? "Up to \(maxPhotos) photos \u{2014} drag to reorder, the first is the cover"
                            : "Up to \(maxPhotos) photos"
                )
                .font(RexFont.text(11))
                .foregroundStyle(RexColor.mutedForeground)
            }
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task { await upload(items) }
        }
        .sheet(item: $cropping) { photo in
            PhotoCropView(image: photo.image) { cropped in
                Task { await replace(photo.url, with: cropped) }
            }
        }
    }

    /// Fetches the photo back so it can be cropped at full resolution rather
    /// than at the 78pt the picker draws it. The crop replaces the photo in
    /// place — same position in the list, so a cover stays the cover.
    private func beginCrop(_ url: String) async {
        guard let remote = URL(string: url) else { return }
        isUploading = true
        defer { isUploading = false }
        guard let (data, _) = try? await URLSession.shared.data(from: remote),
              let image = UIImage(data: data) else {
            errorMessage = "Couldn't open that photo to adjust it."
            return
        }
        cropping = CroppingPhoto(url: url, image: image)
    }

    /// Uploads the cropped version and swaps it in. A new upload rather than
    /// an overwrite, so anything already pointing at the old file — a Rex
    /// posted earlier from the same photo — keeps working.
    private func replace(_ url: String, with image: UIImage) async {
        guard let index = photoURLs.firstIndex(of: url) else { return }
        isUploading = true
        defer { isUploading = false }
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else { return }
        do {
            let uploaded = try await RexAPI.shared.uploadPhoto(data: jpeg, fileExtension: "jpg")
            photoURLs[index] = uploaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upload(_ items: [PhotosPickerItem]) async {
        isUploading = true
        errorMessage = nil
        for item in items {
            guard photoURLs.count < maxPhotos else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let jpeg = downscaledJPEG(data)
                let url = try await RexAPI.shared.uploadPhoto(data: jpeg, fileExtension: "jpg")
                photoURLs.append(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        selection = []
        isUploading = false
    }
}
