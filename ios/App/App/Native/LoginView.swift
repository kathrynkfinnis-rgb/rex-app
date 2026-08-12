import SwiftUI

/// Sign-in, in three screens: what REX is, then either welcome back or get
/// started. Editorial restraint per the brand guidelines — large fields of
/// Oxford Stone, the supplied wordmark, a serif headline, one dominant action.
struct LoginView: View {
    var onSignedIn: () -> Void

    private enum Screen: Hashable { case signIn, signUp }

    @State private var path: [Screen] = []

    var body: some View {
        NavigationStack(path: $path) {
            landing
                .navigationDestination(for: Screen.self) { screen in
                    switch screen {
                    case .signIn: SignInScreen(onSignedIn: onSignedIn)
                    case .signUp: SignUpScreen(onSignedIn: onSignedIn)
                    }
                }
        }
        .tint(RexColor.primary)
    }

    // MARK: - 1. Landing

    private var landing: some View {
        ZStack {
            RexColor.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: RexSpacing.xxxl)

                Image("RexWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                    .accessibilityLabel("REX")
                    .padding(.bottom, RexSpacing.xl)

                Text("Recommendations from people you actually trust.")
                    .font(RexFont.display(34, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, RexSpacing.md)

                Text("Books, films, places and trips — kept by your friends, not an algorithm.")
                    .font(RexFont.text(16))
                    .foregroundStyle(RexColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                VStack(spacing: RexSpacing.md) {
                    Button("Get started") { path = [.signUp] }
                        .buttonStyle(RexPrimaryButtonStyle())

                    Button("I already have an account") { path = [.signIn] }
                        .buttonStyle(RexSecondaryButtonStyle())
                }

                Text("By continuing you agree to the Terms of Service and Privacy Policy.")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, RexSpacing.lg)

                Spacer(minLength: RexSpacing.xl)
            }
            .padding(.horizontal, RexSpacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 2. Welcome back

private struct SignInScreen: View {
    var onSignedIn: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focused: AuthField?

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isLoading
    }

    var body: some View {
        AuthScaffold(title: "Welcome back", blurb: "Pick up where your friends left off.") {
            VStack(spacing: RexSpacing.md) {
                authField("Email", text: $email, isSecure: false, field: .email,
                          submitLabel: .next, focused: $focused) { focused = .password }
                authField("Password", text: $password, isSecure: true, field: .password,
                          submitLabel: .go, focused: $focused) { if canSubmit { signIn() } }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, RexSpacing.md)
            }

            Button(action: signIn) {
                if isLoading {
                    ProgressView().tint(RexColor.primaryForeground)
                } else {
                    Text("Sign in")
                }
            }
            .buttonStyle(RexPrimaryButtonStyle())
            .opacity(canSubmit ? 1 : 0.5)
            .disabled(!canSubmit)
            .padding(.top, RexSpacing.xl)

            orDivider

            AppleSignInButton(onSignedIn: onSignedIn, errorMessage: $errorMessage)
        }
    }

    private var orDivider: some View {
        HStack(spacing: RexSpacing.md) {
            Rectangle().fill(RexColor.border).frame(height: 1)
            Text("or").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
            Rectangle().fill(RexColor.border).frame(height: 1)
        }
        .padding(.vertical, RexSpacing.lg)
    }

    private func signIn() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await RexAPI.shared.signIn(email: email, password: password)
                await MainActor.run { isLoading = false; onSignedIn() }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - 3. Get started

private struct SignUpScreen: View {
    var onSignedIn: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var checkYourInbox = false
    @FocusState private var focused: AuthField?

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 6
            && !isLoading
    }

    var body: some View {
        AuthScaffold(
            title: checkYourInbox ? "Check your inbox" : "Get started",
            blurb: checkYourInbox
                ? "We've sent you a link to confirm your email. Tap it and you're in."
                : "Two steps: make an account, then find your friends."
        ) {
            if checkYourInbox {
                Image(systemName: "envelope")
                    .font(.system(size: 40))
                    .foregroundStyle(RexColor.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RexSpacing.xxl)
            } else {
                stepRow(1, "Make an account", "Email and a password, or use Apple.")
                stepRow(2, "Find your friends", "REX is only as good as the people in it.")

                VStack(spacing: RexSpacing.md) {
                    authField("Email", text: $email, isSecure: false, field: .email,
                              submitLabel: .next, focused: $focused) { focused = .password }
                    authField("Password (6+ characters)", text: $password, isSecure: true,
                              field: .password, submitLabel: .go, focused: $focused) {
                        if canSubmit { signUp() }
                    }
                }
                .padding(.top, RexSpacing.lg)

                if let errorMessage {
                    Text(errorMessage)
                        .font(RexFont.text(13))
                        .foregroundStyle(RexColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, RexSpacing.md)
                }

                Button(action: signUp) {
                    if isLoading {
                        ProgressView().tint(RexColor.primaryForeground)
                    } else {
                        Text("Create account")
                    }
                }
                .buttonStyle(RexPrimaryButtonStyle())
                .opacity(canSubmit ? 1 : 0.5)
                .disabled(!canSubmit)
                .padding(.top, RexSpacing.xl)

                HStack(spacing: RexSpacing.md) {
                    Rectangle().fill(RexColor.border).frame(height: 1)
                    Text("or").font(RexFont.text(12)).foregroundStyle(RexColor.mutedForeground)
                    Rectangle().fill(RexColor.border).frame(height: 1)
                }
                .padding(.vertical, RexSpacing.lg)

                AppleSignInButton(onSignedIn: onSignedIn, errorMessage: $errorMessage)
            }
        }
    }

    private func stepRow(_ n: Int, _ title: String, _ blurb: String) -> some View {
        HStack(alignment: .top, spacing: RexSpacing.md) {
            Text("\(n)")
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primaryForeground)
                .frame(width: 26, height: 26)
                .background(RexColor.primary)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RexFont.text(15, weight: .medium))
                    .foregroundStyle(RexColor.foreground)
                Text(blurb)
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.bottom, RexSpacing.md)
    }

    private func signUp() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await RexAPI.shared.signUp(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    // No session means Supabase is waiting on email confirmation.
                    if RexAPI.shared.hasSession { onSignedIn() } else { checkYourInbox = true }
                }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = error.localizedDescription }
            }
        }
    }
}

// MARK: - Shared bits

private enum AuthField { case email, password }

/// The common frame for screens 2 and 3.
private struct AuthScaffold<Content: View>: View {
    let title: String
    let blurb: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            RexColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(RexFont.display(32, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, RexSpacing.sm)

                    Text(blurb)
                        .font(RexFont.text(16))
                        .foregroundStyle(RexColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, RexSpacing.xxl)

                    content()

                    Spacer(minLength: RexSpacing.xxxl)
                }
                .padding(.horizontal, RexSpacing.page)
                .padding(.top, RexSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

@ViewBuilder
private func authField(
    _ placeholder: String,
    text: Binding<String>,
    isSecure: Bool,
    field: AuthField,
    submitLabel: SubmitLabel,
    focused: FocusState<AuthField?>.Binding,
    onSubmit: @escaping () -> Void
) -> some View {
    Group {
        if isSecure {
            SecureField(placeholder, text: text)
        } else {
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
        }
    }
    .font(RexFont.text(16))
    .focused(focused, equals: field)
    .submitLabel(submitLabel)
    .onSubmit(onSubmit)
    .padding(.horizontal, RexSpacing.lg)
    .frame(height: 52)
    .background(RexColor.card)
    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
            .stroke(focused.wrappedValue == field ? RexColor.primary : RexColor.border, lineWidth: 1)
    )
}
