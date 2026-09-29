import SwiftUI

/// Sept 29 — what Talk to Rex has worked out about you, in one list you can
/// delete from.
///
/// This exists because the alternative is indefensible. Rex writes down what
/// it infers — "two kids", "won't start a long film on a weeknight" — and uses
/// it to shape every later answer. Somebody who can't see that list can't
/// correct it, can't disagree with it, and has no way of knowing why the
/// suggestions changed. Storing it invisibly would be the version of this
/// feature nobody would defend once asked about it directly.
///
/// So: plain sentences, in the order they were last useful, each deletable.
/// Facts are readable by their owner alone — not even friends — because what
/// gets inferred about you is more revealing than anything you chose to post.
struct RexMemoryRoute: Hashable {}

struct RexMemoryView: View {
    @State private var facts: [RexFact] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deleting: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RexSpacing.lg) {
                explainer

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, RexSpacing.xl)
                } else if facts.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                            if index > 0 { Divider().padding(.leading, RexSpacing.md) }
                            factRow(fact)
                        }
                    }
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RexRadius.card, style: .continuous)
                            .stroke(RexColor.border, lineWidth: 1)
                    )

                    Text("Deleting a line means Rex stops using it. It may work the same thing out again from something you ask later.")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                }
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.vertical, RexSpacing.lg)
        }
        .background(RexColor.background.ignoresSafeArea())
        .navigationTitle("What Rex remembers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text("When you talk to Rex, it keeps a short list of things that seem worth remembering — so you don't have to say them twice.")
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.foreground.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Text("It keeps facts, not conversations. Nobody else can see this list, including your friends.")
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 26))
                .foregroundStyle(RexColor.mutedForeground)
            Text("Nothing yet")
                .font(RexFont.display(18, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text("Ask Rex for a few recommendations and anything worth keeping will show up here.")
                .font(RexFont.text(14))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, RexSpacing.xl)
    }

    private func factRow(_ fact: RexFact) -> some View {
        HStack(alignment: .top, spacing: RexSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fact.fact)
                    .font(RexFont.text(15))
                    .foregroundStyle(RexColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                // The difference matters to someone deciding whether to
                // delete it: "you told me" is a quote, "I noticed" is a guess
                // and guesses are the ones worth checking.
                Text(fact.source == "stated" ? "You told Rex this" : "Rex worked this out")
                    .font(RexFont.text(11))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            Spacer(minLength: 0)

            Button {
                Task { await forget(fact) }
            } label: {
                if deleting.contains(fact.id) {
                    ProgressView().scaleEffect(0.7).frame(width: 22, height: 22)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RexColor.mutedForeground)
                        .frame(width: 22, height: 22)
                        .background(RexColor.muted)
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(deleting.contains(fact.id))
            .accessibilityLabel("Forget: \(fact.fact)")
        }
        .padding(RexSpacing.md)
    }

    private func load() async {
        isLoading = true
        do {
            facts = try await RexAPI.shared.fetchRexFacts()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func forget(_ fact: RexFact) async {
        deleting.insert(fact.id)
        do {
            try await RexAPI.shared.deleteRexFact(id: fact.id)
            facts.removeAll { $0.id == fact.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        deleting.remove(fact.id)
    }
}
