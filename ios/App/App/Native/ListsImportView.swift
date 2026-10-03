import SwiftUI
import UniformTypeIdentifiers

/// Entry point for #109 ("Lists" category) and native trip import
/// (#15/#38): choose a document — or paste free text — and have
/// recommendations pulled out of it automatically. Nothing becomes a real Rex
/// until ImportReviewView is confirmed.
///
/// Oct 3 — "want to be able to upload eg. a word doc". This screen has always
/// said "from Notes, a Word doc, an itinerary, wherever" and then offered
/// nowhere to put the Word doc; the only route in was select-all-and-paste,
/// which works in Notes and not in Files. RexDocumentText reads the document
/// on the phone and fills the box below, so the text is still shown and
/// editable before anything is sent anywhere.
struct ListsImportView: View {
    var onDone: () -> Void
    /// Passed straight through to ImportReviewView — see its own doc.
    var onExtractedAsTrip: ((String, [ItineraryEntry]) -> Void)? = nil
    var onExtractedAsList: ((String, String, [ItineraryEntry]) -> Void)? = nil
    /// Passed straight through — see ImportReviewView.intoCollection.
    var intoCollection: (id: String, name: String)? = nil
    /// Sept 10 — set from the list form only: hands the pasted text back to
    /// become the list's Notes, for a document that's commentary rather
    /// than a set of things.
    var onUseAsNotes: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isExtracting = false
    @State private var errorMessage: String?
    @State private var reviewSource: String?
    @State private var choosingFile = false
    @State private var isReadingFile = false
    /// The document the text in the box came from, so it's obvious the import
    /// worked and which file is sitting there.
    @State private var importedFileName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.lg) {
                    Text("Choose a document, or paste a list of recommendations in \u{2014} from Notes, a Word doc, an itinerary, wherever. We'll pull out each one, with your comments kept intact, so you can check them before anything's posted.")
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.mutedForeground)
                    // Same disclosure as recipe photo import.
                    Text("The text is sent to our AI provider (Anthropic) to pick out the recommendations. Rex keeps only what you choose to save.")
                        .font(RexFont.text(11.5))
                        .foregroundStyle(RexColor.mutedForeground)

                    VStack(alignment: .leading, spacing: RexSpacing.xs) {
                        Button {
                            choosingFile = true
                        } label: {
                            if isReadingFile {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label(
                                    importedFileName == nil ? "Choose a document" : "Choose a different document",
                                    systemImage: "doc.text"
                                )
                                .font(RexFont.text(13.5, weight: .semibold))
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(RexSecondaryButtonStyle())
                        .disabled(isReadingFile || isExtracting)

                        if let importedFileName {
                            Label(
                                "Read from \(importedFileName) \u{2014} have a look over it below, then extract.",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                        } else {
                            Text("Word, Pages, PDF, rich text or plain text.")
                                .font(RexFont.text(12))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                    }

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

                    if let onUseAsNotes {
                        Button {
                            onUseAsNotes(text)
                            dismiss()
                        } label: {
                            Text("Add it to the list\u{2019}s notes instead")
                                .font(RexFont.text(14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(RexColor.primary)
                        .disabled(isExtracting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("For a document that's mostly commentary — it goes into the Notes box as it is, rather than being split into items.")
                            .font(RexFont.text(12))
                            .foregroundStyle(RexColor.mutedForeground)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .fileImporter(
                isPresented: $choosingFile,
                allowedContentTypes: RexDocumentText.readableTypes
            ) { result in
                load(result)
            }
            .navigationTitle("Import from doc")
            .rexDismissableKeyboard()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $reviewSource) { source in
                ImportReviewView(
                    source: source,
                    onDone: { onDone(); dismiss() },
                    onExtractedAsTrip: onExtractedAsTrip.map { handler in
                        { name, entries in dismiss(); handler(name, entries) }
                    },
                    onExtractedAsList: onExtractedAsList.map { handler in
                        { name, kind, entries in dismiss(); handler(name, kind, entries) }
                    },
                    intoCollection: intoCollection
                )
            }
        }
        .tint(RexColor.primary)
    }

    /// Reading happens off the main thread: unzipping a .docx is quick, but
    /// PDFKit pulling the text out of a long PDF is not, and it shouldn't
    /// freeze the screen it was started from.
    private func load(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            isReadingFile = true
            errorMessage = nil
            Task {
                let outcome = await Task.detached {
                    Result { try RexDocumentText.extract(from: url) }
                }.value
                isReadingFile = false
                switch outcome {
                case .success(let extracted):
                    text = extracted
                    importedFileName = url.lastPathComponent
                case .failure(let error):
                    importedFileName = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func extract() async {
        isExtracting = true
        errorMessage = nil
        do {
            let items = try await RexAPI.shared.extractRecommendations(text: text)
            guard !items.isEmpty else {
                errorMessage = onUseAsNotes == nil
                    ? "Couldn't find any recommendations in that \u{2014} try adding a bit more detail."
                    : "Couldn't pick out separate items in that \u{2014} you can add it to the list\u{2019}s notes instead."
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
