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
    }
}
