import SwiftUI

/// Terms of Use + Privacy Policy shown at sign-up (#182). Standard,
/// generic-but-accurate boilerplate for what REX actually does today —
/// meant to be replaced wholesale once Kathryn has a proper
/// solicitor-reviewed policy; nothing else in the app depends on this
/// copy's exact wording, only on `RexAPI.recordTermsAcceptance()` having
/// been called, so swapping the text later is safe and self-contained.
struct LegalContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case terms = "Terms of Use"
        case privacy = "Privacy Policy"
        var id: String { rawValue }
    }

    @State private var section: Section
    @Environment(\.dismiss) private var dismiss

    init(section: Section = .terms) {
        _section = State(initialValue: section)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(RexSpacing.page)

                ScrollView {
                    Text(section == .terms ? Self.termsBody : Self.privacyBody)
                        .font(RexFont.text(14))
                        .foregroundStyle(RexColor.foreground)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, RexSpacing.page)
                        .padding(.bottom, RexSpacing.xxl)
                }
            }
            .background(RexColor.background.ignoresSafeArea())
            .navigationTitle(section.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(RexColor.primary)
    }

    // MARK: - Copy

    private static let lastUpdated = "26 August 2026"

    private static let termsBody = """
    Last updated \(lastUpdated)

    Welcome to REX. These Terms of Use ("Terms") are a legal agreement between you and REX governing your access to and use of the REX app. By creating an account, you agree to these Terms. If you don't agree, please don't use REX.

    1. Who can use REX
    You must be at least 13 years old to use REX. If you're under 18, you should have a parent or guardian's permission.

    2. Your account
    You're responsible for keeping your login credentials secure and for anything that happens under your account. Tell us right away if you think someone else has access to it.

    3. Your content
    You keep ownership of anything you post — recommendations, photos, notes, trips, lists and comments ("Content"). By posting Content, you give REX a licence to store, display and share it with the other users you choose (friends, or the public where a feature is explicitly public, like a shared link) so the app can work as intended.

    You're responsible for what you post. Don't post anything that:
    • is illegal, defamatory, harassing, or infringes someone else's rights (including copyright or privacy);
    • impersonates another person or misrepresents your affiliation with anyone;
    • contains malware or is intended to disrupt the service.

    We can remove Content or suspend accounts that break these rules.

    4. Anonymous posting
    REX lets you mark a recommendation as posted anonymously, which hides your name and photo from other users in the app's normal display. This is a display setting, not a technical guarantee of anonymity — REX (and, in principle, someone with direct access to the underlying data or API) can still associate an anonymous post with your account. Don't rely on this feature to post anything you wouldn't be comfortable being linked to you.

    5. Friends, blasts and social features
    REX is built around real friend connections. Please only add people you actually know, and be considerate about who you tag, mention, or send requests to.

    6. Third-party content and links
    REX shows information about places, books, films and other items sourced from third parties (like Google Places). We don't guarantee this information is accurate or up to date.

    7. Availability
    We aim to keep REX running smoothly but don't guarantee it will always be available, error-free, or uninterrupted. Features may change, and this is an early-stage app that may still have bugs — thank you for helping us test it.

    8. Termination
    You can delete your account at any time. We can suspend or terminate accounts that violate these Terms.

    9. Disclaimer and liability
    REX is provided "as is" without warranties of any kind. To the maximum extent permitted by law, REX isn't liable for indirect or consequential damages arising from your use of the app.

    10. Changes to these Terms
    We may update these Terms from time to time. If we make material changes, we'll let you know in the app. Continuing to use REX after a change means you accept the updated Terms.

    11. Contact
    Questions about these Terms? Reach out at kathryn.k.finnis@gmail.com.

    This is a general-purpose template and will be replaced with a policy tailored and reviewed for REX specifically as the app grows.
    """

    private static let privacyBody = """
    Last updated \(lastUpdated)

    This Privacy Policy explains what information REX collects, how it's used, and the choices you have. REX is a small, early-stage app — this policy is written in plain terms and will be replaced with a fuller, reviewed version over time.

    1. Information we collect
    • Account information: email address, and (if you use Sign in with Apple) the name Apple shares with us.
    • Profile information: username, display name, avatar photo, and anything else you choose to add.
    • Content you create: recommendations, ratings, notes, photos, trips, lists, blasts, comments, and your friend connections.
    • Location-related data: addresses and coordinates for places you or your friends recommend, so they can be shown on the map. REX does not track your ongoing location in the background — location is only used, with permission, to centre the map or suggest nearby places.
    • Device information: a push notification token, if you enable push notifications, so we can deliver them to your device.
    • Usage information: basic technical logs needed to operate and secure the app.

    2. How we use this information
    We use your information to:
    • run the core features of REX (feeds, friends, trips, lists, maps, notifications);
    • show your content to the friends you choose to share it with;
    • send you notifications you've opted into;
    • maintain the security and reliability of the service;
    • understand overall usage so we can improve the app.

    We don't sell your personal information.

    3. Who your information is shared with
    • Other REX users: friends can see your recommendations, profile, and activity as described in the app; some features (like shared trip/list links) are visible to anyone with the link.
    • Service providers: we use Supabase to store data and Google (Maps/Places) to look up locations — these providers process data on our behalf under their own security and privacy commitments.
    • We do not share your personal information with advertisers or data brokers.

    4. Anonymous posts
    Marking a post as anonymous hides your identity from other users in REX's normal interface. It does not anonymise the underlying record — REX retains the connection between you and the post. See the Terms of Use for more detail.

    5. Data retention
    We keep your information for as long as your account is active. If you delete your account, we'll delete or anonymise your personal data within a reasonable period, except where we need to retain something for legal or security reasons.

    6. Your rights
    Depending on where you live (including under the UK/EU GDPR), you may have the right to:
    • access the personal data we hold about you;
    • correct inaccurate data;
    • request deletion of your data;
    • export your data in a portable format;
    • object to or restrict certain processing;
    • withdraw consent at any time, where processing is based on consent.

    To exercise any of these rights, contact us at kathryn.k.finnis@gmail.com and we'll respond as soon as we reasonably can.

    7. Children's privacy
    REX isn't directed at children under 13, and we don't knowingly collect personal information from them.

    8. Security
    We take reasonable technical and organisational steps to protect your information, including access controls on our database and encrypted connections. No system is 100% secure, and we can't guarantee absolute security.

    9. International transfers
    Our service providers may process data outside your home country. Where that happens, we rely on their own safeguards for handling data lawfully.

    10. Changes to this policy
    We may update this policy as REX evolves. Material changes will be flagged in the app.

    11. Contact
    Questions, requests, or concerns about your data? Email kathryn.k.finnis@gmail.com.

    This is a general-purpose template and will be replaced with a policy tailored and reviewed for REX specifically as the app grows.
    """
}
