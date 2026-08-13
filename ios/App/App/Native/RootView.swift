import SwiftUI

struct RootView: View {
    @State private var isSignedIn = RexAPI.shared.isSignedIn

    var body: some View {
        Group {
            if isSignedIn {
                MainTabView(onSignedOut: { isSignedIn = false })
            } else {
                LoginView(onSignedIn: { isSignedIn = true })
            }
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
}
