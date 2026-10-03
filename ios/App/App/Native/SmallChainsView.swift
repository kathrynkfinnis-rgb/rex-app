import SwiftUI

/// An item id as a sheet subject. `.sheet(item:)` wants Identifiable and
/// String isn't, and conforming String itself would reach every file in the
/// app to solve one local problem.
struct RexItemRef: Identifiable {
    let id: String
}

/// Oct 3 — "when someone Rexes something which has multiple branches eg
/// Bancone or relais d'entrecôte or mr bao (but less than 20 instances), give
/// the option to automatically Rex the others making it clear the initial rex
/// is from a particular location."
///
/// Offered after you've Rex'd one branch. Nothing is ticked to begin with:
/// this is a shortcut for someone who means it, not a default that quietly
/// turns one recommendation into five. Each copy carries a note saying which
/// branch you actually went to, because "I loved Bancone" and "I loved the
/// Covent Garden one" are different claims and only one of them is true.
struct SmallChainsView: View {
    let branches: [RexSearchHit]
    /// The branch they actually went to — named in every copy's note.
    let originalTitle: String
    let originalAddress: String?
    let rating: Double
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<String> = []
    @State private var isSaving = false
    @State private var progress: String?
    @State private var errorMessage: String?

    /// "180 Franciscan Rd, London SW17 8HG, UK" -> "Franciscan Rd". The first
    /// line of the address is what people call a branch by.
    private var originalBranchLabel: String {
        guard let originalAddress, !originalAddress.isEmpty else { return originalTitle }
        let parts = originalAddress.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.first ?? originalTitle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RexSpacing.md) {
                    Text(
                        branches.count == 1
                            ? "There's one other \(originalTitle). Rex that one too?"
                            : "There are \(branches.count) other \(originalTitle)s. Rex any of them too?"
                    )
                    .font(RexFont.text(14))
                    .foregroundStyle(RexColor.mutedForeground)

                    Text("Each one you pick gets your rating, with a note saying you went to the \(originalBranchLabel) one.")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.placeholder)

                    ForEach(branches, id: \.id) { branch in
                        Button {
                            if selected.contains(branch.id) {
                                selected.remove(branch.id)
                            } else {
                                selected.insert(branch.id)
                            }
                        } label: {
                            HStack(spacing: RexSpacing.md) {
                                Image(systemName: selected.contains(branch.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(selected.contains(branch.id) ? RexColor.primary : RexColor.mutedForeground)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(branch.address ?? branch.title)
                                        .font(RexFont.text(14, weight: .medium))
                                        .foregroundStyle(RexColor.foreground)
                                        .multilineTextAlignment(.leading)
                                    if let rating = branch.googleRating, rating > 0 {
                                        Text(String(format: "%.1f on Google", rating))
                                            .font(RexFont.text(11))
                                            .foregroundStyle(RexColor.mutedForeground)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(RexSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .rexCard()
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.destructive)
                    }

                    Button {
                        Task { await rexSelected() }
                    } label: {
                        if isSaving {
                            HStack(spacing: 6) {
                                ProgressView().tint(RexColor.primaryForeground)
                                Text(progress ?? "Adding…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text(selected.count == 1 ? "Rex this one too" : "Rex these \(selected.count) too")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(RexPrimaryButtonStyle())
                    .disabled(selected.isEmpty || isSaving)
                    .padding(.top, RexSpacing.sm)
                }
                .padding(RexSpacing.page)
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle("Other branches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }.disabled(isSaving)
                }
            }
        }
        .tint(RexColor.primary)
    }

    /// One at a time, and a failure part-way doesn't throw away what worked —
    /// same reasoning as the trip post: the person gets told what didn't go up
    /// rather than losing the lot.
    private func rexSelected() async {
        let chosen = branches.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        isSaving = true
        defer { isSaving = false; progress = nil }

        var failed: [String] = []
        for (index, branch) in chosen.enumerated() {
            progress = chosen.count > 1 ? "Adding \(index + 1) of \(chosen.count)…" : "Adding…"
            do {
                let itemId = try await RexAPI.shared.createItem(
                    type: RexCategory.place.rawValue,
                    title: branch.title,
                    subtitle: nil,
                    address: branch.address,
                    hit: branch
                )
                try await RexAPI.shared.createRecommendation(
                    itemId: itemId,
                    rating: rating,
                    note: "Same place as the \(originalBranchLabel) one, which is the branch I went to."
                )
            } catch {
                failed.append(branch.address ?? branch.title)
            }
        }

        if failed.isEmpty {
            onDone()
            dismiss()
        } else {
            errorMessage = failed.count == 1
                ? "Couldn't add \(failed[0])."
                : "Couldn't add \(failed.count) of them."
            onDone()
        }
    }
}
