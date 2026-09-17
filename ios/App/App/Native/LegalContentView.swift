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
    static let version = "2026-09-17"
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

    private static let lastUpdated = "17 September 2026"

    // Sept 17 — rewritten from Kathryn's solicitor drafts ("Find Rex",
    // Three Lines Studio Ltd) merged with what the app actually does, which
    // the drafts didn't cover: contacts matching, AI document and photo
    // import, in-app reporting and blocking, consent records, in-app export
    // and deletion. Age is 16+ throughout, per Kathryn. Anything still
    // needing her input is marked [TO CONFIRM] rather than invented.

    private static let termsBody = """
    Last updated \(lastUpdated)

    Welcome to REX (the "App"), operated by Three Lines Studio Ltd ("we", "us", "our"). These Terms of Service ("Terms") govern your use of the App, our website and related services.

    By creating an account or using the App, you agree to these Terms. If you don't agree, please don't use REX.

    1. Who can use REX
    You must be at least 16 years old to create an account. By registering you confirm you meet that age requirement.

    You're responsible for keeping your login details secure and for everything done through your account. Tell us at support@find-rex.com if you think someone else has access to it.

    2. Your content
    REX lets you post photos, text, ratings, recommendations, trips, lists, links and profile details ("Your Content").

    You keep ownership of Your Content. By posting it, you give us a worldwide, non-exclusive, royalty-free, transferable, sub-licensable licence to host, store, reproduce, adapt, publish and display it for the purpose of operating, improving and promoting the App.

    You confirm that you have the rights to post Your Content and that it doesn't infringe anyone else's intellectual property, privacy or other rights.

    You can delete any Rex, photo, trip or list at any time. Deleting your account deletes all of it (see section 8).

    3. What you may not post
    Don't use REX to post or do anything that is:
    • illegal, fraudulent, threatening, abusive, harassing, defamatory or hateful;
    • sexually explicit, or graphically violent;
    • discriminatory on the basis of race, ethnicity, religion, sex, gender, sexual orientation, disability or age;
    • infringing of anyone's copyright, trademark or other rights;
    • spam, unauthorised advertising or a scam;
    • impersonating another person or misrepresenting your connection to one;
    • harmful code, or an attempt to scrape, overload or reverse-engineer the App.

    4. Reporting, blocking and moderation
    Reporting: every Rex, comment and profile can be reported from inside the App — the "…" menu on a card, or the "…" on someone's profile — or by emailing support@find-rex.com.

    Our response: we review reports and aim to act within 24 hours. We can remove content, restrict features, or suspend and delete accounts that break these rules. Serious or repeated breaches mean removal without notice.

    Blocking: you can block anyone from their profile or from a card's menu. Blocking ends any friendship between you, hides each of you from the other, and can be undone in Settings → Your data & privacy → Blocked accounts.

    We may also review or remove content proactively, but we're not obliged to monitor everything posted.

    5. Copyright complaints
    If you believe content on REX infringes your copyright, email support@find-rex.com with: a description of the work; where the material appears in the App; your contact details; a statement that you believe in good faith the use isn't authorised; and a statement, made under penalty of perjury, that your notice is accurate and you're the rights holder or authorised to act for them. We respond in line with the Digital Millennium Copyright Act and equivalent laws.

    6. Our intellectual property
    Except for Your Content, everything in the App — software, design, logos, trademarks, text and graphics — belongs to or is licensed by Three Lines Studio Ltd. Don't copy, distribute or make derivative works from it without our written permission.

    7. Importing with AI
    When you import recommendations from a document, or a recipe from a photo, the text or image you choose is sent to our AI provider (Anthropic) to be read. REX doesn't keep the photo or the document — only what you choose to save. Don't import anything you don't have the right to share. See the Privacy Policy for detail.

    8. Ending your account
    You can delete your account and everything in it at any time: Profile → Settings → Your data & privacy → Delete my account. You can also download a copy of your data there first.

    We may suspend or end your access, or remove Your Content, if you break these Terms or if we need to for legal or security reasons.

    9. Availability and liability
    REX is provided "as is" and "as available". It's an early-stage app: features change, and it may have bugs. We don't guarantee it will always be available, accurate or uninterrupted.

    Content posted by users is their view, not ours. We don't endorse or verify recommendations, and information about places, books and films comes from third parties (Google, TMDB, Open Library and others) which we don't guarantee.

    To the fullest extent permitted by law, Three Lines Studio Ltd is not liable for indirect, incidental, special or consequential loss, or loss of profits or revenue, arising from your use of, or inability to use, the App. Nothing here limits liability that can't be limited by law, including for death or personal injury caused by negligence, or fraud. If you're a consumer, you keep your statutory rights.

    10. Apple
    These Terms are between you and Three Lines Studio Ltd, not Apple. Apple has no obligation to provide support or maintenance for the App. If the App fails to conform to any warranty, you may notify Apple and Apple will refund the purchase price (if any); to the maximum extent permitted by law, Apple has no other warranty obligation. Apple isn't responsible for addressing any claim about the App, including product liability, legal compliance and consumer protection claims. Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them against you.

    11. Governing law
    These Terms are governed by the laws of England and Wales, and the courts of England and Wales have exclusive jurisdiction. If you're a consumer resident elsewhere in the UK or the EU, you keep the protection of your local mandatory laws.

    12. Changes
    We may update these Terms. When we make a material change we'll ask you to review and agree to the new version in the App, and we keep a record of when you did.

    13. Contact
    Three Lines Studio Ltd
    support@find-rex.com
    Registered address: [TO CONFIRM — Kathryn to add the registered company address]
    """

    private static let privacyBody = """
    Last updated \(lastUpdated)

    Three Lines Studio Ltd ("we", "us", "our") operates REX. This policy explains what we collect, why, who processes it, and the choices and rights you have. We are the data controller for the personal data described here.

    1. Information we collect
    • Account and profile: email address, username, name, profile photo, and anything else you add. If you use Sign in with Apple, the name and email address Apple shares with us (which may be a private relay address).
    • What you post: recommendations, ratings, notes, photos, trips, lists, blasts, comments, likes, and your friend connections.
    • Places you recommend: addresses and map coordinates, so they can be shown on the map.
    • Your device's location: only if you allow it, and only while you're using the App, to centre the map on where you are. Apple turns the coordinates into an area name for the map's header. It isn't saved to your account, isn't shared with friends, and REX never tracks your location in the background. The App works without it.
    • Your contacts: only if you choose "Find friends from your contacts". REX reads the email addresses in your contacts on your phone and scrambles each one (a SHA-256 hash) before anything leaves the device. Those scrambled values are compared with REX accounts to show which of your contacts are here, then discarded. We don't store your contacts, names or phone numbers.
    • Imports: text you paste for import, and photos of recipes you choose to import (see section 4).
    • Device and technical data: push notification token if you turn notifications on, device type and operating system, IP address, and basic logs needed to run and secure the service.
    • Safety data: reports you make or that are made about your content, and who you have blocked.
    • Records of consent: which version of these documents you agreed to, and when.
    • Support: what you send us when you contact us or send feedback.

    2. Why we use it, and our lawful basis
    • Creating and running your account, showing your content to the friends you choose — to perform our contract with you.
    • Using your location, your contacts, and sending push notifications — consent, which you give through the iOS permission prompts and can withdraw at any time in iOS Settings or in the App.
    • Keeping REX safe: moderating reported content, preventing fraud and abuse, enforcing our Terms — our legitimate interest in a safe service, and our legal obligations.
    • Understanding overall usage so we can improve the App — our legitimate interest in developing the service.
    • Responding to your questions, complaints and data requests — our legal obligations and legitimate interests.

    We don't sell your personal data, we don't use it for advertising, and we don't make decisions about you by automated means alone.

    3. Who processes your data
    We share data only with providers who process it on our instructions, under contract:
    • Supabase — database, file storage and authentication.
    • Google (Maps, Places) — maps, place and address lookup.
    • Apple — Sign in with Apple, push notification delivery, and turning coordinates into an area name.
    • Anthropic — reading documents and recipe photos you choose to import (section 4).
    • TMDB, Open Library and Google Books — descriptions and ratings for films, TV and books shown on item pages. These are lookups of the title, not of you.

    We may also disclose data where the law requires it, or to protect the rights and safety of our users.

    Other people see what you post: your friends see your Rex, profile and activity. Some things are public by design — a shared trip or collection link opens for anyone who has the link, and content you post to a public collection is visible to anyone on REX.

    4. Importing documents and recipe photos
    When you use "Import from doc" or import a recipe from a photo, the text or image is sent to Anthropic's Claude to pick out the recommendations or read the recipe. REX doesn't store the photo — it isn't added to your account — and only the text you then choose to post is saved. Anthropic processes it under its commercial terms, doesn't use it to train its models, and deletes it after a limited retention period. If you'd rather not, type the details in yourself instead.

    5. Anonymous posts
    Marking a post anonymous hides your name and photo from other users in the App's normal display. It doesn't anonymise the underlying record: REX keeps the link between you and the post, and can be required to disclose it. Don't rely on it to post anything you wouldn't want linked to you.

    6. Keeping and deleting your data
    We keep your information while your account is active.

    When you delete your account (Profile → Settings → Your data & privacy), your profile, recommendations, trips, lists, collections, comments, likes, photos, friend connections and notification settings are deleted immediately. Copies may remain in our providers' routine backups for a short period until those are overwritten, and we may keep a minimal record of reports and safety actions where we need to for legal reasons.

    7. International transfers
    Our providers may process data outside the UK and European Economic Area. Where they do, we rely on appropriate safeguards such as the UK International Data Transfer Agreement or Standard Contractual Clauses.

    8. Your rights
    Under UK and EU data protection law you can: access a copy of your data; correct it; delete it; export it in a portable format; restrict or object to processing; and withdraw consent at any time.

    Two of these you can exercise yourself, immediately: Profile → Settings → Your data & privacy → Download my data, or Delete my account. For anything else, email support@find-rex.com.

    9. Complaints
    If you're unhappy with how we handle your data, email support@find-rex.com and we'll acknowledge it and investigate. If you're still unsatisfied you can complain to the Information Commissioner's Office (ico.org.uk) or your local supervisory authority.

    10. Children
    REX is not for under-16s. We don't knowingly collect data from them. If we learn we have, we'll delete it.

    11. Security
    We protect your information with access controls on our database, encrypted connections, and rules that limit what each account can read. No system is completely secure, and we can't guarantee absolute security.

    12. Changes
    We may update this policy. When we make a material change we'll ask you to review and agree to the new version in the App, and we keep a record of when you did.

    13. Contact
    Three Lines Studio Ltd
    support@find-rex.com
    Registered address: [TO CONFIRM — Kathryn to add the registered company address]
    """
}