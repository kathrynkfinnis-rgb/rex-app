import SwiftUI
import PhotosUI

/// Pick photos from the library and upload them to Supabase storage.
/// Binds to the signed URLs so the parent form can post them with the Rex.
struct PhotoPickerView: View {
    @Binding var photoURLs: [String]
    var maxPhotos: Int = 6

    @State private var selection: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var errorMessage: String?

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
                        }
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
                Text("Up to \(maxPhotos) photos")
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
            }
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task { await upload(items) }
        }
    }

    private func upload(_ items: [PhotosPickerItem]) async {
        isUploading = true
        errorMessage = nil
        for item in items {
            guard photoURLs.count < maxPhotos else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                // Re-encode as JPEG so HEIC from the camera roll uploads as
                // something every client can display.
                let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8) ?? data
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
