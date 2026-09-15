import SwiftUI

struct RootView: View {
    @State private var isSignedIn = RexAPI.shared.isSignedIn
    /// Sept 14 — what, if anything, stands between a signed-in person and
    /// the app: choosing a username first, then the onboarding tour. One
    /// cover driven by one value, not two covers on one view (only one of
    /// those would ever present — see FeedView.ActiveSheet).
    private enum Gate: Identifiable {
        case consent
        case username(suggested: String, name: String?)
        case onboarding
        case notifications
        var id: String {
            switch self {
            case .consent: return "consent"
            case .username: return "username"
            case .onboarding: return "onboarding"
            case .notifications: return "notifications"
            }
        }
    }
    @State private var gate: Gate?

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
                    .onAppear { Task { await checkGates() } }
                    .fullScreenCover(item: $gate) { current in
                        switch current {
                        case .consent:
                            ConsentUpdateView(onAgreed: {
                                gate = nil
                                Task { await checkGates() }
                            })
                        case .username(let suggested, let name):
                            UsernameSetupView(suggestedUsername: suggested, suggestedName: name) {
                                // Straight on to the tour if they haven't
                                // had it, rather than dropping them in the
                                // feed and popping it up a second later.
                                Task {
                                    if needsOnboarding() {
                                        gate = .onboarding
                                    } else if !RexPushNotifications.hasAsked, await RexPushNotifications.canAsk() {
                                        gate = .notifications
                                    } else {
                                        gate = nil
                                    }
                                }
                            }
                        case .onboarding:
                            OnboardingView(onDone: {
                                markOnboarded()
                                gate = nil
                            })
                        case .notifications:
                            NotificationsAskView(onDone: { gate = nil })
                        }
                    }
            } else {
                LoginView(onSignedIn: { isSignedIn = true })
            }
        }
        .onChange(of: isSignedIn) { _, signedIn in
            if signedIn { Task { await checkGates() } }
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

    private func needsOnboarding() -> Bool {
        guard let userId = RexAPI.shared.currentUserId else { return false }
        return !UserDefaults.standard.bool(forKey: onboardedKey(userId))
    }

    /// Username first — "when Danny logged in, he wasn't asked to create a
    /// username" — because it's how friends find you, and the tour that
    /// follows ends at finding friends.
    private func checkGates() async {
        // Every sign-in and launch: make sure this phone's push token is on
        // the server (see refreshRegistrationIfAuthorized).
        await RexPushNotifications.refreshRegistrationIfAuthorized()
        guard gate == nil else { return }
        // Sept 15 — agreement to the current Terms/Privacy Policy comes
        // before anything else. Someone who ticked the box at email sign-up
        // but had to confirm their email first had no session to record it
        // with then; that agreement is recorded now instead of asking twice.
        if await RexAPI.shared.consentNeedsUpdate() {
            if UserDefaults.standard.bool(forKey: "rex.pendingSignupConsent"),
               (try? await RexAPI.shared.recordConsent(source: "signup")) != nil {
                UserDefaults.standard.removeObject(forKey: "rex.pendingSignupConsent")
            } else {
                gate = .consent
                return
            }
        }
        if let pending = await RexAPI.shared.pendingUsernameSetup() {
            gate = .username(suggested: pending.username, name: pending.displayName)
        } else if needsOnboarding() {
            gate = .onboarding
        } else if !RexPushNotifications.hasAsked, await RexPushNotifications.canAsk() {
            // Already through onboarding before it asked (Danny, and
            // everyone before him) and never asked since: once.
            gate = .notifications
        }
    }

    private func markOnboarded() {
        guard let userId = RexAPI.shared.currentUserId else { return }
        UserDefaults.standard.set(true, forKey: onboardedKey(userId))
    }
}
