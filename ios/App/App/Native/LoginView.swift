import SwiftUI

/// Welcome / sign-in. Editorial restraint per the brand guidelines: large
/// fields of Oxford Stone, the supplied wordmark, a serif headline and one
/// dominant action.
struct LoginView: View {
    var onSignedIn: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isLoading
    }

    var body: some View {
        ZStack {
            RexColor.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: RexSpacing.xxxl)

                    Image("RexWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 34)
                        .accessibilityLabel("REX")
                        .padding(.bottom, RexSpacing.xl)

                    Text("Recommendations from people you actually trust.")
                        .font(RexFont.display(32, weight: .semibold))
                        .foregroundStyle(RexColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, RexSpacing.md)

                    Text("Books, films, places and trips — kept by your friends, not an algorithm.")
                        .font(RexFont.text(16))
                        .foregroundStyle(RexColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, RexSpacing.xxl)

                    VStack(spacing: RexSpacing.md) {
                        field(
                            "Email", text: $email, isSecure: false,
                            field: .email, submitLabel: .next
                        )
                        field(
                            "Password", text: $password, isSecure: true,
                            field: .password, submitLabel: .go
                        )
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

                    Text("By continuing you agree to the Terms of Service and Privacy Policy.")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, RexSpacing.lg)

                    Spacer(minLength: RexSpacing.xxxl)
                }
                .padding(.horizontal, RexSpacing.page)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func field(
        _ placeholder: String,
        text: Binding<String>,
        isSecure: Bool,
        field: Field,
        submitLabel: SubmitLabel
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
        .focused($focused, equals: field)
        .submitLabel(submitLabel)
        .onSubmit {
            if field == .email { focused = .password } else if canSubmit { signIn() }
        }
        .padding(.horizontal, RexSpacing.lg)
        .frame(height: 52)
        .background(RexColor.card)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                .stroke(focused == field ? RexColor.primary : RexColor.border, lineWidth: 1)
        )
    }

    private func signIn() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await RexAPI.shared.signIn(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    onSignedIn()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
