import SwiftUI

/// #102 (Phoebe + Gemma) — after signup, ask a couple of quick questions
/// instead of dropping straight into an empty feed, and explain what the
/// app actually is while general awareness is still low. Three steps: what
/// REX is, what you're into, then find some friends (REX is only as good as
/// the people in it, and a feed with nobody followed is the worst possible
/// first impression).
///
/// The explainer used to live behind a logo tap in the feed's toolbar, but
/// that slot went to the new Explore tab instead — this is its new, better
/// home: the moment someone's least sure what REX is, is the moment they've
/// just signed up.
///
/// Shown once per account — RootView gates this on a per-user-id UserDefaults
/// flag, not tied to "is this literally a brand-new signup", so it behaves
/// sensibly on every sign-in path (email, Apple) without LoginView needing
/// to thread a separate "just signed up" signal through.
struct OnboardingView: View {
    var onDone: () -> Void

    private enum Step { case intro, interests, findFriends }

    @State private var step: Step = .intro
    @State private var selected: Set<RexCategory> = []
    @State private var isSaving = false

    private let interestOptions: [RexCategory] = [
        .place, .trip, .book, .movie, .tv, .podcast, .recipe, .event,
    ]

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .intro: introStep
                case .interests: interestsStep
                case .findFriends: findFriendsStep
                }
            }
            .background(RexColor.background.ignoresSafeArea())
            .toolbar {
                if step != .intro {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { advance() }
                            .font(RexFont.text(14, weight: .semibold))
                            .foregroundStyle(RexColor.mutedForeground)
                    }
                }
            }
        }
        .tint(RexColor.primary)
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: RexSpacing.lg) {
            Image("RexWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 28)
                .accessibilityLabel("REX")
                .padding(.top, RexSpacing.lg)

            Text("Recommendations from people you actually trust.")
                .font(RexFont.display(26, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: RexSpacing.md) {
                introRow(icon: "person.2", text: "Friends share what they've actually read, watched, eaten and been to \u{2014} not an algorithm's guess.")
                introRow(icon: "checkmark.seal", text: "Every recommendation is rated by someone you know, with their own take on it.")
                introRow(icon: "bookmark", text: "Save what catches your eye into collections, or start a trip and build it out stop by stop.")
            }

            Spacer(minLength: 0)

            Button("Get started") { advance() }
                .buttonStyle(RexPrimaryButtonStyle())
        }
        .padding(.horizontal, RexSpacing.page)
        .padding(.bottom, RexSpacing.lg)
    }

    private func introRow(icon: String, text: String) -> some View {
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
        case .intro: step = .interests
        case .interests: step = .findFriends
        case .findFriends: onDone()
        }
    }
}
