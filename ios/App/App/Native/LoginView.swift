import SwiftUI

struct LoginView: View {
    var onSignedIn: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            RexColor.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Text("REX")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(RexColor.primary)

                Text("The little shared book of things your friends actually love.")
                    .font(.subheadline)
                    .foregroundStyle(RexColor.mutedForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 23))
                        .overlay(RoundedRectangle(cornerRadius: 23).stroke(RexColor.border, lineWidth: 1))

                    SecureField("Password", text: $password)
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: 23))
                        .overlay(RoundedRectangle(cornerRadius: 23).stroke(RexColor.border, lineWidth: 1))
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(RexColor.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button(action: signIn) {
                    if isLoading {
                        ProgressView().tint(RexColor.primaryForeground)
                    } else {
                        Text("Sign in").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(RexColor.primary)
                .foregroundStyle(RexColor.primaryForeground)
                .clipShape(Capsule())
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .disabled(isLoading || email.isEmpty || password.isEmpty)

                Spacer()
                Spacer()
            }
        }
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
