import SwiftUI

/// Oct 12 — "can we be able to paste in a link to an insta or tiktok video and
/// pull out a Rex (e.g. recipes)."
///
/// Paste, read, review, fill in the form. Deliberately the same shape as
/// ListsImportView: nothing is saved from here. What comes back fills in the
/// Add Rex form behind it, which is where the person edits and posts it — so a
/// caption the model read badly costs a correction rather than a bad Rex.
///
/// What it can and cannot see is worth being plain about in the UI rather than
/// only in a comment, because "it didn't pick up the method" otherwise looks
/// like a bug. The caption is all there is: TikTok publishes it through oEmbed
/// and Instagram through the page's metadata, and neither hands over the
/// video, so steps that were only ever spoken aloud or shown on screen are not
/// reachable. The screen says so once, quietly, under the field.
struct LinkImportView: View {
    var onExtracted: (ExtractedLink) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var link = ""
    @State private var isReading = false
    @State private var errorMessage: String?

    private var looksSupported: Bool {
        let lower = link.lowercased()
        return lower.contains("tiktok.com") || lower.contains("instagram.com")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    TextField("Paste the link", text: $link, axis: .vertical)
                        .font(RexFont.text(15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .lineLimit(1...4)
                        .padding(RexSpacing.md)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )

                    Text("Instagram and TikTok. Rex reads the post's caption — if the recipe was only spoken out loud in the video, it won't be in there.")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }

                    Button {
                        Task { await read() }
                    } label: {
                        HStack(spacing: RexSpacing.sm) {
                            if isReading { ProgressView().tint(RexColor.primaryForeground) }
                            Text(isReading ? "Reading\u{2026}" : "Read this post")
                                .font(RexFont.text(15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, RexSpacing.md)
                        .background(RexColor.primary)
                        .foregroundStyle(RexColor.primaryForeground)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isReading || !looksSupported)
                    .opacity(isReading || !looksSupported ? 0.5 : 1)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Import from a link")
            .navigationBarTitleDisplayMode(.inline)
            .rexDismissableKeyboard()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
        .tint(RexColor.primary)
    }

    private func read() async {
        errorMessage = nil
        isReading = true
        defer { isReading = false }
        do {
            let found = try await RexAPI.shared.extractFromLink(link.trimmingCharacters(in: .whitespacesAndNewlines))
            onExtracted(found)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
