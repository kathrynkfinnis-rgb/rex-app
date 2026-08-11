import SwiftUI

struct FeedbackRoute: Hashable {}

/// Send feedback, anonymously by default. Anonymous submissions store no
/// user id at all, so they genuinely can't be traced back.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var anonymous = true
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                if sent {
                    VStack(spacing: RexSpacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(RexColor.primary)
                        Text("Thank you")
                            .font(RexFont.display(24, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text("That's gone straight to the team.")
                            .font(RexFont.text(15))
                            .foregroundStyle(RexColor.mutedForeground)
                        Button("Done") { dismiss() }
                            .buttonStyle(RexPrimaryButtonStyle())
                            .padding(.top, RexSpacing.md)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, RexSpacing.xxxl)
                } else {
                    Text("Tell us anything")
                        .font(RexFont.display(30, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)

                    Text("Bugs, ideas, things that annoyed you — all of it helps.")
                        .font(RexFont.text(15))
                        .foregroundStyle(RexColor.mutedForeground)

                    TextEditor(text: $message)
                        .font(RexFont.text(16))
                        .frame(height: 180)
                        .padding(RexSpacing.sm)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )

                    Toggle(isOn: $anonymous) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send anonymously")
                                .font(RexFont.text(15, weight: .medium))
                                .foregroundStyle(RexColor.foreground)
                            Text(anonymous
                                 ? "We won't know it was you."
                                 : "Your name will be attached, so we can follow up.")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }
                    .tint(RexColor.primary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }

                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().tint(RexColor.primaryForeground)
                        } else {
                            Text("Send")
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .opacity(message.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    .disabled(isSending || message.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        do {
            try await RexAPI.shared.sendFeedback(
                message: message.trimmingCharacters(in: .whitespaces),
                anonymous: anonymous,
                page: "feed"
            )
            sent = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
