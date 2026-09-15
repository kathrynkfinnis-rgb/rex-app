import SwiftUI

/// Terms of Use + Privacy Policy shown at sign-up (#182). Standard,
/// generic-but-accurate boilerplate for what REX actually does today —
/// meant to be replaced wholesale once Kathryn has a proper
/// solicitor-reviewed policy; nothing else in the app depends on this
/// copy's exact wording, only on `RexAPI.recordTermsAcceptance()` having
/// been called, so swapping the text later is safe and self-contained.
/// Sept 15 — the version people agree to. Bump it whenever the Terms or the
/// Privacy Policy change materially: every account whose recorded version
/// differs is asked to agree again (RootView's consent gate), and the new
/// acceptance is logged in consent_log with a timestamp.
enum RexLegal {
    static let version = "2026-09-15"
}

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

    private static let lastUpdated = "15 September 2026"

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
    You can delete your account at any time, from Profile → Your data & privacy → Delete my account. We can suspend or terminate accounts that violate these Terms.

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
    • Places you recommend: addresses and map coordinates for places you or your friends Rex, so they can be shown on the map.
    • Your device's location: only if you allow it, and only while you're using the app, to centre the map on where you are. Apple turns it into an area name (like "Hackney") for the map's header. It isn't saved to your account, it isn't shared with your friends, and REX never tracks your location in the background.
    • Your contacts: only if you choose "Find friends from your contacts". REX reads the email addresses in your contacts on your phone and scrambles each one (a SHA-256 hash) before anything leaves the phone. Those scrambled values are compared with REX accounts to show you which of your contacts are already here, then discarded. We don't store your contacts or upload names, phone numbers or other details.
    • Device information: a push notification token, if you turn on notifications, so we can deliver them to your phone.
    • Records of your agreement to these policies: which version you agreed to, and when.
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
    • Service providers, who process data on our behalf under their own security and privacy commitments:
      – Supabase: stores your account, content and photos.
      – Google (Maps and Places): shows maps and looks up places and addresses.
      – Apple: Sign in with Apple, push notifications, and naming the area on the map.
      – Anthropic (Claude): reads documents and recipe photos you choose to import (see below).
    • We do not share your personal information with advertisers or data brokers.

    Importing from a document or a recipe photo
    When you use "Import from doc" or import a recipe from a photo, the text or photo you choose is sent to Anthropic's Claude AI to pick out the recommendations or read the recipe. REX doesn't keep a copy: the photo isn't uploaded to your account, and only the text you then choose to post is saved. Anthropic processes it under its commercial terms, doesn't use it to train its models, and deletes it after a limited retention period. If you'd rather it wasn't processed this way, type or paste the details in yourself instead.

    4. Anonymous posts
    Marking a post as anonymous hides your identity from other users in REX's normal interface. It does not anonymise the underlying record — REX retains the connection between you and the post. See the Terms of Use for more detail.

    5. Data retention
    We keep your information for as long as your account is active. When you delete your account, your profile, recommendations, trips, lists, collections, comments, likes, friend connections, photos and notification settings are deleted straight away. Copies may remain in our database provider's routine backups for a short period until those backups are overwritten.

    6. Your rights
    Depending on where you live (including under the UK/EU GDPR), you may have the right to:
    • access the personal data we hold about you;
    • correct inaccurate data;
    • request deletion of your data;
    • export your data in a portable format;
    • object to or restrict certain processing;
    • withdraw consent at any time, where processing is based on consent.

    You can download a copy of your data, or delete your account and everything in it, yourself at any time: Profile → Your data & privacy. For anything else, contact us at kathryn.k.finnis@gmail.com and we'll respond as soon as we reasonably can.

    7. Children's privacy
    REX isn't directed at children under 13, and we don't knowingly collect personal information from them.

    8. Security
    We take reasonable technical and organisational steps to protect your information, including access controls on our database and encrypted connections. No system is 100% secure, and we can't guarantee absolute security.

    9. International transfers
    Our service providers may process data outside your home country. Where that happens, we rely on their own safeguards for handling data lawfully.

    10. Changes to this policy
    We may update this policy as REX evolves. When we make a material change, we'll ask you to review and agree to the new version in the app, and we keep a record of when you did.

    11. Contact
    Questions, requests, or concerns about your data? Email kathryn.k.finnis@gmail.com.

    This is a general-purpose template and will be replaced with a policy tailored and reviewed for REX specifically as the app grows.
    """
}
