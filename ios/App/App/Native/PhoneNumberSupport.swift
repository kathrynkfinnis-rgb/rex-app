import SwiftUI
import CryptoKit

/// Sept 29 — "please ask for phone number at sign up, and then an alert for
/// those that have already set up accounts".
///
/// Contacts matching worked on email only, and almost nobody has their
/// friends' sign-in addresses in their phone — people have numbers. Matching
/// on numbers is the version that actually finds anyone.
///
/// The number never leaves the device in the clear and is never stored: what
/// goes to the server is a SHA-256 of it in E.164 form, the same treatment
/// the email side already gets. See the migration for what that does and
/// doesn't protect.
enum RexPhone {
    /// Normalising is the whole difficulty. The same mobile is written
    /// "07917 004798", "+44 7917 004798", "+447917004798" and "07917004798",
    /// and a hash only matches if both sides agree on one form — so both
    /// sides use E.164, and a mismatch here means the feature silently finds
    /// nobody rather than failing loudly.
    ///
    /// `region` is the dialling code to assume for a number written without
    /// one ("44"), taken from the phone's own region.
    static func e164(_ raw: String, region: String = defaultCallingCode) -> String? {
        let digitsAndPlus = raw.filter { $0.isNumber || $0 == "+" }
        guard !digitsAndPlus.isEmpty else { return nil }

        if digitsAndPlus.hasPrefix("+") {
            let digits = digitsAndPlus.dropFirst().filter(\.isNumber)
            return digits.count >= 8 ? "+" + digits : nil
        }

        var digits = digitsAndPlus.filter(\.isNumber)
        // 00 is the other way of writing +, used across Europe.
        if digits.hasPrefix("00") { digits = String(digits.dropFirst(2)); return digits.count >= 8 ? "+" + digits : nil }
        // A national number: drop the trunk 0 and put the country code on.
        if digits.hasPrefix("0") { digits = String(digits.dropFirst()) }
        guard digits.count >= 7 else { return nil }
        return "+" + region + digits
    }

    /// The phone's own region, so a UK phone assumes +44 and an Irish one
    /// assumes +353 without anyone being asked which country they're in.
    static var defaultCallingCode: String {
        let region = Locale.current.region?.identifier ?? "GB"
        return callingCodes[region] ?? "44"
    }

    /// Enough of the world to cover anyone REX is likely to reach soon. An
    /// unknown region falls back to +44 rather than refusing, since a wrong
    /// guess simply fails to match rather than doing damage.
    private static let callingCodes: [String: String] = [
        "GB": "44", "IE": "353", "US": "1", "CA": "1", "AU": "61", "NZ": "64",
        "FR": "33", "DE": "49", "ES": "34", "IT": "39", "PT": "351", "NL": "31",
        "BE": "32", "CH": "41", "AT": "43", "SE": "46", "NO": "47", "DK": "45",
        "FI": "358", "PL": "48", "GR": "30", "ZA": "27", "IN": "91", "SG": "65",
        "HK": "852", "AE": "971", "JP": "81", "BR": "55", "MX": "52",
    ]

    static func hash(_ e164: String) -> String {
        SHA256.hash(data: Data(e164.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Normalise and hash in one step, or nil if it isn't a usable number.
    static func hashed(_ raw: String) -> String? {
        e164(raw).map(hash)
    }
}

/// Asked once, after the username is chosen at sign-up — and separately, once,
/// of everyone who signed up before this existed.
///
/// Deliberately skippable. A phone number is a bigger ask than an email
/// address, and someone who says no should get the app rather than a wall.
struct PhoneNumberPromptView: View {
    /// "Set up" at sign-up, "catch-up" for an existing account — the ask is
    /// the same, the framing isn't.
    var isCatchUp: Bool = false
    var onDone: () -> Void

    @State private var number = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.lg) {
            Spacer(minLength: RexSpacing.xxl)

            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(RexColor.primary)

            Text(isCatchUp ? "Let friends find you" : "How will friends find you?")
                .font(RexFont.display(26, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text("""
                 Your friends have your number in their phone — they almost certainly \
                 don't have the email address you signed up with. Adding it is what lets \
                 REX tell them you're here.
                 """)
                .font(RexFont.text(15))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Mobile number", text: $number)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focused)
                .font(RexFont.text(17))
                .padding(.horizontal, RexSpacing.md)
                .frame(height: 52)
                .background(RexColor.card)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                        .stroke(RexColor.border, lineWidth: 1)
                )

            Text("""
                 REX never stores your number and never shows it to anyone. It's scrambled \
                 on this phone first, and only the scrambled version is sent — the same way \
                 contact matching already works.
                 """)
                .font(RexFont.text(12))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(RexFont.text(13))
                    .foregroundStyle(RexColor.destructive)
            }

            Spacer()

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView().tint(RexColor.primaryForeground).frame(maxWidth: .infinity)
                } else {
                    Text("Save").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(RexPrimaryButtonStyle())
            .disabled(isSaving || RexPhone.e164(number) == nil)
            .opacity(RexPhone.e164(number) == nil ? 0.5 : 1)

            Button(isCatchUp ? "Not now" : "Skip") {
                RexPhone.markAsked()
                onDone()
            }
            .font(RexFont.text(15, weight: .semibold))
            .foregroundStyle(RexColor.mutedForeground)
            .frame(maxWidth: .infinity)
            .padding(.bottom, RexSpacing.lg)
        }
        .padding(.horizontal, RexSpacing.page)
        .background(RexColor.background.ignoresSafeArea())
        .rexDismissableKeyboard()
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            focused = true
        }
    }

    private func save() async {
        guard let hash = RexPhone.hashed(number) else {
            errorMessage = "That doesn't look like a mobile number."
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try await RexAPI.shared.setMyPhoneHash(hash)
            RexPhone.markAsked()
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

extension RexPhone {
    /// Asked once per account, whatever the answer — nobody should meet this
    /// screen twice.
    private static func key() -> String? {
        RexAPI.shared.currentUserId.map { "rex.askedForPhone.\($0)" }
    }

    static func markAsked() {
        guard let key = key() else { return }
        UserDefaults.standard.set(true, forKey: key)
    }

    static var hasBeenAsked: Bool {
        guard let key = key() else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}
