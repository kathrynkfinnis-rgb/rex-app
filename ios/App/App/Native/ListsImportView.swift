import SwiftUI

/// Entry point for #109 ("Lists" category) and native trip import
/// (#15/#38): paste in free text — Notes, a Word doc, a blog post, an
/// itinerary — and have recommendations pulled out of it automatically.
/// Nothing becomes a real Rex until ImportReviewView is confirmed.
struct ListsImportView: View {
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isExtracting = false
    @State private var errorMessage: String?
    @State private var reviewSource: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    Text("Paste in a list of recommendations \u{2014} from Notes, a Word doc, an itinerary, wherever. We'll pull out each one, with your comments kept intact, so you can check them before anything's posted.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)

                    TextEditor(text: $text)
                        .font(RexFont.text(15))
                        .frame(minHeight: 280)
                        .padding(RexSpacing.sm)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }

                    Button {
                        Task { await extract() }
                    } label: {
                        if isExtracting {
                            ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                        } else {
                            Text("Extract recommendations").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(isExtracting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Import from doc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $reviewSource) { source in
                ImportReviewView(source: source, onDone: { onDone(); dismiss() })
            }
        }
        .tint(RexColor.primary)
    }

    private func extract() async {
        isExtracting = true
        errorMessage = nil
        do {
            let items = try await RexAPI.shared.extractRecommendations(text: text)
            guard !items.isEmpty else {
                errorMessage = "Couldn't find any recommendations in that \u{2014} try adding a bit more detail."
                isExtracting = false
                return
            }
            // Unique per paste, not per user — lets fetchStagingRows pull
            // back exactly this batch on the review screen, distinct from
            // any earlier import that's still pending review.
            let source = "lists-\(Int(Date().timeIntervalSince1970))"
            try await RexAPI.shared.insertStagingRows(items, source: source)
            reviewSource = source
        } catch {
            errorMessage = error.localizedDescription
        }
        isExtracting = false
    }
}
