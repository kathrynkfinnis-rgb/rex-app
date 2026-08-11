import SwiftUI
import PhotosUI

/// Edit your display name and profile picture. The avatar shows everywhere
/// your name appears, so this is the one place it's set.
struct EditProfileView: View {
    let profile: RexProfileDetail?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var avatarURL: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: RexSpacing.xl) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            UserAvatarView(
                                url: avatarURL,
                                name: displayName.isEmpty ? (profile?.username ?? "?") : displayName,
                                size: 104
                            )
                            if isUploading {
                                Circle()
                                    .fill(.black.opacity(0.35))
                                    .frame(width: 104, height: 104)
                                    .overlay(ProgressView().tint(.white))
                            } else {
                                Circle()
                                    .fill(RexColor.primary)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(RexColor.primaryForeground)
                                    )
                                    .overlay(Circle().stroke(RexColor.background, lineWidth: 2))
                            }
                        }
                    }
                    .disabled(isUploading)
                    .padding(.top, RexSpacing.lg)

                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Display name")
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        TextField("Your name", text: $displayName)
                            .font(RexFont.text(16))
                            .padding(.horizontal, RexSpacing.lg)
                            .frame(height: 52)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                    .stroke(RexColor.border, lineWidth: 1)
                            )
                        if let username = profile?.username {
                            Text("@\(username) — your username can't be changed here.")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(RexColor.primaryForeground)
                        } else {
                            Text("Save")
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(isSaving || isUploading)

                    Spacer()
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
        .onAppear {
            displayName = profile?.display_name ?? ""
            avatarURL = profile?.avatar_url
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        errorMessage = nil
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                // Re-encode so HEIC from the camera roll uploads as something
                // every client can render.
                let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
                avatarURL = try await RexAPI.shared.uploadAvatar(data: jpeg)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isUploading = false
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            try await RexAPI.shared.updateProfile(
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                avatarURL: avatarURL
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
