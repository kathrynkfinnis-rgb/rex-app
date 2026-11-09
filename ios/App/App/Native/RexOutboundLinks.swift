import SwiftUI
import AppTrackingTransparency
// Oct 16, security review — `import AdSupport` was here with no
// ASIdentifierManager use anywhere in the app. Apple's scanner reads the
// import and expects an IDFA declaration, which would have contradicted the
// privacy label's "no tracking". Rex never reads the advertising identifier:
// the ATT prompt exists because of what a Skimlinks redirect does, not
// because we want an ID. See the note on isAffiliateProgrammeActive.

/// Sept 21 — affiliate links, and the permission they require.
///
/// Sept 24, from App Store review: the Info.plist key that goes with this
/// (NSUserTrackingUsageDescription) has been REMOVED. Apple refuses a
/// submission where the binary says it may ask to track but the privacy
/// label says it doesn't — and with no affiliate programme approved, the
/// label is the one telling the truth. Put the key back in the same breath
/// as flipping isAffiliateProgrammeActive, or the submission bounces.
///
/// When someone taps through to a shop from Rex, we can earn a commission on
/// what they buy. Skimlinks does the work: hand it any outbound link and it
/// turns the ones from merchants it covers into affiliate links, leaving
/// everything else alone.
///
/// Two rules shape all of this, and both are load-bearing:
///
/// 1. **Apple requires permission first.** A Skimlinks redirect is tracking
///    under App Tracking Transparency — it lets a third party follow someone
///    from Rex to a purchase. So the system prompt has to be shown and
///    allowed *before* the first link is ever rewritten. Shipping without it
///    is one of the most reliable ways to be rejected, and Apple tests for it.
///
/// 2. **A refusal costs the person nothing.** Say no and the plain link opens,
///    immediately, exactly as before. The only difference is that we don't get
///    paid. Nothing is withheld, nothing nags, and nothing is degraded.
///
/// We never read the advertising identifier ourselves. Permission is asked
/// because of what the redirect does, not because Rex wants an ID.
enum RexOutboundLink {
    /// Sept 22 — Skimlinks turned find-rex.com down: no original content and
    /// no traffic, which is exactly what their published criteria say they
    /// reject. Until some affiliate network approves us there is nothing to
    /// earn, so the whole thing is dormant: links open directly, and nobody
    /// is asked for permission to track them for revenue that doesn't exist.
    ///
    /// Everything below is kept, working, behind this one flag. Flip it back
    /// on the day an application is accepted — and update the privacy policy
    /// and the App Store privacy label in the same breath, because both
    /// currently say, truthfully, that Rex does no tracking at all.
    static let isAffiliateProgrammeActive = false

    /// From the Skimlinks dashboard: publisher 309502, site X1797857.
    private static let skimlinksId = "309502X1797857"

    // MARK: - Amazon Associates

    /// Oct 20 — "sort out the amazon affiliate link".
    ///
    /// Amazon Associates is not the same shape as Skimlinks and is worth
    /// keeping separate rather than folding into the flag above.
    ///
    /// Skimlinks bounces the person through go.skimresources.com, which lets
    /// a third party watch them travel from Rex to a purchase. That is
    /// tracking under App Tracking Transparency, which is why everything
    /// above waits on a system prompt. An Associates tag is a query
    /// parameter on a link to Amazon that the person was already opening:
    /// no third party, no redirect, no identifier, and nothing about them
    /// sent anywhere. So this path does not ask, and does not need
    /// NSUserTrackingUsageDescription back in Info.plist.
    ///
    /// Two things it does need, neither of them code, both noted in full in
    /// the brief that goes with this:
    ///
    ///   * An approved Associates account per region. The tag is per store —
    ///     a .co.uk tag earns nothing on .com — and approval requires three
    ///     qualifying sales within 180 days or the account is closed.
    ///   * The disclosure Amazon's Operating Agreement requires, displayed
    ///     where people see the links. AffiliateLinksSection carries it.
    ///
    /// Empty until a tag exists: an unapproved or misspelled tag earns
    /// nothing and is indistinguishable from a working one, so the only safe
    /// default is to add no parameter at all and leave the link exactly as
    /// the person wrote it.
    /// Oct 20 — findrex-21, the UK store. The suffix is the store: -21 is
    /// amazon.co.uk, -20 is amazon.com.
    ///
    /// The others stay empty deliberately rather than being filled with the
    /// same string. Every Amazon store is a separate Associates account with
    /// its own tag, and the EU locales share the -21 suffix without sharing
    /// the tag — findrex-21 on amazon.de is simply an unrecognised tag, which
    /// earns nothing and looks exactly like one that works. An empty entry
    /// leaves the link untouched, which is the honest version of the same
    /// outcome and the one that cannot be mistaken for working.
    private static let amazonTags: [String: String] = [
        "amazon.co.uk": "findrex-21",
        "amazon.com": "",
        "amazon.de": "",
        "amazon.fr": "",
        "amazon.es": "",
        "amazon.it": "",
        "amazon.ie": "",
    ]

    /// Oct 20 — "can we have affiliate revenue up and running in the
    /// TestFlight version (99) but not the live App Store version".
    ///
    /// The same binary goes to both, so this cannot be a build setting. What
    /// distinguishes them at runtime is the receipt: TestFlight installs get
    /// one named sandboxReceipt, App Store installs get one named receipt.
    /// That is the standard way to tell, and it is what gates the tag below.
    ///
    /// It happened to be true already — every line of the Amazon work landed
    /// after build 98 was cut, so the build in review has none of it — but
    /// "happened to be true" is not a property you can rely on twice. This
    /// makes it a fact about the code instead of a fact about the order
    /// things were committed in.
    ///
    /// To go live for everyone: delete this property and the two references
    /// to it. Before doing that, read the note on isAffiliateProgrammeActive
    /// about the privacy label — it does not apply to Amazon, which shares
    /// nothing, but it is the thing to check rather than assume.
    /// Nov 6 — "I would like to turn on affiliate revenue." The TestFlight
    /// gate that used to be here is gone, which is what that means: the tag
    /// now goes on for everybody, App Store builds included.
    ///
    /// Why it was safe to remove, in the order the note above asked for it to
    /// be checked:
    ///
    ///   * The privacy label does not change. That warning belongs to
    ///     Skimlinks, which bounces people through go.skimresources.com and
    ///     is tracking under ATT. An Associates tag is a query parameter on a
    ///     link to Amazon the person was already opening — no redirect, no
    ///     third party, no identifier, nothing about them sent anywhere. So
    ///     no NSUserTrackingUsageDescription and no ATT prompt, and the label
    ///     still truthfully says Rex does no tracking.
    ///   * The disclosure Amazon's Operating Agreement requires is already
    ///     where the links are: AmazonDisclosure at the foot of every item
    ///     page that carries one, plus AffiliateLinksSection in Privacy and
    ///     data. Both key off this property, so they appear in the same
    ///     builds that tag.
    ///
    /// And why now rather than later: approval needs three qualifying sales
    /// inside 180 days of applying or the account is closed, and a gate that
    /// hid the links from everyone except TestFlight was guaranteeing zero of
    /// them. The links have to reach real people for the account to survive.
    ///
    /// Still the one honest condition — that a tag actually exists. An
    /// unapproved or misspelled tag earns nothing and looks exactly like a
    /// working one, so a store with no tag leaves its links untouched.
    static var isAmazonAssociateActive: Bool {
        amazonTags.values.contains { !$0.isEmpty }
    }

    /// The tag for whichever Amazon store this URL points at, matching on the
    /// registrable domain so www., smile. and m. all resolve the same way.
    private static func amazonTag(for host: String) -> String? {
        guard isAmazonAssociateActive else { return nil }
        let lower = host.lowercased()
        for (domain, tag) in amazonTags where !tag.isEmpty {
            if lower == domain || lower.hasSuffix(".\(domain)") { return tag }
        }
        // Oct 22 — Amazon's own share button hands out amzn.eu/d/02Xq9dK and
        // amzn.to/…, which are Amazon and were matching none of the above. A
        // link somebody shared from the Amazon app was the one link we did not
        // tag. They redirect to a regional store, so the UK tag is the right
        // one to use on a short link reached from a UK phone.
        if lower == "amzn.eu" || lower == "amzn.to"
            || lower.hasSuffix(".amzn.eu") || lower.hasSuffix(".amzn.to") {
            return amazonTags["amazon.co.uk"].flatMap { $0.isEmpty ? nil : $0 }
        }
        return nil
    }

    /// Oct 22 — "I want to be able to take a share link from amazon and then
    /// that fill in the details and then the pill is automatically our revenue
    /// generating link."
    ///
    /// The last part needs the ASIN, which is the one thing an Amazon URL
    /// always carries however it is shaped: /dp/B0XXXX, /gp/product/B0XXXX,
    /// /gp/aw/d/B0XXXX, or a short link once it has resolved. From it we can
    /// build the canonical product address with our tag on it, which is a
    /// better thing to store than whatever tracking the share button attached.
    static func amazonASIN(in url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host.contains("amazon.") || host.contains("amzn.")
        else { return nil }
        let segments = url.path.split(separator: "/").map(String.init)
        for (index, segment) in segments.enumerated() {
            guard ["dp", "d", "product", "gp"].contains(segment.lowercased()) else { continue }
            // The id is the next segment that looks like one: ten characters
            // of digits and capitals. "gp/product/B0XXXX" has one in between.
            for candidate in segments.dropFirst(index + 1).prefix(2) where isASIN(candidate) {
                return candidate.uppercased()
            }
        }
        // Some paths carry it with no marker at all.
        return segments.first(where: isASIN)?.uppercased()
    }

    private static func isASIN(_ candidate: String) -> Bool {
        candidate.count == 10
            && candidate.allSatisfy { $0.isNumber || ($0.isLetter && $0.isUppercase) }
    }

    /// The clean product address for an ASIN, tagged. Replaces a share link's
    /// tracking parameters rather than adding to them.
    static func amazonProductURL(asin: String) -> URL? {
        guard isAmazonAssociateActive,
              let tag = amazonTags["amazon.co.uk"], !tag.isEmpty
        else { return URL(string: "https://www.amazon.co.uk/dp/\(asin)") }
        return URL(string: "https://www.amazon.co.uk/dp/\(asin)?tag=\(tag)")
    }

    /// Oct 20 — "say I recommend a book and Phoebe buys it — do we need a
    /// link to 'buy on amazon'". Yes, and it has to be built rather than
    /// pasted: book search comes from Google Books and sets no product link
    /// at all, so a book added the normal way has nothing to tap.
    ///
    /// A search link rather than a product page, because a product page needs
    /// the ASIN, which needs Amazon's Product Advertising API, which they
    /// only grant after three qualifying sales — the same three sales this is
    /// meant to produce. Search links are permitted and track identically.
    ///
    /// `department` narrows the results: film and TV go to Prime Video, where
    /// renting or buying is the thing that actually earns, rather than to a
    /// shelf of DVDs.
    static func amazonSearch(for query: String, department: String? = nil) -> URL? {
        guard isAmazonAssociateActive,
              let tag = amazonTags["amazon.co.uk"], !tag.isEmpty,
              var components = URLComponents(string: "https://www.amazon.co.uk/s")
        else { return nil }
        let cleaned = query
            .replacingOccurrences(of: "·", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        components.queryItems = [URLQueryItem(name: "k", value: cleaned)]
            + (department.map { [URLQueryItem(name: "i", value: $0)] } ?? [])
            + [URLQueryItem(name: "tag", value: tag)]
        return components.url
    }

    /// Oct 22 — hoisted out of ItemDetailView, which had it privately, so the
    /// wish list could offer the same thing without a second copy of the
    /// rules. Two screens quietly disagreeing about which categories are
    /// buyable, or about whether a film says Buy or Rent, is the kind of
    /// drift nobody notices until a tester does.
    ///
    /// Nil for a place, a trip, a recipe or a podcast: Amazon has nothing to
    /// sell for the first three, and a podcast is free.
    static func amazonSearch(forTitle title: String, subtitle: String?, category: RexCategory) -> URL? {
        switch category {
        case .book:
            // Title and author. A book's subtitle is the author, sometimes
            // followed by "· year" — Amazon matches against product titles,
            // and the year only narrows it wrongly.
            let author = (subtitle ?? "").split(separator: "·").first.map(String.init) ?? ""
            return amazonSearch(for: "\(title) \(author.trimmingCharacters(in: .whitespaces))")
        case .movie, .tv:
            // Title alone — a film's subtitle is its director and year, which
            // is not printed on anything Amazon sells. instant-video is where
            // renting and buying happens; the alternative is a shelf of DVDs.
            return amazonSearch(for: title, department: "instant-video")
        case .other:
            return amazonSearch(for: title)
        default:
            return nil
        }
    }

    /// Whether this category gets an Amazon link at all — the same question
    /// amazonSearch answers, asked without needing a title to hand. Used to
    /// decide whether a screen has anything to disclose.
    static func amazonLabelApplies(to category: RexCategory) -> Bool {
        switch category {
        case .book, .movie, .tv, .other: return true
        default: return false
        }
    }

    /// Honest about what the link does. "Find" rather than "Buy" on a product,
    /// because a product in Other might be a board game Amazon stocks or a
    /// particular small-producer olive oil it has never heard of, and a search
    /// that returns nothing is a smaller broken promise than a Buy button that
    /// does. "Rent or buy" on a film, because sending somebody to pay for
    /// something already included with their subscription is a worse answer
    /// than the provider row they could have read instead.
    static func amazonLabel(for category: RexCategory) -> String {
        switch category {
        case .book: return "Buy on Amazon"
        case .movie, .tv: return "Rent or buy on Amazon"
        default: return "Find on Amazon"
        }
    }

    /// Adds the Associates tag, or returns nil if this isn't an Amazon link
    /// we have a tag for. An existing `tag` is left alone: it is somebody
    /// else's, and overwriting another creator's attribution to take their
    /// commission is not a thing Rex should do quietly.
    static func amazonTagged(_ url: URL) -> URL? {
        guard let host = url.host, let tag = amazonTag(for: host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        var items = components.queryItems ?? []
        guard !items.contains(where: { $0.name == "tag" }) else { return nil }
        items.append(URLQueryItem(name: "tag", value: tag))
        components.queryItems = items
        return components.url
    }

    /// Asked once, the first time someone actually taps through to a shop —
    /// not at launch, where it arrives with no context and is refused out of
    /// hand. iOS only ever shows the real prompt once per install; after that
    /// this returns the standing answer.
    @discardableResult
    static func requestTrackingPermissionIfNeeded() async -> ATTrackingManager.AuthorizationStatus {
        let status = ATTrackingManager.trackingAuthorizationStatus
        guard isAffiliateProgrammeActive, status == .notDetermined else { return status }
        return await ATTrackingManager.requestTrackingAuthorization()
    }

    static var isTrackingAllowed: Bool {
        ATTrackingManager.trackingAuthorizationStatus == .authorized
    }

    /// The URL to actually open. Only ever decorated for http(s) links, and
    /// only when the person has said yes — anything else is returned untouched.
    static func resolved(_ url: URL) -> URL {
        // Amazon first, and without asking: a tag on a link to the shop the
        // person already chose is not tracking, so making them sit through a
        // permission prompt to earn it would be asking for something we don't
        // need. If they said no to Skimlinks, this still applies — the answer
        // they gave was about being followed by a third party.
        if let tagged = amazonTagged(url) { return tagged }

        guard isAffiliateProgrammeActive,
              isTrackingAllowed,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              // Our own links have nothing to earn and shouldn't be bounced
              // through a third party on the way.
              url.host?.hasSuffix("find-rex.com") != true,
              let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let redirect = URL(string: "https://go.skimresources.com/?id=\(skimlinksId)&url=\(encoded)")
        else { return url }
        return redirect
    }

    /// Ask (if we haven't), then open. The link opens either way — the answer
    /// only decides whether it goes the long way round.
    @MainActor
    static func open(_ url: URL, using openURL: OpenURLAction) async {
        await requestTrackingPermissionIfNeeded()
        openURL(resolved(url))
    }
}

/// A link to somewhere outside Rex, opened through the affiliate layer.
///
/// Drop-in for SwiftUI's `Link`: same call shape, but it asks for tracking
/// permission the first time and decorates the URL when allowed.
struct RexOutboundLinkButton<Label: View>: View {
    let url: URL
    @ViewBuilder var label: () -> Label

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Task { await RexOutboundLink.open(url, using: openURL) }
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityHint(url.host ?? "")
    }
}

/// Nov 9 — "can we find a way to easily add an affiliate linked Amazon link?"
///
/// There was nothing to add: a link somebody pastes into a blast reply, a
/// note or a list is already an Amazon link, and `resolved` already knows how
/// to tag one. What was missing is that none of those taps ever reached it.
/// `RexOutboundLinkButton` covers the buttons the app draws itself — "Buy on
/// Amazon" on an item page — and user-written text goes through `linkified`,
/// which hands the raw URL straight to the system.
///
/// So every Amazon link anyone has pasted into a comment has earned nothing.
///
/// This is deliberately not applied at the app root, where it would also sit
/// over every internal `openURL` call. It goes on the views that render text
/// somebody typed, which is where pasted links live.
///
/// `resolved` leaves anything that isn't a shop we have a tag for exactly as
/// it was, and it will not overwrite a `tag` already on the URL — taking
/// another creator's commission is not something to do quietly.
extension View {
    func rexOutboundLinks() -> some View {
        environment(\.openURL, OpenURLAction { url in
            .systemAction(RexOutboundLink.resolved(url))
        })
    }
}

/// Oct 22 — "do we need to declare anything if we are earning affiliate
/// revenue?" Yes: Amazon's Operating Agreement requires the relationship
/// stated clearly and conspicuously, and under the CAP Code an affiliate link
/// is a marketing communication that has to be obviously identifiable as one.
///
/// Build 100 had the words, but only in Settings → Your data & privacy, two
/// taps deep on a screen nobody opens — while the links themselves sit on item
/// cards and wish lists. A disclosure the reader never reaches is not a
/// disclosure.
///
/// At the foot of the screen rather than against the button, Kathryn's call:
/// it is on the same page as the link, which is what is being asked for,
/// without putting a commercial note next to a friend's recommendation.
///
/// Renders nothing when no tag is configured, which includes every App Store
/// build — claiming a commission we are not earning would be its own small
/// untruth.
struct AmazonDisclosure: View {
    var body: some View {
        if RexOutboundLink.isAmazonAssociateActive {
            Text("Some links here go to Amazon. Rex may earn a commission on what you buy, at no cost to you \u{2014} it never changes what your friends recommend or the order you see it in.")
                .font(RexFont.text(11.5))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, RexSpacing.page)
                .padding(.top, RexSpacing.lg)
                .padding(.bottom, RexSpacing.md)
        }
    }
}

/// Settings → Your data & privacy. Someone who said no — or yes — should be
/// able to find out what that meant and change their mind, without having to
/// know the answer lives in iOS Settings.
struct AffiliateLinksSection: View {
    @Environment(\.openURL) private var openURL
    @State private var status = ATTrackingManager.trackingAuthorizationStatus

    private var summary: String {
        // With only Amazon live there is no permission to describe — nothing
        // was asked and nothing is being tracked — so the ATT wording below
        // would be describing a prompt that never appears.
        if !RexOutboundLink.isAffiliateProgrammeActive {
            return "Some shop links earn Rex a small commission. It never costs you anything, it never changes what your friends recommend or the order you see it in, and nothing about you is shared with anyone."
        }
        switch status {
        case .authorized:
            return "Shop links you tap may earn Rex a small commission. It never costs you anything, and it never changes what your friends recommend or the order you see it in."
        case .denied, .restricted:
            return "Shop links open directly, and Rex earns nothing from them. Nothing about the app is any different."
        default:
            return "The first time you tap through to a shop, we'll ask. Saying no changes nothing about how Rex works."
        }
    }

    var body: some View {
        // Oct 20 — this used to appear only when Skimlinks was live. Amazon
        // Associates needs it too, and for a stronger reason: their Operating
        // Agreement requires the disclosure to be displayed, so a live tag
        // with this section hidden is a breach of the terms rather than just
        // an omission. Either programme being on is enough to show it.
        if RexOutboundLink.isAffiliateProgrammeActive || RexOutboundLink.isAmazonAssociateActive {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text("Shop links")
                .font(RexFont.text(14, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text(summary)
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            // The wording Amazon require, near enough verbatim — this is one
            // of the few places where the phrasing is not ours to improve.
            if RexOutboundLink.isAmazonAssociateActive {
                Text("As an Amazon Associate, Rex earns from qualifying purchases.")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // iOS only shows its own prompt once, so after that the only way
            // to change the answer is Settings. Say so plainly rather than
            // offering a button that would do nothing.
            if RexOutboundLink.isAffiliateProgrammeActive, status != .notDetermined {
                Button("Change this in iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(RexFont.text(13, weight: .semibold))
                .foregroundStyle(RexColor.primary)
                .buttonStyle(.plain)
            }
        }
        .padding(RexSpacing.md)
        .rexCard()
        .task { status = ATTrackingManager.trackingAuthorizationStatus }
        }
    }
}
