import SwiftUI
import AppTrackingTransparency
import AdSupport

/// Sept 21 — affiliate links, and the permission they require.
///
/// Sept 24, from App Store review: the Info.plist key that goes with this
/// (NSUserTrackingUsageDescription) has been REMOVED. Apple refuses a
/// submission where the binary says it may ask to track but the privacy
/// label says it doesn't — and with no affiliate programme approved, the
/// label is the one telling the truth. Put the key back in the same breath
/// as flipping isAffiliateProgrammeActive, or the submission bounces.
///
/// When someone taps through to a shop from REX, we can earn a commission on
/// what they buy. Skimlinks does the work: hand it any outbound link and it
/// turns the ones from merchants it covers into affiliate links, leaving
/// everything else alone.
///
/// Two rules shape all of this, and both are load-bearing:
///
/// 1. **Apple requires permission first.** A Skimlinks redirect is tracking
///    under App Tracking Transparency — it lets a third party follow someone
///    from REX to a purchase. So the system prompt has to be shown and
///    allowed *before* the first link is ever rewritten. Shipping without it
///    is one of the most reliable ways to be rejected, and Apple tests for it.
///
/// 2. **A refusal costs the person nothing.** Say no and the plain link opens,
///    immediately, exactly as before. The only difference is that we don't get
///    paid. Nothing is withheld, nothing nags, and nothing is degraded.
///
/// We never read the advertising identifier ourselves. Permission is asked
/// because of what the redirect does, not because REX wants an ID.
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
    /// currently say, truthfully, that REX does no tracking at all.
    static let isAffiliateProgrammeActive = false

    /// From the Skimlinks dashboard: publisher 309502, site X1797857.
    private static let skimlinksId = "309502X1797857"

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

/// A link to somewhere outside REX, opened through the affiliate layer.
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

/// Settings → Your data & privacy. Someone who said no — or yes — should be
/// able to find out what that meant and change their mind, without having to
/// know the answer lives in iOS Settings.
struct AffiliateLinksSection: View {
    @Environment(\.openURL) private var openURL
    @State private var status = ATTrackingManager.trackingAuthorizationStatus

    private var summary: String {
        switch status {
        case .authorized:
            return "Shop links you tap may earn REX a small commission. It never costs you anything, and it never changes what your friends recommend or the order you see it in."
        case .denied, .restricted:
            return "Shop links open directly, and REX earns nothing from them. Nothing about the app is any different."
        default:
            return "The first time you tap through to a shop, we'll ask. Saying no changes nothing about how REX works."
        }
    }

    var body: some View {
        if RexOutboundLink.isAffiliateProgrammeActive {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            Text("Shop links")
                .font(RexFont.text(14, weight: .semibold))
                .foregroundStyle(RexColor.foreground)
            Text(summary)
                .font(RexFont.text(13))
                .foregroundStyle(RexColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            // iOS only shows its own prompt once, so after that the only way
            // to change the answer is Settings. Say so plainly rather than
            // offering a button that would do nothing.
            if status != .notDetermined {
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
