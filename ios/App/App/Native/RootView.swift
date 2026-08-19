import SwiftUI

struct RootView: View {
    @State private var isSignedIn = RexAPI.shared.isSignedIn
    @State private var showingOnboarding = false

    var body: some View {
        Group {
            if isSignedIn {
                MainTabView(onSignedOut: { isSignedIn = false })
                    // #102 — gated on a per-user-id flag rather than "did
                    // this session just call signUp()", so it fires
                    // correctly regardless of which sign-in path got them
                    // here (email, Apple, or a plain returning sign-in on a
                    // fresh install) without LoginView needing to thread a
                    // separate "just signed up" signal through three screens.
                    .onAppear { checkOnboarding() }
                    .fullScreenCover(isPresented: $showingOnboarding) {
                        OnboardingView(onDone: {
                            markOnboarded()
                            showingOnboarding = false
                        })
                    }
            } else {
                LoginView(onSignedIn: { isSignedIn = true })
            }
        }
        .onChange(of: isSignedIn) { _, signedIn in
            if signedIn { checkOnboarding() }
        }
        // The brand palette (RexColor) is fixed light-only — RexColor.card is
        // a literal white hex, not a semantic color that darkens with the
        // system. Plain-default text left unstyled follows the device's
        // colour scheme regardless, so a phone in Dark Mode rendered white
        // text on that same white field: invisible until you knew it was
        // there. Locking to light stops every current and future field from
        // inheriting a scheme this palette was never built for.
        .preferredColorScheme(.light)
    }

    private func onboardedKey(_ userId: String) -> String { "rex.onboarded.\(userId)" }

    private func checkOnboarding() {
        guard let userId = RexAPI.shared.currentUserId else { return }
        showingOnboarding = !UserDefaults.standard.bool(forKey: onboardedKey(userId))
    }

    private func markOnboarded() {
        guard let userId = RexAPI.shared.currentUserId else { return }
        UserDefaults.standard.set(true, forKey: onboardedKey(userId))
    }
}
