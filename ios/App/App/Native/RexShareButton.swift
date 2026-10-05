import SwiftUI
import UIKit

/// Oct 5 — "and can we truncate the link?"
///
/// A share used to be a `ShareLink`, which needs its URL the moment the card
/// is drawn. A short code can't be known then without asking the server for
/// one per card you scroll past — which would mint codes for everything
/// nobody shares. So this is a Button instead: it asks for the code when you
/// tap, then opens the share sheet.
///
/// If the code doesn't come back — offline, or the 5 October migration hasn't
/// run — it shares the full-length link rather than nothing. A long link
/// works; a share that silently does nothing does not.
struct RexShareButton<Label: View>: View {
    /// 'rec', 'trip', 'want' or 'list' — matches share_links.kind.
    let kind: String
    let targetId: String
    /// Where this points without a short code.
    let fallbackURL: URL
    /// The words above the link. RexShareLink.message builds these.
    let message: String
    @ViewBuilder var label: () -> Label

    @State private var payload: SharePayload?
    @State private var minting = false

    var body: some View {
        Button {
            Task { await share() }
        } label: {
            if minting {
                ProgressView()
                    .controlSize(.small)
                    .tint(RexColor.mutedForeground)
            } else {
                label()
            }
        }
        .buttonStyle(.plain)
        .disabled(minting)
        .sheet(item: $payload) { ActivitySheet(payload: $0) }
    }

    private func share() async {
        minting = true
        let short = await RexAPI.shared.shareCode(kind: kind, targetId: targetId)
        minting = false
        let url = short.flatMap(RexShareLink.shortURL(code:)) ?? fallbackURL
        payload = SharePayload(message: message, url: url)
    }
}

struct SharePayload: Identifiable {
    let message: String
    let url: URL
    var id: String { url.absoluteString }
}

/// UIActivityViewController, because SwiftUI's own share sheet is ShareLink
/// and ShareLink can't be handed its item late. Message and URL go in as two
/// activity items, which is what ShareLink(item:message:) does — WhatsApp
/// puts the words first and the link under them.
private struct ActivitySheet: UIViewControllerRepresentable {
    let payload: SharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [payload.message, payload.url],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
