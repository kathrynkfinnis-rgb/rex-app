import SwiftUI
import AuthenticationServices
import CryptoKit

/// Sign in with Apple.
///
/// Apple signs a nonce we generate and returns it inside the identity token;
/// Supabase compares the two to prove the token was minted for this attempt.
/// Apple wants the SHA-256 of the nonce, Supabase wants the original, so both
/// are kept.
struct AppleSignInButton: View {
    var onSignedIn: () -> Void
    @Binding var errorMessage: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var rawNonce = ""

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Self.randomNonce()
            rawNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let auth):
                guard
                    let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let idToken = String(data: tokenData, encoding: .utf8)
                else {
                    errorMessage = "Apple didn't return a sign-in token. Try again."
                    return
                }
                Task {
                    do {
                        try await RexAPI.shared.signInWithApple(idToken: idToken, nonce: rawNonce)
                        await MainActor.run { onSignedIn() }
                    } catch {
                        await MainActor.run { errorMessage = error.localizedDescription }
                    }
                }
            case .failure(let error):
                // Cancelling isn't an error worth shouting about.
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                errorMessage = error.localizedDescription
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
    }

    // MARK: - Nonce

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // Falling back to a predictable nonce would defeat the point.
            return UUID().uuidString + UUID().uuidString
        }
        let charset = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
