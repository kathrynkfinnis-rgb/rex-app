import SwiftUI

/// #102 (Gemma) — tapping the REX wordmark shows this, a small "what is
/// this app" overlay for while general awareness of REX is still low.
/// Deliberately brief: a logo tap should answer the question in one glance,
/// not turn into a whole screen.
struct RexExplainerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.lg) {
            Image("RexWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .accessibilityLabel("REX")

            Text("Recommendations from people you actually trust.")
                .font(RexFont.display(24, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: RexSpacing.md) {
                explainerRow(icon: "person.2", text: "Friends share what they've actually read, watched, eaten and been to \u{2014} not an algorithm's guess.")
                explainerRow(icon: "checkmark.seal", text: "Every recommendation is rated 1\u{2013}5 by someone you know, with their own take on it.")
                explainerRow(icon: "bookmark", text: "Save what catches your eye into collections, or start a trip and build it out stop by stop.")
            }

            Spacer(minLength: 0)

            Button("Got it") { dismiss() }
                .buttonStyle(RexPrimaryButtonStyle())
        }
        .padding(RexSpacing.page)
        .padding(.top, RexSpacing.md)
        .background(RexColor.background.ignoresSafeArea())
    }

    private func explainerRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: RexSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RexColor.primary)
                .frame(width: 22)
                .padding(.top, 1)
            Text(text)
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
