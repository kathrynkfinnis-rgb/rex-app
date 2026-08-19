import SwiftUI

/// #102 (Phoebe) — after signup, ask a couple of quick questions instead of
/// dropping straight into an empty feed. Two steps: what you're into, then
/// find some friends (REX is only as good as the people in it, and a feed
/// with nobody followed is the worst possible first impression).
///
/// Shown once per account — RootView gates this on a per-user-id UserDefaults
/// flag, not tied to "is this literally a brand-new signup", so it behaves
/// sensibly on every sign-in path (email, Apple) without LoginView needing
/// to thread a separate "just signed up" signal through.
struct OnboardingView: View {
    var onDone: () -> Void

    private enum Step { case interests, findFriends }

    @State private var step: Step = .interests
    @State private var selected: Set<RexCategory> = []
    @State private var isSaving = false

    private let interestOptions: [RexCategory] = [
        .place, .trip, .book, .movie, .tv, .podcast, .recipe, .event,
    ]

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .interests: interestsStep
                case .findFriends: findFriendsStep
                }
            }
            .background(RexColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { advance() }
                        .font(RexFont.text(14, weight: .semibold))
                        .foregroundStyle(RexColor.mutedForeground)
                }
            }
        }
        .tint(RexColor.primary)
    }

    private var interestsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                Text("What are you into?")
                    .font(RexFont.display(28, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Text("Pick a few \u{2014} we'll use it to shape what you see first. You can change this anytime.")
                    .font(RexFont.text(15))
                    .foregroundStyle(RexColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.top, RexSpacing.lg)
            .padding(.bottom, RexSpacing.xl)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: RexSpacing.sm) {
                    ForEach(interestOptions, id: \.self) { category in
                        interestTile(category)
                    }
                }
                .padding(.horizontal, RexSpacing.page)
            }

            Button {
                Task { await saveInterestsAndAdvance() }
            } label: {
                if isSaving {
                    ProgressView().tint(RexColor.primaryForeground)
                } else {
                    Text(selected.isEmpty ? "Continue" : "Continue with \(selected.count) selected")
                }
            }
            .buttonStyle(RexPrimaryButtonStyle())
            .disabled(isSaving)
            .padding(.horizontal, RexSpacing.page)
            .padding(.vertical, RexSpacing.lg)
        }
    }

    private func interestTile(_ category: RexCategory) -> some View {
        let isOn = selected.contains(category)
        return Button {
            if isOn { selected.remove(category) } else { selected.insert(category) }
        } label: {
            HStack(spacing: RexSpacing.sm) {
                Image(systemName: category.symbol)
                    .font(.system(size: 16))
                Text(category.label)
                    .font(RexFont.text(15, weight: .medium))
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                }
            }
            .foregroundStyle(isOn ? RexColor.primaryForeground : RexColor.foreground)
            .padding(.horizontal, RexSpacing.md)
            .frame(height: 52)
            .background(isOn ? RexColor.primary : RexColor.card)
            .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                    .stroke(isOn ? RexColor.primary : RexColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var findFriendsStep: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: RexSpacing.sm) {
                Text("Find your friends")
                    .font(RexFont.display(28, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Text("REX is only as good as the people in it. Search for anyone you know who's already here.")
                    .font(RexFont.text(15))
                    .foregroundStyle(RexColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, RexSpacing.page)
            .padding(.top, RexSpacing.lg)
            .padding(.bottom, RexSpacing.sm)

            // The real Friends screen — search, suggested friends, send
            // request — reused wholesale rather than rebuilt here.
            FriendsView()

            Button("Done") { advance() }
                .buttonStyle(RexPrimaryButtonStyle())
                .padding(.horizontal, RexSpacing.page)
                .padding(.vertical, RexSpacing.lg)
        }
    }

    private func saveInterestsAndAdvance() async {
        isSaving = true
        if !selected.isEmpty {
            try? await RexAPI.shared.updateInterests(Array(selected))
        }
        isSaving = false
        step = .findFriends
    }

    private func advance() {
        switch step {
        case .interests: step = .findFriends
        case .findFriends: onDone()
        }
    }
}
