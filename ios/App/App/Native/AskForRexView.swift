import SwiftUI

struct AskRoute: Hashable {}

/// "Put out a blast" — ask friends for a recommendation. Writes to `requests`,
/// the same table the web app uses, so blasts appear in both.
struct AskForRexView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var note = ""
    @State private var type: RexCategory = .place
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
                        Text("Blast sent")
                            .font(RexFont.display(24, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        Text("Your friends will see it in their feed.")
                            .font(RexFont.text(15))
                            .foregroundStyle(RexColor.mutedForeground)
                        Button("Done") { dismiss() }
                            .buttonStyle(RexPrimaryButtonStyle())
                            .padding(.top, RexSpacing.md)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, RexSpacing.xxxl)
                } else {
                    Text("Ask friends for a Rex")
                        .font(RexFont.display(30, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)

                    Text("Put out a blast — friends can chime in with suggestions.")
                        .font(RexFont.text(15))
                        .foregroundStyle(RexColor.mutedForeground)

                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("What are you after?")
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: RexSpacing.sm) {
                                ForEach(rexAllCategories, id: \.self) { c in
                                    Button { type = c } label: {
                                        Text(c.label)
                                            .font(RexFont.text(13, weight: type == c ? .semibold : .regular))
                                            .foregroundStyle(type == c ? RexColor.primaryForeground : RexColor.mutedForeground)
                                            .padding(.horizontal, RexSpacing.md)
                                            .padding(.vertical, 7)
                                            .background(type == c ? RexColor.primary : RexColor.card)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(type == c ? RexColor.primary : RexColor.border, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    VStack(alignment: .leading, spacing: RexSpacing.sm) {
                        Text("Your ask")
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        TextField("e.g. Somewhere for a birthday dinner in Soho", text: $title)
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
                        Text("Any detail? (optional)")
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.foreground)
                        TextField("Budget, area, vibe…", text: $note, axis: .vertical)
                            .font(RexFont.text(16))
                            .lineLimit(3...5)
                            .padding(RexSpacing.md)
                            .background(RexColor.card)
                            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                    .stroke(RexColor.border, lineWidth: 1)
                            )
                    }

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
                            Text("Put out the blast")
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    .disabled(isSending || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(RexSpacing.page)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        do {
            try await RexAPI.shared.createRequest(
                type: type.rawValue,
                title: title.trimmingCharacters(in: .whitespaces),
                note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
            )
            sent = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}
