import SwiftUI
import PhotosUI

/// Edit your display name and profile picture. The avatar shows everywhere
/// your name appears, so this is the one place it's set.
struct EditProfileView: View {
    let profile: RexProfileDetail?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    /// Sept 14 — usernames were fixed at whatever sign-up generated; now
    /// they can be changed here, the same way the first-run screen sets one.
    @State private var username = ""
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
                    }

                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Username")
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        HStack(spacing: 2) {
                            Text("@").foregroundStyle(RexColor.mutedForeground)
                            TextField("username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: username) { _, new in
                                    let cleaned = new.lowercased().replacingOccurrences(of: " ", with: "_")
                                    if cleaned != new { username = cleaned }
                                }
                        }
                        .font(RexFont.text(16))
                        .padding(.horizontal, RexSpacing.lg)
                        .frame(height: 52)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                        Text(usernameProblem ?? "Friends can find you by this or your name.")
                            .font(RexFont.text(12))
                            .foregroundStyle(usernameProblem == nil ? RexColor.mutedForeground : RexColor.destructive)
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
                    .disabled(isSaving || isUploading || usernameProblem != nil)

                    Spacer()
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Edit profile")
            .rexDismissableKeyboard()
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
            username = profile?.username ?? ""
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private var usernameProblem: String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        if username.count < 3 { return "At least 3 characters." }
        if username.count > 20 { return "20 characters at most." }
        if username.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Letters, numbers and underscores only."
        }
        return nil
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        errorMessage = nil
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                // Avatars render at most ~104pt — 600px is plenty.
                let jpeg = downscaledJPEG(data, maxDimension: 600)
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
            if username != profile?.username {
                try await RexAPI.shared.claimUsername(username, displayName: nil)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
